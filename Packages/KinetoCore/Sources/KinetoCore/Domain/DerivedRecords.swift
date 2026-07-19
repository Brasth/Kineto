import Foundation

public struct TranslationRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let sourceSegmentID: UUID
    public let sourceLanguage: SpokenLanguage
    public let targetLanguage: SpokenLanguage
    public let text: String

    public init(
        id: UUID = UUID(),
        sourceSegmentID: UUID,
        sourceLanguage: SpokenLanguage,
        targetLanguage: SpokenLanguage,
        text: String
    ) {
        self.id = id
        self.sourceSegmentID = sourceSegmentID
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.text = text
    }
}

public struct EvidenceReference: Codable, Equatable, Sendable {
    public let segmentID: UUID
    public let supportingText: String

    public init(segmentID: UUID, supportingText: String) {
        self.segmentID = segmentID
        self.supportingText = supportingText
    }
}

public enum ChatTurnOutcome: String, Codable, Equatable, Sendable {
    case grounded
    case noAnswer
}

public enum ChatNoAnswerReason: String, Codable, Equatable, Sendable {
    case noRelevantEvidence
    case modelUnavailable
    case unsupportedLocale
    case invalidGeneratedEvidence
    case generationFailed
}

public struct ChatTurnRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let meetingID: UUID
    public let createdAt: Date
    public let responseLanguage: SpokenLanguage
    public let question: String
    public let answer: String
    public let outcome: ChatTurnOutcome
    public let noAnswerReason: ChatNoAnswerReason?
    public let citations: [EvidenceReference]

    public init(
        id: UUID = UUID(),
        meetingID: UUID,
        createdAt: Date = Date(),
        responseLanguage: SpokenLanguage,
        question: String,
        answer: String,
        outcome: ChatTurnOutcome,
        noAnswerReason: ChatNoAnswerReason? = nil,
        citations: [EvidenceReference]
    ) {
        self.id = id
        self.meetingID = meetingID
        self.createdAt = createdAt
        self.responseLanguage = responseLanguage
        self.question = question
        self.answer = answer
        self.outcome = outcome
        self.noAnswerReason = noAnswerReason
        self.citations = citations
    }
}

public struct SummaryItem: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case overview
        case keyPoint
        case decision
        case action
    }

    public let id: UUID
    public let kind: Kind
    public let text: String
    public let evidence: [EvidenceReference]

    public init(id: UUID = UUID(), kind: Kind, text: String, evidence: [EvidenceReference]) {
        self.id = id
        self.kind = kind
        self.text = text
        self.evidence = evidence
    }
}

/// A user-selected structure for an evidence-linked meeting summary.
public enum SummaryTemplate: String, Codable, CaseIterable, Sendable, Identifiable {
    case executiveBrief = "executive-brief"
    case actionPlan = "action-plan"
    case discussionNotes = "discussion-notes"

    public var id: String { rawValue }
    public var version: Int { 1 }

    public var displayName: String {
        switch self {
        case .executiveBrief:
            "Executive brief"
        case .actionPlan:
            "Action plan"
        case .discussionNotes:
            "Discussion notes"
        }
    }

    public var detail: String {
        switch self {
        case .executiveBrief:
            "A concise overview, decisions, next actions, and essential context."
        case .actionPlan:
            "Prioritizes explicit commitments and confirmed decisions."
        case .discussionNotes:
            "Organizes the main topics discussed, with decisions and follow-ups."
        }
    }

    public var sectionOrder: [SummaryItem.Kind] {
        switch self {
        case .executiveBrief:
            [.overview, .decision, .action, .keyPoint]
        case .actionPlan:
            [.overview, .action, .decision, .keyPoint]
        case .discussionNotes:
            [.overview, .keyPoint, .decision, .action]
        }
    }

    public func sectionTitle(for kind: SummaryItem.Kind) -> String {
        switch (self, kind) {
        case (.executiveBrief, .overview):
            "Overview"
        case (.executiveBrief, .decision):
            "Decisions"
        case (.executiveBrief, .action):
            "Next actions"
        case (.executiveBrief, .keyPoint):
            "Key context"
        case (.actionPlan, .overview):
            "Objective"
        case (.actionPlan, .action):
            "Commitments"
        case (.actionPlan, .decision):
            "Confirmed decisions"
        case (.actionPlan, .keyPoint):
            "Supporting context"
        case (.discussionNotes, .overview):
            "Discussion overview"
        case (.discussionNotes, .keyPoint):
            "Topics discussed"
        case (.discussionNotes, .decision):
            "Decisions"
        case (.discussionNotes, .action):
            "Follow-ups"
        }
    }

    public func maximumItems(for kind: SummaryItem.Kind) -> Int {
        switch (self, kind) {
        case (_, .overview):
            1
        case (.executiveBrief, .decision), (.executiveBrief, .action):
            3
        case (.executiveBrief, .keyPoint):
            4
        case (.actionPlan, .action):
            6
        case (.actionPlan, .decision):
            3
        case (.actionPlan, .keyPoint):
            2
        case (.discussionNotes, .keyPoint):
            6
        case (.discussionNotes, .decision), (.discussionNotes, .action):
            2
        }
    }

    public var generationInstructions: String {
        switch self {
        case .executiveBrief:
            "Return one overview, then explicit decisions, explicit next actions, and only the key context needed to understand them."
        case .actionPlan:
            "Return one objective, then explicit commitments and actions first, followed by confirmed decisions and only essential context."
        case .discussionNotes:
            "Return one discussion overview, then the main topics in chronological order, followed by explicit decisions and follow-ups."
        }
    }
}

public struct SummaryRecord: Codable, Equatable, Sendable {
    public static let generalConversationTemplateID = "general-conversation"
    public static let generalConversationTemplateVersion = 1

    public let meetingID: UUID
    public let language: SpokenLanguage
    public let createdAt: Date
    public let templateID: String
    public let templateVersion: Int
    public let items: [SummaryItem]

    public init(
        meetingID: UUID,
        language: SpokenLanguage,
        createdAt: Date = Date(),
        templateID: String = SummaryRecord.generalConversationTemplateID,
        templateVersion: Int = SummaryRecord.generalConversationTemplateVersion,
        items: [SummaryItem]
    ) {
        self.meetingID = meetingID
        self.language = language
        self.createdAt = createdAt
        self.templateID = templateID
        self.templateVersion = templateVersion
        self.items = items
    }
}
