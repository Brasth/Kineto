import XCTest
@testable import Kineto

// Local mirror of the v2 snapshot JSON shape (PetSettingsSnapshot itself is private in AppModel).
private struct TestPetSnapshot: Codable, Equatable {
    let version: Int
    let enabled: Bool?
    let selectedPetID: String?
    let size: String?
    let motion: String?
}

@MainActor
final class PetSettingsSnapshotMigrationTests: XCTestCase {
    private let settingsKey = "kineto.petSettings"
    private let legacyKeys = [
        "kineto.petModeEnabled",
        "kineto.petAppearance",
        "kineto.petSize",
        "kineto.petMotion",
        "kineto.petAccent"
    ]

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: settingsKey)
        for k in legacyKeys {
            UserDefaults.standard.removeObject(forKey: k)
        }
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: settingsKey)
        for k in legacyKeys {
            UserDefaults.standard.removeObject(forKey: k)
        }
        super.tearDown()
    }

    func testV2SelectedPetIDIsPreservedThroughRestoreAndPublicSetters() {
        // Seed v2 via raw JSON (never reference the private PetSettingsSnapshot)
        let v2JSON = "{\"version\":2,\"enabled\":true,\"selectedPetID\":\"slug@deadbeef\",\"size\":\"large\",\"motion\":\"static\"}"
        UserDefaults.standard.set(Data(v2JSON.utf8), forKey: settingsKey)

        let model = AppModel()

        // Public observable state after restore
        XCTAssertTrue(model.petModeEnabled)
        XCTAssertEqual(model.petSize, .large)
        XCTAssertEqual(model.petMotion, .static)

        // Trigger real persistence path via public setters
        let originalEnabled = model.petModeEnabled
        model.petModeEnabled = !originalEnabled
        model.petModeEnabled = originalEnabled

        guard let written = UserDefaults.standard.data(forKey: settingsKey),
              let snap = try? JSONDecoder().decode(TestPetSnapshot.self, from: written) else {
            XCTFail("no persisted snapshot")
            return
        }
        XCTAssertEqual(snap.version, 2)
        XCTAssertEqual(snap.selectedPetID, "slug@deadbeef")
    }

    func testV1SnapshotMigratesToV2WithSelectionCleared() {
        // Legacy v1 data + old snapshot shape
        UserDefaults.standard.set(true, forKey: "kineto.petModeEnabled")
        let v1JSON = "{\"version\":1,\"enabled\":true,\"appearance\":\"signal\",\"size\":\"standard\",\"motion\":\"subtle\",\"accent\":\"#00C7BE\"}"
        UserDefaults.standard.set(Data(v1JSON.utf8), forKey: settingsKey)

        let model = AppModel()

        // Trigger persist via public setter
        model.petModeEnabled = true
        model.petModeEnabled = false

        guard let written = UserDefaults.standard.data(forKey: settingsKey),
              let snap = try? JSONDecoder().decode(TestPetSnapshot.self, from: written) else {
            XCTFail("no snapshot after v1->v2")
            return
        }
        XCTAssertEqual(snap.version, 2)
        XCTAssertEqual(snap.enabled, false)
        XCTAssertNil(snap.selectedPetID)
    }

    func testFutureVersionSnapshotIsLeftByteForByteUnchanged() {
        let futureJSON = "{\"version\":99,\"enabled\":true,\"selectedPetID\":\"must-keep-exactly\",\"size\":\"compact\",\"motion\":\"subtle\"}"
        let futureData = Data(futureJSON.utf8)
        UserDefaults.standard.set(futureData, forKey: settingsKey)

        _ = AppModel()

        XCTAssertEqual(UserDefaults.standard.data(forKey: settingsKey), futureData)
    }
}

private actor StubPetCatalogRepository: PetCatalogRepository {
    private let cached: PetDexCatalogSnapshot
    private let installed: PetDexInstalledPet
    private(set) var refreshCount = 0
    private(set) var installedSlugs: [String] = []

    init(cached: PetDexCatalogSnapshot, installed: PetDexInstalledPet) {
        self.cached = cached
        self.installed = installed
    }

    func loadCachedCatalog() async -> PetDexCatalogSnapshot? {
        cached
    }

    func refreshCatalog() async throws -> PetDexCatalogSnapshot {
        refreshCount += 1
        return cached
    }

    func install(slug: String) async throws -> PetDexInstalledPet {
        installedSlugs.append(slug)
        return installed
    }

    func loadInstalledPet(id: String) async -> PetDexInstalledPet? {
        nil
    }

    func installedSlugRequests() -> [String] {
        installedSlugs
    }

    func refreshRequests() -> Int {
        refreshCount
    }
}

@MainActor
final class PetDexCatalogActionTests: XCTestCase {
    private func makeFixture() -> (PetDexCatalogSnapshot, PetDexInstalledPet) {
        let item = PetDexCatalogItem(
            slug: "boba",
            displayName: "Boba",
            kind: "cat",
            creator: "PetDex",
            spritesheetURL: URL(string: "https://assets.petdex.dev/pets/boba.webp")!,
            petJSONURL: URL(string: "https://assets.petdex.dev/pets/boba.json")!
        )
        let snapshot = PetDexCatalogSnapshot(
            schemaVersion: 1,
            fetchedAt: .now,
            items: [item]
        )
        let installed = PetDexInstalledPet(
            id: "boba@deadbeef",
            item: item,
            spriteSHA256: "deadbeef",
            spriteFilename: "spritesheet.webp",
            pixelWidth: 1536,
            pixelHeight: 1872,
            layout: .classic8x9
        )
        return (snapshot, installed)
    }

    func testPrepareUsesCacheWithoutRefreshingAndSelectInstallsTheChosenPet() async {
        let (snapshot, installed) = makeFixture()
        let repository = StubPetCatalogRepository(cached: snapshot, installed: installed)
        let model = AppModel(petCatalogRepository: repository)

        await model.preparePetCatalog()
        XCTAssertEqual(model.petCatalog, snapshot.items)
        let refreshesAfterPrepare = await repository.refreshRequests()
        XCTAssertEqual(refreshesAfterPrepare, 0)

        await model.refreshPetCatalog()
        let refreshesAfterRefresh = await repository.refreshRequests()
        XCTAssertEqual(refreshesAfterRefresh, 1)

        model.petModeEnabled = false
        await model.selectPet(slug: "boba")

        XCTAssertEqual(model.selectedPet, installed)
        XCTAssertFalse(model.petModeEnabled)
        XCTAssertNil(model.installingPetSlug)
        let installedSlugs = await repository.installedSlugRequests()
        XCTAssertEqual(installedSlugs, ["boba"])
    }

    func testCatalogSearchMatchesNameSlugAndCreatorWithWhitespaceTrimmed() {
        let pets = [
            PetDexCatalogItem(
                slug: "night-owl",
                displayName: "Night Owl",
                kind: "bird",
                creator: "Ari",
                spritesheetURL: URL(string: "https://assets.petdex.dev/pets/night-owl/sprite.webp")!,
                petJSONURL: URL(string: "https://assets.petdex.dev/pets/night-owl/pet.json")!
            ),
            PetDexCatalogItem(
                slug: "swift-fox",
                displayName: "Fox",
                kind: "mammal",
                creator: "Swift Studio",
                spritesheetURL: URL(string: "https://assets.petdex.dev/pets/swift-fox/sprite.webp")!,
                petJSONURL: URL(string: "https://assets.petdex.dev/pets/swift-fox/pet.json")!
            )
        ]

        XCTAssertEqual(
            PetDexCatalogSearch.matching(pets, query: "  owl ").map(\.slug),
            ["night-owl"]
        )
        XCTAssertEqual(
            PetDexCatalogSearch.matching(pets, query: "SWIFT").map(\.slug),
            ["swift-fox"]
        )
        XCTAssertEqual(PetDexCatalogSearch.matching(pets, query: "  "), pets)
    }
}