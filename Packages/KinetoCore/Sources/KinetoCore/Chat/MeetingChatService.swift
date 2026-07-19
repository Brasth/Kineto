import Foundation
import FoundationModels

@Generable
private struct GeneratedChatCitation {
    @Guide(description: "UUID of a supplied transcript segment")
    var segmentID: String

    @Guide(description: "Exact contiguous text copied from that supplied excerpt")
    var quote: String
}

@Generable
private struct GeneratedChatPayload {
    @Guide(description: "A concise answer grounded only in the supplied transcript excerpts")
    var answer: String

    @Guide(description: "One or more exact supporting quotes from supplied transcript excerpts")
    var citations: [GeneratedChatCitation]
}

struct MeetingChatGeneration: Sendable, Equatable {
    let answer: String
    let citations: [EvidenceReference]

    init(answer: String, citations: [EvidenceReference]) {
        self.answer = answer
        self.citations = citations
    }
}

enum MeetingChatModelCapability: Sendable, Equatable {
    case available
    case unavailable
    case unsupportedLocale
}

typealias MeetingChatGenerator = @Sendable (String) async throws -> MeetingChatGeneration
typealias MeetingChatCapability = @Sendable (SpokenLanguage) -> MeetingChatModelCapability

/// Produces one grounded, standalone answer for a completed meeting snapshot.
/// Every request gets a fresh, tool-free Foundation Models session; no prior turns
/// or derived meeting data are included in its prompt.
public actor MeetingChatService {
    private let retriever: MeetingLexicalRetriever
    private let validator: EvidenceValidator
    private let capability: MeetingChatCapability
    private let generator: MeetingChatGenerator

    public init(
        model: SystemLanguageModel = .default,
        validator: EvidenceValidator = EvidenceValidator()
    ) {
        self.retriever = MeetingLexicalRetriever()
        self.validator = validator
        self.capability = Self.capability(for: model)
        self.generator = Self.generator(for: model)
    }

    init(
        retriever: MeetingLexicalRetriever = MeetingLexicalRetriever(),
        validator: EvidenceValidator = EvidenceValidator(),
        capability: @escaping MeetingChatCapability,
        generator: @escaping MeetingChatGenerator
    ) {
        self.retriever = retriever
        self.validator = validator
        self.capability = capability
        self.generator = generator
    }

    public func answer(
        question: String,
        from snapshot: MeetingSnapshot,
        language: SpokenLanguage
    ) async -> ChatTurnRecord {
        let normalizedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = retriever.retrieve(question: normalizedQuestion, from: snapshot)
        guard !context.segments.isEmpty else {
            return noAnswer(
                question: normalizedQuestion,
                meetingID: snapshot.meeting.id,
                language: language,
                reason: .noRelevantEvidence,
                context: context
            )
        }

        switch capability(language) {
        case .unavailable:
            return noAnswer(
                question: normalizedQuestion,
                meetingID: snapshot.meeting.id,
                language: language,
                reason: .modelUnavailable,
                context: context
            )
        case .unsupportedLocale:
            return noAnswer(
                question: normalizedQuestion,
                meetingID: snapshot.meeting.id,
                language: language,
                reason: .unsupportedLocale,
                context: context
            )
        case .available:
            break
        }

        do {
            let generated = try await generator(Self.prompt(question: normalizedQuestion, context: context))
            let answer = generated.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !answer.isEmpty else {
                return noAnswer(
                    question: normalizedQuestion,
                    meetingID: snapshot.meeting.id,
                    language: language,
                    reason: .invalidGeneratedEvidence,
                    context: context
                )
            }
            guard Self.citationsAreInSuppliedExcerpts(generated.citations, context: context) else {
                return noAnswer(
                    question: normalizedQuestion,
                    meetingID: snapshot.meeting.id,
                    language: language,
                    reason: .invalidGeneratedEvidence,
                    context: context
                )
            }
            guard let citations = try? validator.validateChatCitations(
                generated.citations,
                meetingID: snapshot.meeting.id,
                retrievedSegments: context.sourceSegments
            ) else {
                return noAnswer(
                    question: normalizedQuestion,
                    meetingID: snapshot.meeting.id,
                    language: language,
                    reason: .invalidGeneratedEvidence,
                    context: context
                )
            }
            return ChatTurnRecord(
                meetingID: snapshot.meeting.id,
                responseLanguage: language,
                question: normalizedQuestion,
                answer: answer,
                outcome: .grounded,
                citations: citations
            )
        } catch {
            return noAnswer(
                question: normalizedQuestion,
                meetingID: snapshot.meeting.id,
                language: language,
                reason: .generationFailed,
                context: context
            )
        }
    }

    private func noAnswer(
        question: String,
        meetingID: UUID,
        language: SpokenLanguage,
        reason: ChatNoAnswerReason,
        context: RetrievedMeetingContext
    ) -> ChatTurnRecord {
        let excerpts = context.segments.map {
            EvidenceReference(segmentID: $0.segment.id, supportingText: $0.promptExcerpt)
        }
        let citations = (try? validator.validateChatCitations(
            excerpts,
            meetingID: meetingID,
            retrievedSegments: context.sourceSegments
        )) ?? []
        return ChatTurnRecord(
            meetingID: meetingID,
            responseLanguage: language,
            question: question,
            answer: Self.noAnswerText(for: language),
            outcome: .noAnswer,
            noAnswerReason: reason,
            citations: citations
        )
    }

    private static func prompt(question: String, context: RetrievedMeetingContext) -> String {
        "Question:\n\(question)\n\nRetrieved transcript excerpts:\n\(context.prompt)"
    }

    private static func citationsAreInSuppliedExcerpts(
        _ citations: [EvidenceReference],
        context: RetrievedMeetingContext
    ) -> Bool {
        guard !citations.isEmpty else { return false }
        let excerpts = Dictionary(uniqueKeysWithValues: context.segments.map {
            ($0.segment.id, $0.promptExcerpt)
        })
        return citations.allSatisfy { citation in
            guard let excerpt = excerpts[citation.segmentID] else { return false }
            let quote = citation.supportingText.trimmingCharacters(in: .whitespacesAndNewlines)
            return !quote.isEmpty && excerpt.range(of: quote) != nil
        }
    }

    private static func noAnswerText(for language: SpokenLanguage) -> String {
        language.isVietnamese
            ? "Tôi không thể trả lời câu hỏi này từ các đoạn hội thoại đã truy xuất."
            : "I can’t answer this from the retrieved meeting transcript excerpts."
    }

    private static func capability(for model: SystemLanguageModel) -> MeetingChatCapability {
        { language in
            guard model.availability == .available else { return .unavailable }
            let locale = Locale(identifier: language.rawValue)
            return model.supportsLocale(locale) ? .available : .unsupportedLocale
        }
    }

    private static func generator(for model: SystemLanguageModel) -> MeetingChatGenerator {
        { prompt in
            let session = LanguageModelSession(
                model: model,
                tools: [],
                instructions: """
                Answer only from the retrieved transcript excerpts in the user prompt.
                Do not infer facts absent from those excerpts. Return an answer only when it is supported.
                Every citation must use a supplied segment UUID and an exact contiguous quote copied from that supplied excerpt.
                """
            )
            let response = try await session.respond(to: prompt, generating: GeneratedChatPayload.self)
            return MeetingChatGeneration(
                answer: response.content.answer,
                citations: response.content.citations.compactMap { citation in
                    guard let segmentID = UUID(uuidString: citation.segmentID) else { return nil }
                    return EvidenceReference(segmentID: segmentID, supportingText: citation.quote)
                }
            )
        }
    }
}
