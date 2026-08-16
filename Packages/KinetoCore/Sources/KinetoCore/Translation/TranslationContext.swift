import Foundation

/// One earlier finalized clause used only as disambiguation context.
public struct TranslationTurn: Equatable, Sendable {
    public let speaker: SpeakerLabel
    public let sourceLanguage: SpokenLanguage
    public let sourceText: String
    public let translatedText: String?

    public init(
        speaker: SpeakerLabel,
        sourceLanguage: SpokenLanguage,
        sourceText: String,
        translatedText: String? = nil
    ) {
        self.speaker = speaker
        self.sourceLanguage = sourceLanguage
        self.sourceText = sourceText
        self.translatedText = translatedText
    }
}

/// Situation and recent speech that a clause-level machine translation cannot see.
public struct TranslationContext: Equatable, Sendable {
    public static let empty = TranslationContext()

    public var scenario: MeetingScenario
    public var speaker: SpeakerLabel
    public var recentTurns: [TranslationTurn]

    public init(
        scenario: MeetingScenario = .general,
        speaker: SpeakerLabel = .selectedSource,
        recentTurns: [TranslationTurn] = []
    ) {
        self.scenario = scenario
        self.speaker = speaker
        self.recentTurns = recentTurns
    }

    public static func isChronologicallyBefore(_ lhs: Segment, _ rhs: Segment) -> Bool {
        if lhs.startTime != rhs.startTime { return lhs.startTime < rhs.startTime }
        if lhs.endTime != rhs.endTime { return lhs.endTime < rhs.endTime }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// Turns that already happened. Later speech is never treated as context
    /// for an older clause being reconciled after stop.
    public static func precedingTurns(
        from segments: [Segment],
        translations: [TranslationRecord],
        before segment: Segment,
        limit: Int = 5
    ) -> [TranslationTurn] {
        let earlier = segments
            .filter { prior in
                prior.isFinal && prior.id != segment.id && isChronologicallyBefore(prior, segment)
            }
            .sorted(by: isChronologicallyBefore)
        return earlier.suffix(limit).map { prior in
            TranslationTurn(
                speaker: prior.speakerLabel,
                sourceLanguage: prior.language,
                sourceText: prior.text,
                translatedText: translations.first { $0.sourceSegmentID == prior.id }?.text
            )
        }
    }
}
