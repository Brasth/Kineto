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
}
