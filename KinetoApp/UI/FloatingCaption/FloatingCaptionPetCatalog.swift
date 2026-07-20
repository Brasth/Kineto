import Foundation

/// The semantic roles used by a pet's fixed pixel sprite.
enum FloatingCaptionPetPixelRole: String, CaseIterable, Sendable {
    case empty
    case outline
    case fill
    case face
    case blush
    case accent
    case highlight
}

/// A compact row-major pixel grid suitable for rendering with SwiftUI Canvas.
struct FloatingCaptionPetSprite: Equatable, Sendable {
    let width: Int
    let height: Int
    let pixels: [FloatingCaptionPetPixelRole]

    init(width: Int, height: Int, pixels: [FloatingCaptionPetPixelRole]) {
        precondition(width > 0 && height > 0, "Pet sprites must have positive dimensions.")
        precondition(pixels.count == width * height, "Pet sprite pixel count must match its dimensions.")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    subscript(x: Int, y: Int) -> FloatingCaptionPetPixelRole {
        precondition((0..<width).contains(x) && (0..<height).contains(y), "Pet sprite coordinate out of bounds.")
        return pixels[y * width + x]
    }
}

struct FloatingCaptionPetTheme: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let appearance: FloatingCaptionPetAppearance
    let defaultAccent: FloatingCaptionPetAccent
    let sprite: FloatingCaptionPetSprite
}

enum FloatingCaptionPetCatalog {
    static let builtInThemes: [FloatingCaptionPetTheme] = [
        FloatingCaptionPetTheme(
            id: FloatingCaptionPetAppearance.signal.rawValue,
            title: "Signal Cat",
            appearance: .signal,
            defaultAccent: accent("#00C7BE"),
            sprite: sprite([
                "..OO....OO..",
                ".OFF....FFO.",
                ".OFF....FFO.",
                "..OOOOOOOO..",
                ".OFFFFFFFFO.",
                "OFFFE..EFFFO",
                ".OFFA..AFFFO",
                "OFFFE..EFFFO",
                ".OFFFFFFFFO.",
                ".OOFFFFFFOO.",
                "..O......O..",
                "............"
            ])
        ),
        FloatingCaptionPetTheme(
            id: FloatingCaptionPetAppearance.orbit.rawValue,
            title: "Orbit Fox",
            appearance: .orbit,
            defaultAccent: accent("#FF9F43"),
            sprite: sprite([
                "..OO....OO..",
                ".OFFO..OFFO.",
                ".OFFFFFFFFO.",
                "..OOOOOOOO..",
                ".OFFFFFFFFO.",
                "OFFFE..EFFFO",
                "OFFFA..AFFFO",
                ".OFFFFFFFFO.",
                "..OFFFFFFO..",
                "...O....O...",
                "...OO..OO...",
                "............"
            ])
        ),
        FloatingCaptionPetTheme(
            id: FloatingCaptionPetAppearance.beacon.rawValue,
            title: "Beacon Frog",
            appearance: .beacon,
            defaultAccent: accent("#56D364"),
            sprite: sprite([
                ".OO....OO...",
                ".OFF..FFO...",
                "..OOOOOOOO..",
                ".OFFFFFFFFO.",
                "OFFFE..EFFFO",
                "OFFFA..AFFFO",
                ".OFFFFFFFFO.",
                ".OFFFFFFFFO.",
                "..OFFFFFFO..",
                "..OO....OO..",
                "...O....O...",
                "............"
            ])
        ),
        FloatingCaptionPetTheme(
            id: FloatingCaptionPetAppearance.night.rawValue,
            title: "Night Owl",
            appearance: .night,
            defaultAccent: accent("#A78BFA"),
            sprite: sprite([
                "...OO..OO...",
                "..OFF..FFO..",
                ".OFFFFFFFFO.",
                "..OOOOOOOO..",
                ".OFFFFHHFFO.",
                "OFFFE..EFFFO",
                "OFFFB..BFFFO",
                ".OFFFFFFFFO.",
                "..OFFFFFFO..",
                "...OO..OO...",
                "....O..O....",
                "............"
            ])
        ),
        FloatingCaptionPetTheme(
            id: FloatingCaptionPetAppearance.meadow.rawValue,
            title: "Meadow Rabbit",
            appearance: .meadow,
            defaultAccent: accent("#F4B942"),
            sprite: sprite([
                "....OO......",
                "...OFFO.....",
                "..OFFFFO....",
                ".OFFFFFFFFO.",
                "..OOOOOOOO..",
                ".OFFFFFFFFO.",
                "OFFFE..EFFFO",
                "OFFFA..AFFFO",
                ".OFFFFFFFFO.",
                "..OFFFFFFO..",
                "...OO..OO...",
                "............"
            ])
        )
    ]

    static func theme(for appearance: FloatingCaptionPetAppearance) -> FloatingCaptionPetTheme {
        builtInThemes.first(where: { $0.appearance == appearance })!
    }

    private static func accent(_ storageValue: String) -> FloatingCaptionPetAccent {
        FloatingCaptionPetAccent(storageValue: storageValue)!
    }

    private static func sprite(_ rows: [String]) -> FloatingCaptionPetSprite {
        let width = 12
        let height = 12
        precondition(rows.count == height, "Pet sprites must contain exactly 12 rows.")
        precondition(rows.allSatisfy { $0.count == width }, "Pet sprite rows must contain exactly 12 pixels.")

        let pixels: [FloatingCaptionPetPixelRole] = rows.flatMap { row in
            row.map { character -> FloatingCaptionPetPixelRole in
                switch character {
                case ".": FloatingCaptionPetPixelRole.empty
                case "O": FloatingCaptionPetPixelRole.outline
                case "F": FloatingCaptionPetPixelRole.fill
                case "E": FloatingCaptionPetPixelRole.face
                case "B": FloatingCaptionPetPixelRole.blush
                case "A": FloatingCaptionPetPixelRole.accent
                case "H": FloatingCaptionPetPixelRole.highlight
                default:
                    preconditionFailure("Pet sprite contains an unknown pixel role.")
                }
            }
        }
        return FloatingCaptionPetSprite(width: width, height: height, pixels: pixels)
    }
}
