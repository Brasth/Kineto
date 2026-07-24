import Foundation

/// Normalized catalog item from PetDex. Slugs are the stable identity.
struct PetDexCatalogItem: Codable, Equatable, Identifiable, Sendable {
    var id: String { slug }
    let slug: String
    let displayName: String
    let kind: String
    let creator: String?
    let spritesheetURL: URL
    let petJSONURL: URL
}

/// Supported atlas layouts derived strictly from pixel dimensions.
enum PetDexAtlasLayout: String, Codable, Sendable {
    case classic8x9
    case v2_8x11
}

/// A validated, locally installed pet selection.
/// ID format: "<slug>@<lowercase SHA-256 of sprite bytes>"
struct PetDexInstalledPet: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let item: PetDexCatalogItem
    let spriteSHA256: String
    let spriteFilename: String  // "spritesheet.webp" or "spritesheet.png"
    let pixelWidth: Int
    let pixelHeight: Int
    let layout: PetDexAtlasLayout
}

/// Snapshot of the fetched catalog for persistence and UI.
struct PetDexCatalogSnapshot: Codable, Equatable, Sendable {
    let schemaVersion: Int  // exactly 1
    let fetchedAt: Date
    let items: [PetDexCatalogItem]
}

enum PetDexCatalogSearch {
    static func matching(
        _ pets: [PetDexCatalogItem],
        query: String
    ) -> [PetDexCatalogItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return pets }

        return pets.filter { pet in
            pet.displayName.localizedCaseInsensitiveContains(trimmedQuery)
                || pet.slug.localizedCaseInsensitiveContains(trimmedQuery)
                || (pet.creator?.localizedCaseInsensitiveContains(trimmedQuery) ?? false)
        }
    }
}
