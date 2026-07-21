import Foundation

/// A persisted BCP-47 language tag emitted by the active recognizer.
///
/// Existing meeting packages encoded simple tags such as `"en"` and `"vi"`; those
/// remain valid. New Apple Speech locales retain their regional tag, for example
/// `"pt-BR"`, so a meeting records the language that actually produced its text.
public struct SpokenLanguage: RawRepresentable, Codable, Hashable, Sendable {
    public static let english = SpokenLanguage(rawValue: "en")
    public static let vietnamese = SpokenLanguage(rawValue: "vi")
    public static let chinese = SpokenLanguage(rawValue: "zh")
    public static let unknown = SpokenLanguage(rawValue: "unknown")

    public let rawValue: String

    public init(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.caseInsensitiveCompare("unknown") != .orderedSame else {
            self.rawValue = "unknown"
            return
        }
        self.rawValue = Locale(identifier: trimmed).identifier(.bcp47)
    }

    public init(localeIdentifier: String) {
        self.init(rawValue: localeIdentifier)
    }

    public var languageCode: String {
        guard rawValue != Self.unknown.rawValue else { return rawValue }
        return Locale(identifier: rawValue).language.languageCode?.identifier.lowercased() ?? rawValue.lowercased()
    }

    public var isEnglish: Bool { languageCode == Self.english.rawValue }
    public var isVietnamese: Bool { languageCode == Self.vietnamese.rawValue }

    /// Translation currently supports only final EN↔VI transcript segments.
    public var translationTarget: SpokenLanguage? {
        if isEnglish { return .vietnamese }
        if isVietnamese { return .english }
        return nil
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum AudioSource: String, Codable, Hashable, Sendable {
    case you
    case selectedSource
}

extension AudioSource {
    public var active: ActiveSources {
        switch self {
        case .you: return .you
        case .selectedSource: return .selectedSource
        }
    }
}

/// Presentation label derived only from capture source.
/// Not speaker identity: microphone is `you`, app/display mix is `selectedSource`.
public enum SpeakerLabel: String, Codable, Hashable, Sendable {
    case you
    case selectedSource

    public var displayName: String {
        switch self {
        case .you:
            "You"
        case .selectedSource:
            "Selected Source"
        }
    }

    public static func `default`(for source: AudioSource) -> SpeakerLabel {
        switch source {
        case .you:
            .you
        case .selectedSource:
            .selectedSource
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case SpeakerLabel.you.rawValue:
            self = .you
        case SpeakerLabel.selectedSource.rawValue:
            self = .selectedSource
        case "personA", "personB", "unknown":
            // Legacy heuristic labels collapse to the capture-mix presentation label.
            self = .selectedSource
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown speaker label \(raw)"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct Segment: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let meetingID: UUID
    public let source: AudioSource
    public let speakerLabel: SpeakerLabel
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let language: SpokenLanguage
    public let text: String
    public let confidence: Double?
    public let isFinal: Bool

    public init(
        id: UUID = UUID(),
        meetingID: UUID,
        source: AudioSource,
        speakerLabel: SpeakerLabel? = nil,
        startTime: TimeInterval,
        endTime: TimeInterval,
        language: SpokenLanguage,
        text: String,
        confidence: Double? = nil,
        isFinal: Bool
    ) {
        precondition(startTime >= 0 && endTime >= startTime)
        self.id = id
        self.meetingID = meetingID
        self.source = source
        self.speakerLabel = speakerLabel ?? .default(for: source)
        self.startTime = startTime
        self.endTime = endTime
        self.language = language
        self.text = text
        self.confidence = confidence
        self.isFinal = isFinal
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case meetingID
        case source
        case speakerLabel
        case startTime
        case endTime
        case language
        case text
        case confidence
        case isFinal
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        meetingID = try container.decode(UUID.self, forKey: .meetingID)
        source = try container.decode(AudioSource.self, forKey: .source)
        speakerLabel = try container.decodeIfPresent(SpeakerLabel.self, forKey: .speakerLabel)
            ?? .default(for: source)
        startTime = try container.decode(TimeInterval.self, forKey: .startTime)
        endTime = try container.decode(TimeInterval.self, forKey: .endTime)
        language = try container.decode(SpokenLanguage.self, forKey: .language)
        text = try container.decode(String.self, forKey: .text)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        isFinal = try container.decode(Bool.self, forKey: .isFinal)
    }
}
