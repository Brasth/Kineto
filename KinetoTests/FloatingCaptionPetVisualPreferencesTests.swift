import AppKit
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Kineto

private struct UnusedPetCatalogTransport: PetDexCatalogTransport {
    func refreshCatalog() async throws -> Data {
        throw NSError(domain: "test", code: 1)
    }

    func downloadPet(slug: String) async throws -> (petJSON: Data, sprite: Data, manifestItem: Data) {
        throw NSError(domain: "test", code: 1)
    }
}

private struct FixturePetCatalogTransport: PetDexCatalogTransport {
    let petJSON: Data
    let sprite: Data
    let manifestItem: Data

    func refreshCatalog() async throws -> Data {
        Data()
    }

    func downloadPet(slug: String) async throws -> (petJSON: Data, sprite: Data, manifestItem: Data) {
        (petJSON, sprite, manifestItem)
    }
}

@MainActor
final class FloatingCaptionPetVisualPreferencesTests: XCTestCase {
    func testCompanionSizesAndMotionRespectAccessibility() {
        XCTAssertEqual(FloatingCaptionPetSize.compact.points, 48)
        XCTAssertEqual(FloatingCaptionPetSize.standard.points, 60)
        XCTAssertEqual(FloatingCaptionPetSize.large.points, 72)
        XCTAssertEqual(FloatingCaptionPetMotion.subtle.effective(reduceMotion: false), .subtle)
        XCTAssertEqual(FloatingCaptionPetMotion.subtle.effective(reduceMotion: true), .static)
        XCTAssertEqual(FloatingCaptionPetMotion.static.effective(reduceMotion: false), .static)
    }

    func testHiddenOverlayHasNoCompanionPreferences() {
        XCTAssertEqual(FloatingCaptionOverlayPresentation.hidden.caption.petState, .hidden)
        XCTAssertNil(FloatingCaptionOverlayPresentation.hidden.petVisualPreferences)
    }

    func testClassicAtlasUsesIdleRowZeroAndSixFrames() throws {
        let sheet = try makeSpritesheet(rowCount: 9)
        let frames = try PetDexSpriteFrameLoader.idleFrames(
            data: sheet,
            pet: makePet(data: sheet, layout: .classic8x9, rowCount: 9)
        )

        XCTAssertEqual(frames.count, 6)
        XCTAssertEqual(frames.map(sampleRed), [0, 1, 2, 3, 4, 5])
    }

    func testV2AtlasUsesIdleRowZeroAndSixFrames() throws {
        let sheet = try makeSpritesheet(rowCount: 11)
        let frames = try PetDexSpriteFrameLoader.idleFrames(
            data: sheet,
            pet: makePet(data: sheet, layout: .v2_8x11, rowCount: 11)
        )

        XCTAssertEqual(frames.count, 6)
        XCTAssertEqual(frames.map(sampleRed), [0, 1, 2, 3, 4, 5])
    }

    func testSpriteLoaderRejectsCorruptDataEvenWithMatchingDigest() {
        let corrupt = Data("not an image".utf8)
        XCTAssertThrowsError(
            try PetDexSpriteFrameLoader.idleFrames(
                data: corrupt,
                pet: makePet(data: corrupt, layout: .classic8x9, rowCount: 9)
            )
        )
    }

    func testCatalogStoreRoundTripsCacheAndRejectsCorruptSelection() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = PetDexCatalogStore(root: root)
        let sheet = try makeSpritesheet(rowCount: 9)
        let pet = makePet(data: sheet, layout: .classic8x9, rowCount: 9)
        let catalog = PetDexCatalogSnapshot(
            schemaVersion: 1,
            fetchedAt: .now,
            items: [pet.item]
        )

        try await store.saveCatalog(catalog)
        let cachedCatalog = await store.loadCachedCatalog()
        XCTAssertEqual(cachedCatalog?.items, [pet.item])

        try await store.saveInstalledPet(pet, spriteData: sheet)
        let installedPet = await store.loadInstalledPet()
        XCTAssertEqual(installedPet, pet)

        let spriteURL = root
            .appendingPathComponent("Selected", isDirectory: true)
            .appendingPathComponent(pet.spriteFilename)
        try Data("corrupt".utf8).write(to: spriteURL)
        let corruptInstalledPet = await store.loadInstalledPet()
        XCTAssertNil(corruptInstalledPet)
    }

    func testRepositoryDoesNotResolveMismatchedInstalledPetID() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = PetDexCatalogStore(root: root)
        let sheet = try makeSpritesheet(rowCount: 9)
        let pet = makePet(data: sheet, layout: .classic8x9, rowCount: 9)
        try await store.saveInstalledPet(pet, spriteData: sheet)

        let repository = PetDexCatalogRepository(
            transport: UnusedPetCatalogTransport(),
            store: store
        )
        let resolved = await repository.loadInstalledPet(id: "other@selection")
        XCTAssertNil(resolved)
    }

    func testRepositoryRejectsDivisibleSpriteWithUnsupportedAspectRatio() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let transport = FixturePetCatalogTransport(
            petJSON: Data(#"{"id":"bad"}"#.utf8),
            sprite: try makeSpritesheet(rowCount: 90),
            manifestItem: Data(
                #"{"displayName":"Bad","kind":"cat","spritesheetUrl":"https://assets.petdex.dev/pets/bad/spritesheet.png","petJsonUrl":"https://assets.petdex.dev/pets/bad/pet.json"}"#.utf8
            )
        )
        let repository = PetDexCatalogRepository(
            transport: transport,
            store: PetDexCatalogStore(root: root)
        )

        do {
            _ = try await repository.install(slug: "bad")
            XCTFail("Expected unsupported atlas layout to be rejected")
        } catch let error as NSError {
            XCTAssertEqual(error.domain, "KinetoPetCatalog")
            XCTAssertEqual(error.code, 3)
        }
    }

    private func makePet(
        data: Data,
        layout: PetDexAtlasLayout,
        rowCount: Int
    ) -> PetDexInstalledPet {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return PetDexInstalledPet(
            id: "fixture@\(digest)",
            item: PetDexCatalogItem(
                slug: "fixture",
                displayName: "Fixture",
                kind: "test",
                creator: nil,
                spritesheetURL: URL(string: "https://example.invalid/sprite.png")!,
                petJSONURL: URL(string: "https://example.invalid/pet.json")!
            ),
            spriteSHA256: digest,
            spriteFilename: "spritesheet.png",
            pixelWidth: 8,
            pixelHeight: rowCount,
            layout: layout
        )
    }

    private func makeSpritesheet(rowCount: Int) throws -> Data {
        var pixels = [UInt8](repeating: 0, count: 8 * rowCount * 4)
        for row in 0..<rowCount {
            for column in 0..<8 {
                let offset = (row * 8 + column) * 4
                pixels[offset] = UInt8(row == 0 ? column : 100 + row)
                pixels[offset + 3] = 255
            }
        }

        let image = try XCTUnwrap(
            CGImage(
                width: 8,
                height: rowCount,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: 8 * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: CGDataProvider(data: Data(pixels) as CFData)!,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        )
        let data = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(
                data,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func sampleRed(_ image: NSImage) -> UInt8 {
        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return pixel[0]
    }
}
