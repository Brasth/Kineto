import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

actor PetDexCatalogRepository: PetCatalogRepository {
    private let transport: any PetDexCatalogTransport
    private let store: PetDexCatalogStore

    init(transport: any PetDexCatalogTransport, store: PetDexCatalogStore) {
        self.transport = transport
        self.store = store
    }

    func loadCachedCatalog() async -> PetDexCatalogSnapshot? {
        await store.loadCachedCatalog()
    }

    func refreshCatalog() async throws -> PetDexCatalogSnapshot {
        let raw = try await transport.refreshCatalog()
        let snapshot = try parseManifest(raw)
        try await store.saveCatalog(snapshot)
        return snapshot
    }

    func install(slug: String) async throws -> PetDexInstalledPet {
        let (petJSONData, spriteData, itemData) = try await transport.downloadPet(slug: slug)

        let item = try parseCatalogItem(from: itemData, slug: slug)

        let petJSON = try? JSONSerialization.jsonObject(with: petJSONData) as? [String: Any]
        if let id = petJSON?["id"] as? String, id != slug {
            throw makeError(code: 3, message: "pet.json id mismatch")
        }

        guard let dims = imageDimensions(of: spriteData) else {
            throw makeError(code: 3, message: "Invalid sprite image")
        }
        let (pixelCount, pixelCountOverflowed) = dims.width.multipliedReportingOverflow(by: dims.height)
        guard !pixelCountOverflowed, pixelCount <= 25_000_000 else {
            throw makeError(code: 6, message: "Sprite too large")
        }
        guard let layout = deriveLayout(width: dims.width, height: dims.height) else {
            throw makeError(code: 3, message: "Unsupported sprite layout")
        }
        guard dims.width % 8 == 0 else {
            throw makeError(code: 3, message: "Width not divisible by 8")
        }
        let rowCount = (layout == .classic8x9) ? 9 : 11
        guard dims.height % rowCount == 0 else {
            throw makeError(code: 3, message: "Height mismatch for layout")
        }

        let digest = sha256(of: spriteData)
        let installedID = "\(slug)@\(digest)"
        let spriteFilename = spriteData.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "spritesheet.png" : "spritesheet.webp"

        let installed = PetDexInstalledPet(
            id: installedID,
            item: item,
            spriteSHA256: digest,
            spriteFilename: spriteFilename,
            pixelWidth: dims.width,
            pixelHeight: dims.height,
            layout: layout
        )

        try await store.saveInstalledPet(installed, spriteData: spriteData)
        return installed
    }

    func loadInstalledPet(id: String) async -> PetDexInstalledPet? {
        guard let pet = await store.loadInstalledPet(), pet.id == id else { return nil }
        return pet
    }

    private func parseManifest(_ data: Data) throws -> PetDexCatalogSnapshot {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let petsArray = json["pets"] as? [[String: Any]]
        else {
            throw makeError(code: 3, message: "Invalid catalog")
        }

        var items: [PetDexCatalogItem] = []
        var seen = Set<String>()

        for raw in petsArray {
            guard let slug = raw["slug"] as? String,
                  slug.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil,
                  let displayName = raw["displayName"] as? String, !displayName.isEmpty, displayName.unicodeScalars.count <= 80,
                  let kind = raw["kind"] as? String, kind.unicodeScalars.count <= 32,
                  let spritesheetStr = raw["spritesheetUrl"] as? String,
                  let petJsonStr = raw["petJsonUrl"] as? String,
                  let spritesheetURL = URL(string: spritesheetStr),
                  let petJSONURL = URL(string: petJsonStr)
            else { continue }

            let creator = raw["submittedBy"] as? String
            let item = PetDexCatalogItem(
                slug: slug,
                displayName: displayName,
                kind: kind,
                creator: creator,
                spritesheetURL: spritesheetURL,
                petJSONURL: petJSONURL
            )
            if seen.insert(slug).inserted {
                items.append(item)
            }
        }

        items.sort {
            let a = $0.displayName.lowercased()
            let b = $1.displayName.lowercased()
            if a != b { return a < b }
            return $0.slug < $1.slug
        }

        guard items.count <= 10_000 else {
            throw makeError(code: 3, message: "Catalog too large")
        }

        return PetDexCatalogSnapshot(schemaVersion: 1, fetchedAt: Date(), items: items)
    }

    private func parseCatalogItem(from data: Data, slug: String) throws -> PetDexCatalogItem {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let displayName = raw["displayName"] as? String,
              let kind = raw["kind"] as? String,
              let ss = raw["spritesheetUrl"] as? String,
              let pj = raw["petJsonUrl"] as? String,
              let ssURL = URL(string: ss),
              let pjURL = URL(string: pj)
        else {
            throw makeError(code: 3, message: "Invalid manifest item")
        }
        return PetDexCatalogItem(slug: slug, displayName: displayName, kind: kind, creator: raw["submittedBy"] as? String, spritesheetURL: ssURL, petJSONURL: pjURL)
    }

    private func deriveLayout(width: Int, height: Int) -> PetDexAtlasLayout? {
        guard width > 0, height > 0 else { return nil }
        let (classicWidth, classicWidthOverflowed) = width.multipliedReportingOverflow(by: 1872)
        let (classicHeight, classicHeightOverflowed) = height.multipliedReportingOverflow(by: 1536)
        if !classicWidthOverflowed, !classicHeightOverflowed, classicWidth == classicHeight {
            return .classic8x9
        }
        let (v2Width, v2WidthOverflowed) = width.multipliedReportingOverflow(by: 2288)
        let (v2Height, v2HeightOverflowed) = height.multipliedReportingOverflow(by: 1536)
        if !v2WidthOverflowed, !v2HeightOverflowed, v2Width == v2Height {
            return .v2_8x11
        }
        return nil
    }
    private func imageDimensions(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let w = props[kCGImagePropertyPixelWidth as String] as? Int,
              let h = props[kCGImagePropertyPixelHeight as String] as? Int
        else { return nil }
        return (w, h)
    }

    private func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func makeError(code: Int, message: String) -> NSError {
        NSError(domain: "KinetoPetCatalog", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

protocol PetCatalogRepository: Sendable {
    func loadCachedCatalog() async -> PetDexCatalogSnapshot?
    func refreshCatalog() async throws -> PetDexCatalogSnapshot
    func install(slug: String) async throws -> PetDexInstalledPet
    func loadInstalledPet(id: String) async -> PetDexInstalledPet?
}
