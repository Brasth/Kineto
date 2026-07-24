import CoreGraphics
import Foundation

// Size and motion remain user preferences; identity and artwork come only from PetDexInstalledPet.
enum FloatingCaptionPetSize: String, CaseIterable, Codable, Sendable {
    case compact
    case standard
    case large

    var points: CGFloat {
        switch self {
        case .compact: 48
        case .standard: 60
        case .large: 72
        }
    }
}

enum FloatingCaptionPetMotion: String, CaseIterable, Codable, Sendable {
    case subtle
    case `static`

    func effective(reduceMotion: Bool) -> Self {
        reduceMotion ? .static : self
    }
}

struct FloatingCaptionPetVisualPreferences: Equatable, Sendable {
    let pet: PetDexInstalledPet
    let size: FloatingCaptionPetSize
    let motion: FloatingCaptionPetMotion
}

struct FloatingCaptionOverlayPresentation: Equatable, Sendable {
    let caption: FloatingCaptionPresentation
    let petVisualPreferences: FloatingCaptionPetVisualPreferences?
    let signalGatePresentation: SignalGatePresentation

    init(
        caption: FloatingCaptionPresentation,
        petVisualPreferences: FloatingCaptionPetVisualPreferences?,
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
        petVisualPreferences: nil,
        signalGatePresentation: SignalGatePresentation(phase: .hidden)
    )
}
