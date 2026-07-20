import CoreGraphics
import SwiftUI

enum FloatingCaptionPetAppearance: String, CaseIterable, Sendable {
    case signal = "signal"
    case orbit = "orbit"
    case beacon = "beacon"
    case night = "night"
    case meadow = "meadow"

    var title: String {
        switch self {
        case .signal: "Signal Cat"
        case .orbit: "Orbit Fox"
        case .beacon: "Beacon Frog"
        case .night: "Night Owl"
        case .meadow: "Meadow Rabbit"
        }
    }
}

enum FloatingCaptionPetSize: String, CaseIterable, Sendable {
    case compact
    case standard
    case large

    var title: String {
        switch self {
        case .compact: "Compact"
        case .standard: "Standard"
        case .large: "Large"
        }
    }

    var points: CGFloat {
        switch self {
        case .compact: 40
        case .standard: 52
        case .large: 64
        }
    }
}

enum FloatingCaptionPetMotion: String, CaseIterable, Sendable {
    case subtle
    case `static`

    var title: String {
        switch self {
        case .subtle: "Subtle"
        case .static: "Static"
        }
    }

    func effective(reduceMotion: Bool) -> Self {
        reduceMotion ? .static : self
    }
}

struct FloatingCaptionPetAccent: Equatable, Sendable {
    static let defaultStorageValue = "#00C7BE"

    private let red: UInt8
    private let green: UInt8
    private let blue: UInt8

    init?(storageValue: String) {
        guard storageValue.count == 7,
              storageValue.first == "#"
        else {
            return nil
        }

        let hex = String(storageValue.dropFirst()).uppercased()
        guard hex.count == 6,
              hex.allSatisfy({ $0.isASCII && ("0123456789ABCDEF").contains($0) }),
              let red = UInt8(hex.prefix(2), radix: 16),
              let green = UInt8(hex.dropFirst(2).prefix(2), radix: 16),
              let blue = UInt8(hex.dropFirst(4).prefix(2), radix: 16)
        else {
            return nil
        }

        self.red = red
        self.green = green
        self.blue = blue
    }

    init?(cgColor: CGColor) {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let components = Self.sRGBComponents(from: cgColor, targetColorSpace: colorSpace)
        else {
            return nil
        }

        guard let red = Self.componentByte(components.red),
              let green = Self.componentByte(components.green),
              let blue = Self.componentByte(components.blue)
        else {
            return nil
        }

        self.red = red
        self.green = green
        self.blue = blue
    }

    var storageValue: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    var cgColor: CGColor {
        CGColor(
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            components: [CGFloat(red) / 255, CGFloat(green) / 255, CGFloat(blue) / 255, 1]
        )!
    }

    private static func sRGBComponents(
        from color: CGColor,
        targetColorSpace: CGColorSpace
    ) -> (red: CGFloat, green: CGFloat, blue: CGFloat)? {
        guard let sourceComponents = color.components,
              let sourceColorSpace = color.colorSpace
        else {
            return nil
        }
        let sourceModel = sourceColorSpace.model
        let sourceColorSpaceName = sourceColorSpace.name.map { String(describing: $0) }
        let genericGrayColorSpaceName = CGColor(gray: 0, alpha: 1).colorSpace?.name.map {
            String(describing: $0)
        }
        let genericGrayGamma2_2Name = String(describing: CGColorSpace.genericGrayGamma2_2)

        let isGenericGray = sourceColorSpaceName == genericGrayColorSpaceName ||
            sourceColorSpaceName == genericGrayGamma2_2Name
        if sourceModel == .monochrome, isGenericGray, sourceComponents.count >= 1 {
            let gray = sourceComponents[0]
            return (gray, gray, gray)
        }

        if let converted = color.converted(to: targetColorSpace, intent: .defaultIntent, options: nil),
           let components = converted.components,
           let model = converted.colorSpace?.model
        {
            switch model {
            case .rgb where components.count >= 3:
                return (components[0], components[1], components[2])
            case .monochrome where components.count >= 1:
                return (components[0], components[0], components[0])
            default:
                break
            }
        }

        switch sourceModel {
        case .rgb where sourceComponents.count >= 3:
            return (sourceComponents[0], sourceComponents[1], sourceComponents[2])
        case .monochrome where isGenericGray && sourceComponents.count >= 1:
            let gray = sourceComponents[0]
            return (gray, gray, gray)
        default:
            return nil
        }

    }
    private static func componentByte(_ component: CGFloat) -> UInt8? {
        guard component.isFinite else {
            return nil
        }

        return UInt8((component.clamped(to: 0...1) * 255).rounded())
    }
}


struct FloatingCaptionPetVisualPreferences: Equatable, Sendable {
    static let `default` = Self(
        appearance: .signal,
        size: .standard,
        motion: .subtle,
        accent: FloatingCaptionPetAccent(storageValue: FloatingCaptionPetAccent.defaultStorageValue)!
    )

    let appearance: FloatingCaptionPetAppearance
    let size: FloatingCaptionPetSize
    let motion: FloatingCaptionPetMotion
    let accent: FloatingCaptionPetAccent
}

struct FloatingCaptionOverlayPresentation: Equatable, Sendable {
    let caption: FloatingCaptionPresentation
    let petVisualPreferences: FloatingCaptionPetVisualPreferences
    let signalGatePresentation: SignalGatePresentation

    init(
        caption: FloatingCaptionPresentation,
        petVisualPreferences: FloatingCaptionPetVisualPreferences,
        signalGatePresentation: SignalGatePresentation
    ) {
        self.caption = caption
        self.petVisualPreferences = petVisualPreferences
        self.signalGatePresentation = caption.isVisible && signalGatePresentation.phase == .capturing
            ? signalGatePresentation
            : SignalGatePresentation(phase: .hidden)
    }

    var isVisible: Bool { caption.isVisible }

    static let hidden = Self(
        caption: .hidden,
        petVisualPreferences: .default,
        signalGatePresentation: SignalGatePresentation(phase: .hidden)
    )
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
