import CoreGraphics
import XCTest
@testable import Kineto

@MainActor
final class FloatingCaptionPetVisualPreferencesTests: XCTestCase {
    func testDefaultsAndPickerMetadataMatchProductContract() {
        let preferences = FloatingCaptionPetVisualPreferences.default

        XCTAssertEqual(preferences.appearance, .signal)
        XCTAssertEqual(preferences.size, .standard)
        XCTAssertEqual(preferences.motion, .subtle)
        XCTAssertEqual(preferences.accent.storageValue, "#00C7BE")
        XCTAssertEqual(FloatingCaptionPetAppearance.allCases.map(\.title), ["Signal Cat", "Orbit Fox", "Beacon Frog", "Night Owl", "Meadow Rabbit"])
        XCTAssertEqual(FloatingCaptionPetSize.allCases.map(\.title), ["Compact", "Standard", "Large"])
        XCTAssertEqual(FloatingCaptionPetMotion.allCases.map(\.title), ["Subtle", "Static"])
    }

    func testBuiltInPetCatalogHasStableFiveDistinctThemes() {
        let themes = FloatingCaptionPetCatalog.builtInThemes

        XCTAssertEqual(themes.count, 5)
        XCTAssertEqual(themes.map(\.id), ["signal", "orbit", "beacon", "night", "meadow"])
        for legacyID in ["signal", "orbit", "beacon"] {
            XCTAssertNotNil(FloatingCaptionPetAppearance(rawValue: legacyID))
        }
        XCTAssertEqual(themes.map(\.title), ["Signal Cat", "Orbit Fox", "Beacon Frog", "Night Owl", "Meadow Rabbit"])
        XCTAssertEqual(Set(themes.map(\.id)).count, themes.count)
        XCTAssertEqual(themes.map(\.appearance), FloatingCaptionPetAppearance.allCases)

        guard let firstSprite = themes.first?.sprite else {
            XCTFail("The built-in pet catalog must not be empty")
            return
        }

        for theme in themes {
            XCTAssertEqual(theme.sprite.width, firstSprite.width)
            XCTAssertEqual(theme.sprite.height, firstSprite.height)
            XCTAssertEqual(theme.sprite.pixels.count, theme.sprite.width * theme.sprite.height)
            XCTAssertNotNil(FloatingCaptionPetAccent(storageValue: theme.defaultAccent.storageValue))
        }

        for index in themes.indices {
            for otherIndex in themes.indices.dropFirst(index + 1) {
                XCTAssertNotEqual(
                    themes[index].sprite,
                    themes[otherIndex].sprite,
                    "\(themes[index].id) and \(themes[otherIndex].id) must have distinct sprites"
                )
            }
        }
    }

    func testAccentAcceptsOnlyCanonicalOpaqueSRGBStorage() {
        XCTAssertEqual(FloatingCaptionPetAccent(storageValue: "#00C7BE")?.storageValue, "#00C7BE")
        XCTAssertEqual(FloatingCaptionPetAccent(storageValue: "#ABCDEF")?.storageValue, "#ABCDEF")
        XCTAssertEqual(FloatingCaptionPetAccent(storageValue: "#00c7be")?.storageValue, "#00C7BE")
        XCTAssertNil(FloatingCaptionPetAccent(storageValue: "00C7BE"))
        XCTAssertNil(FloatingCaptionPetAccent(storageValue: "#00C7BEFF"))
        XCTAssertNil(FloatingCaptionPetAccent(storageValue: "#00C7B"))
        XCTAssertNil(FloatingCaptionPetAccent(storageValue: "#GGGGGG"))
        XCTAssertNil(FloatingCaptionPetAccent(storageValue: "#12345G"))
        XCTAssertNil(FloatingCaptionPetAccent(storageValue: ""))
    }

    func testAccentNormalizesSRGBAndDiscardsAlpha() {
        let grayscale = CGColor(gray: 0.5, alpha: 0.05)
        let firstGrayscaleStorage = FloatingCaptionPetAccent(cgColor: grayscale)?.storageValue
        let secondGrayscaleStorage = FloatingCaptionPetAccent(cgColor: grayscale)?.storageValue

        XCTAssertEqual(firstGrayscaleStorage, "#808080")
        XCTAssertEqual(secondGrayscaleStorage, firstGrayscaleStorage)
        let color = CGColor(srgbRed: 0.25, green: 0.5, blue: 0.75, alpha: 0.2)

        XCTAssertEqual(FloatingCaptionPetAccent(cgColor: color)?.storageValue, "#4080BF")
    }

    func testAccentRejectsNonFiniteGrayscaleAndRGBComponentsWithoutTrapping() {
        if let grayscale = CGColor(
            colorSpace: CGColorSpaceCreateDeviceGray(),
            components: [CGFloat.nan, 1]
        ) {
            XCTAssertNil(FloatingCaptionPetAccent(cgColor: grayscale))
        }

        if let rgb = CGColor(
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            components: [CGFloat.nan, 0.5, 0.25, 1]
        ) {
            XCTAssertNil(FloatingCaptionPetAccent(cgColor: rgb))
        }
    }

    func testAppModelRestoresCurrentPetSettingsSnapshot() {
        let defaults = UserDefaults.standard
        let keys = [
            "kineto.petModeEnabled",
            "kineto.petAppearance",
            "kineto.petSize",
            "kineto.petMotion",
            "kineto.petSettings",
            "kineto.petAccent"
        ]
        let previousValues = keys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in previousValues {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        defaults.set(false, forKey: "kineto.petModeEnabled")
        defaults.set("signal", forKey: "kineto.petAppearance")
        defaults.set("compact", forKey: "kineto.petSize")
        defaults.set("subtle", forKey: "kineto.petMotion")
        defaults.set("#00C7BE", forKey: "kineto.petAccent")
        defaults.set(
            Data(##"{"version":1,"enabled":true,"appearance":"night","size":"large","motion":"static","accent":"#123456"}"##.utf8),
            forKey: "kineto.petSettings"
        )

        let model = AppModel()

        XCTAssertTrue(model.petModeEnabled)
        XCTAssertEqual(model.petAppearance, .night)
        XCTAssertEqual(model.petSize, .large)
        XCTAssertEqual(model.petMotion, .static)
        XCTAssertEqual(model.petAccent.storageValue, "#123456")
    }

    func testAppModelLeavesUnsupportedFuturePetSettingsSnapshotUnchanged() {
        let defaults = UserDefaults.standard
        let keys = [
            "kineto.petModeEnabled",
            "kineto.petAppearance",
            "kineto.petSize",
            "kineto.petMotion",
            "kineto.petSettings",
            "kineto.petAccent"
        ]
        let previousValues = keys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in previousValues {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        defaults.set(true, forKey: "kineto.petModeEnabled")
        defaults.set("orbit", forKey: "kineto.petAppearance")
        defaults.set("compact", forKey: "kineto.petSize")
        defaults.set("subtle", forKey: "kineto.petMotion")
        defaults.set("#ABCDEF", forKey: "kineto.petAccent")
        let futureSnapshot = Data(
            ##"{"version":2,"enabled":false,"appearance":"meadow","size":"large","motion":"static","accent":"#654321"}"##.utf8
        )
        defaults.set(futureSnapshot, forKey: "kineto.petSettings")

        _ = AppModel()

        XCTAssertEqual(defaults.data(forKey: "kineto.petSettings"), futureSnapshot)
    }

    func testPetSizesAndMotionRespectAccessibility() {
        XCTAssertEqual(FloatingCaptionPetSize.compact.points, 40)
        XCTAssertEqual(FloatingCaptionPetSize.standard.points, 52)
        XCTAssertEqual(FloatingCaptionPetSize.large.points, 64)
        XCTAssertEqual(FloatingCaptionPetMotion.subtle.effective(reduceMotion: false), .subtle)
        XCTAssertEqual(FloatingCaptionPetMotion.subtle.effective(reduceMotion: true), .static)
        XCTAssertEqual(FloatingCaptionPetMotion.static.effective(reduceMotion: false), .static)
    }

    func testAppModelRestoresOnlyAcceptedPetPreferenceValues() {
        let defaults = UserDefaults.standard
        let keys = [
            "kineto.petModeEnabled",
            "kineto.petAppearance",
            "kineto.petSize",
            "kineto.petMotion",
            "kineto.petSettings",
            "kineto.petAccent"
        ]
        let previousValues = keys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in previousValues {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        defaults.set("not-an-appearance", forKey: "kineto.petAppearance")
        defaults.set("not-a-size", forKey: "kineto.petSize")
        defaults.set("not-a-motion", forKey: "kineto.petMotion")
        defaults.set("#00c7be", forKey: "kineto.petAccent")
        defaults.removeObject(forKey: "kineto.petSettings")

        let fallbackModel = AppModel()

        XCTAssertEqual(fallbackModel.petAppearance, .signal)
        XCTAssertEqual(fallbackModel.petSize, .standard)
        XCTAssertEqual(fallbackModel.petMotion, .subtle)
        XCTAssertEqual(fallbackModel.petAccent.storageValue, FloatingCaptionPetAccent.defaultStorageValue)

        defaults.set(FloatingCaptionPetAppearance.beacon.rawValue, forKey: "kineto.petAppearance")
        defaults.set(FloatingCaptionPetSize.large.rawValue, forKey: "kineto.petSize")
        defaults.set(FloatingCaptionPetMotion.static.rawValue, forKey: "kineto.petMotion")
        defaults.set("#123456", forKey: "kineto.petAccent")
        defaults.removeObject(forKey: "kineto.petSettings")

        let restoredModel = AppModel()

        XCTAssertEqual(restoredModel.petAppearance, .beacon)
        XCTAssertEqual(restoredModel.petSize, .large)
        XCTAssertEqual(restoredModel.petMotion, .static)
        XCTAssertEqual(restoredModel.petAccent.storageValue, "#123456")
    }
}
