import Foundation

public struct MeetingChatGeneration: Sendable, Equatable {
    public let answer: String
    public let citations: [EvidenceReference]

    public init(answer: String, citations: [EvidenceReference]) {
        self.answer = answer
        self.citations = citations
    }
}

public enum MeetingChatModelCapability: Sendable, Equatable {
    case available
    case unavailable
    case unsupportedLocale
    case providerDisconnected
    case userDeniedEgress
}

public struct MeetingChatRequest: Sendable {
    public let prompt: String
    public let language: SpokenLanguage
    public let priorTurns: [ChatTurnRecord]

    public init(prompt: String, language: SpokenLanguage, priorTurns: [ChatTurnRecord] = []) {
        self.prompt = prompt
        self.language = language
        self.priorTurns = priorTurns
    }
}

/// Swappable generator. Retrieval and citation validation stay in `MeetingChatService`.
public protocol MeetingChatGenerating: Sendable {
    var provider: ChatProviderID { get }
    func capability(for language: SpokenLanguage) -> MeetingChatModelCapability
    func generate(_ request: MeetingChatRequest) async throws -> MeetingChatGeneration
}

public struct UnavailableChatGenerator: MeetingChatGenerating {
    public let provider: ChatProviderID
    private let result: MeetingChatModelCapability

    public init(provider: ChatProviderID, result: MeetingChatModelCapability = .unavailable) {
        self.provider = provider
        self.result = result
    }

    public func capability(for language: SpokenLanguage) -> MeetingChatModelCapability {
        result
    }

    public func generate(_ request: MeetingChatRequest) async throws -> MeetingChatGeneration {
        throw ChatGenerationError.unavailable
    }
}

public enum ChatGenerationError: Error, Equatable, Sendable {
    case unavailable
    case disconnected
    case deniedEgress
    case remoteFailure
    case invalidPayload
}

public enum MeetingChatInstructions {
    public static let groundedJSON = """
        Answer only from the retrieved transcript excerpts in the user prompt.
        Do not infer facts absent from those excerpts. Return an answer only when it is supported.
        Every citation must use a supplied segment UUID and an exact contiguous quote copied from that supplied excerpt.
        Reply with JSON only, no markdown fences:
        {"answer":"...","citations":[{"segmentID":"<uuid>","quote":"<exact excerpt span>"}]}
        """
}
