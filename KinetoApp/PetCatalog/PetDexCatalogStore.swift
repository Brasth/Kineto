import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

actor PetDexCatalogStore {
    private let root: URL
    private let selectedDir: URL
    private let fileManager = FileManager.default

    private var catalogURL: URL { root.appendingPathComponent("catalog-v1.json") }

    init(root: URL) {
        self.root = root
        self.selectedDir = root.appendingPathComponent("Selected", isDirectory: true)
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: selectedDir, withIntermediateDirectories: true)
    }

    func loadCachedCatalog() async -> PetDexCatalogSnapshot? {
        guard let data = try? Data(contentsOf: catalogURL) else { return nil }
        return try? JSONDecoder().decode(PetDexCatalogSnapshot.self, from: data)
    }

    func saveCatalog(_ snapshot: PetDexCatalogSnapshot) async throws {
        let data = try JSONEncoder().encode(snapshot)
        let temp = catalogURL.appendingPathExtension("tmp-\(UUID().uuidString)")
        try data.write(to: temp, options: .atomic)
        try synchronizeFile(temp)
        if fileManager.fileExists(atPath: catalogURL.path) {
            _ = try fileManager.replaceItemAt(catalogURL, withItemAt: temp)
        } else {
            try fileManager.moveItem(at: temp, to: catalogURL)
        }
        try synchronizeFile(catalogURL)
    }

    func loadInstalledPet() async -> PetDexInstalledPet? {
        let metaURL = selectedDir.appendingPathComponent("metadata.json")
        guard let metaData = try? Data(contentsOf: metaURL),
              let pet = try? JSONDecoder().decode(PetDexInstalledPet.self, from: metaData)
        else { return nil }

        let spriteURL = selectedDir.appendingPathComponent(pet.spriteFilename)
        guard fileManager.fileExists(atPath: spriteURL.path) else { return nil }
        guard let spriteData = try? Data(contentsOf: spriteURL) else { return nil }
        guard sha256(of: spriteData) == pet.spriteSHA256 else { return nil }
        guard let dims = imageDimensions(of: spriteData) else { return nil }
        guard dims.width == pet.pixelWidth && dims.height == pet.pixelHeight else { return nil }
        return pet
    }

    func saveInstalledPet(_ pet: PetDexInstalledPet, spriteData: Data) async throws {
        let stageDir = root.appendingPathComponent(".Selected.stage-\(UUID().uuidString)")
        let backupDir = root.appendingPathComponent(".Selected.backup-\(UUID().uuidString)")
        try fileManager.createDirectory(at: stageDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stageDir) }

        let stageMeta = stageDir.appendingPathComponent("metadata.json")
        let stageSprite = stageDir.appendingPathComponent(pet.spriteFilename)

        let metaData = try JSONEncoder().encode(pet)
        try metaData.write(to: stageMeta, options: .atomic)
        try spriteData.write(to: stageSprite, options: .atomic)
        try synchronizeFile(stageMeta)
        try synchronizeFile(stageSprite)

        guard let loaded = try? Data(contentsOf: stageMeta),
              let p = try? JSONDecoder().decode(PetDexInstalledPet.self, from: loaded),
              p.id == pet.id,
              let sdata = try? Data(contentsOf: stageSprite),
              sha256(of: sdata) == pet.spriteSHA256
        else {
            throw NSError(domain: "KinetoPetCatalog", code: 3, userInfo: [NSLocalizedDescriptionKey: "Staged pet validation failed"])
        }

        if fileManager.fileExists(atPath: selectedDir.path) {
            try fileManager.moveItem(at: selectedDir, to: backupDir)
        }
        do {
            try fileManager.moveItem(at: stageDir, to: selectedDir)
            try synchronizeDirectory(selectedDir)
            try? fileManager.removeItem(at: backupDir)
        } catch {
            if fileManager.fileExists(atPath: backupDir.path) {
                try? fileManager.moveItem(at: backupDir, to: selectedDir)
            }
            throw error
        }
    }

    func clearSelection() async {
        let meta = selectedDir.appendingPathComponent("metadata.json")
        try? fileManager.removeItem(at: meta)
        let webp = selectedDir.appendingPathComponent("spritesheet.webp")
        let png = selectedDir.appendingPathComponent("spritesheet.png")
        try? fileManager.removeItem(at: webp)
        try? fileManager.removeItem(at: png)
    }

    private func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func imageDimensions(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let w = props[kCGImagePropertyPixelWidth as String] as? Int,
              let h = props[kCGImagePropertyPixelHeight as String] as? Int
        else { return nil }
        return (w, h)
    }

    private func synchronizeFile(_ url: URL) throws {
        let fd = open(url.path, O_RDONLY)
        if fd >= 0 { fsync(fd); close(fd) }
    }

    private func synchronizeDirectory(_ url: URL) throws {
        let fd = open(url.path, O_RDONLY)
        if fd >= 0 { fsync(fd); close(fd) }
    }
}
