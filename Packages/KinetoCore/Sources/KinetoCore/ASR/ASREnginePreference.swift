import Foundation

/// User-selectable live speech engine.
public enum ASREnginePreference: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Apple SpeechAnalyzer / SpeechTranscriber with live volatile results.
    case appleSpeech
    /// Local whisper.cpp finals (higher lag, strong bilingual fallback).
    case whisper

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .appleSpeech:
            "Apple Speech (low latency)"
        case .whisper:
            "Whisper (local model)"
        }
    }

    public var detail: String {
        switch self {
        case .appleSpeech:
            "Live partial captions via on-device Apple speech assets. Choose any language that macOS supports, or use Whisper automatically."
        case .whisper:
            "Pinned local Whisper model. More lag than Apple Speech, with automatic multilingual language detection."
        }
    }
}

/// Language routing chosen for speech recognition, independent of translation and summary language.
public struct RecognitionLanguagePreference: RawRepresentable, Codable, Hashable, Sendable, Identifiable {
    public static let automatic = RecognitionLanguagePreference(rawValue: "automatic")!
    public static let english = RecognitionLanguagePreference.apple(localeIdentifier: "en")
    public static let vietnamese = RecognitionLanguagePreference.apple(localeIdentifier: "vi")

    public let rawValue: String

    public init?(rawValue: String) {
        switch rawValue {
        case "bilingual", "automatic":
            self.rawValue = "automatic"
        case "english":
            self.rawValue = "apple:en"
        case "vietnamese":
            self.rawValue = "apple:vi"
        default:
            guard !rawValue.isEmpty else { return nil }
            self.rawValue = rawValue.hasPrefix("apple:") ? rawValue : "apple:\(rawValue)"
        }
    }

    public static func apple(localeIdentifier: String) -> RecognitionLanguagePreference {
        RecognitionLanguagePreference(rawValue: "apple:\(localeIdentifier)")!
    }

    public var id: String { rawValue }
    public var isAutomatic: Bool { rawValue == Self.automatic.rawValue }

    public var localeIdentifier: String? {
        guard !isAutomatic else { return nil }
        return String(rawValue.dropFirst("apple:".count))
    }
}

/// A single Apple Speech locale and its runtime asset state.
public struct AppleSpeechLocale: Sendable, Equatable, Identifiable {
    public let identifier: String
    public let displayName: String
    public let assetState: LocaleAssetState

    public init(identifier: String, displayName: String, assetState: LocaleAssetState) {
        self.identifier = identifier
        self.displayName = displayName
        self.assetState = assetState
    }

    public var id: String { identifier }
}

/// Runtime readiness for the Apple speech path.
public struct AppleSpeechStatus: Sendable, Equatable {
    public var isFrameworkAvailable: Bool
    public var locales: [AppleSpeechLocale]
    public var notice: String

    public init(
        isFrameworkAvailable: Bool,
        locales: [AppleSpeechLocale],
        notice: String
    ) {
        self.isFrameworkAvailable = isFrameworkAvailable
        self.locales = locales
        self.notice = notice
    }

    public func locale(for preference: RecognitionLanguagePreference) -> AppleSpeechLocale? {
        guard let identifier = preference.localeIdentifier else { return nil }
        return locales.first { Self.matches($0.identifier, identifier) }
    }

    public func assetState(for preference: RecognitionLanguagePreference) -> LocaleAssetState? {
        guard !preference.isAutomatic else { return nil }
        return locale(for: preference)?.assetState ?? .unsupported
    }

    public func canDownloadAsset(for preference: RecognitionLanguagePreference) -> Bool {
        assetState(for: preference) == .available
    }

    public func installedLocaleIdentifier(
        for preference: RecognitionLanguagePreference
    ) -> String? {
        guard locale(for: preference)?.assetState == .installed else { return nil }
        return locale(for: preference)?.identifier
    }

    public func canStart(using preference: RecognitionLanguagePreference) -> Bool {
        isFrameworkAvailable && installedLocaleIdentifier(for: preference) != nil
    }

    public func readinessMessage(for preference: RecognitionLanguagePreference) -> String {
        guard isFrameworkAvailable else {
            return "Apple Speech is unavailable on this Mac. Use Whisper."
        }
        guard !preference.isAutomatic else {
            return "Automatic language detection uses Whisper locally."
        }
        guard let locale = locale(for: preference) else {
            return "This Apple Speech language is not supported by macOS on this Mac and cannot be installed. Use Whisper."
        }
        switch locale.assetState {
        case .installed:
            return "\(locale.displayName) Apple Speech is installed and ready for low-latency captions."
        case .available:
            return "\(locale.displayName) Apple Speech can be downloaded from macOS before recording."
        case .unsupported:
            return "\(locale.displayName) Apple Speech is not supported by macOS on this Mac and cannot be installed. Use Whisper."
        }
    }

    public var installedLocaleCount: Int {
        locales.count { $0.assetState == .installed }
    }

    public var downloadableLocaleCount: Int {
        locales.count { $0.assetState == .available }
    }

    private static func matches(_ lhs: String, _ rhs: String) -> Bool {
        let leftLocale = Locale(identifier: lhs)
        let rightLocale = Locale(identifier: rhs)
        let left = leftLocale.identifier(.bcp47)
        let right = rightLocale.identifier(.bcp47)
        let rightIsLanguageOnly = !rhs.contains("-") && !rhs.contains("_")
        return lhs.caseInsensitiveCompare(rhs) == .orderedSame
            || left.caseInsensitiveCompare(right) == .orderedSame
            || (rightIsLanguageOnly
                && leftLocale.language.languageCode?.identifier.caseInsensitiveCompare(rhs) == .orderedSame)
    }
}

public enum LocaleAssetState: String, Sendable, Equatable {
    case unsupported
    case available
    case installed

    public var label: String {
        switch self {
        case .unsupported:
            "Unsupported on this Mac"
        case .available:
            "Download required"
        case .installed:
            "Installed"
        }
    }
}
