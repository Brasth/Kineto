import Foundation

/// Produces one grounded answer for a completed meeting snapshot.
/// Retrieval and citation validation stay local. The generator is injected.
public actor MeetingChatService {
    private let retriever: MeetingLexicalRetriever
    private let validator: EvidenceValidator
    private let generator: any MeetingChatGenerating
    public let includePriorTurns: Bool

    public init(
        generator: any MeetingChatGenerating = MeetingChatGeneratorFactory.appleOnDeviceIfAvailable(),
        validator: EvidenceValidator = EvidenceValidator(),
        includePriorTurns: Bool = true
    ) {
        self.retriever = MeetingLexicalRetriever()
        self.validator = validator
        self.generator = generator
        self.includePriorTurns = includePriorTurns
    }

    init(
        retriever: MeetingLexicalRetriever = MeetingLexicalRetriever(),
        validator: EvidenceValidator = EvidenceValidator(),
        generator: any MeetingChatGenerating,
        includePriorTurns: Bool = false
    ) {
        self.retriever = retriever
        self.validator = validator
        self.generator = generator
        self.includePriorTurns = includePriorTurns
    }

    /// Test seam matching the previous closure-based initializer.
    init(
        retriever: MeetingLexicalRetriever = MeetingLexicalRetriever(),
        validator: EvidenceValidator = EvidenceValidator(),
        capability: @escaping @Sendable (SpokenLanguage) -> MeetingChatModelCapability,
        generator: @escaping @Sendable (String) async throws -> MeetingChatGeneration
    ) {
        self.retriever = retriever
        self.validator = validator
        self.generator = ClosureChatGenerator(capability: capability, generate: generator)
        self.includePriorTurns = false
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

        switch generator.capability(for: language) {
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
        case .providerDisconnected:
            return noAnswer(
                question: normalizedQuestion,
                meetingID: snapshot.meeting.id,
                language: language,
                reason: .providerDisconnected,
                context: context
            )
        case .userDeniedEgress:
            return noAnswer(
                question: normalizedQuestion,
                meetingID: snapshot.meeting.id,
                language: language,
                reason: .userDeniedEgress,
                context: context
            )
        case .available:
            break
        }

        let prior = includePriorTurns
            ? snapshot.chatTurns.filter { $0.outcome == .grounded }.suffix(6).map { $0 }
            : []

        do {
            let generated = try await generator.generate(
                MeetingChatRequest(
                    prompt: Self.prompt(
                        question: normalizedQuestion,
                        context: context,
                        priorTurns: prior
                    ),
                    language: language,
                    priorTurns: prior
                )
            )
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
                citations: citations,
                provider: generator.provider
            )
        } catch ChatGenerationError.disconnected {
            return noAnswer(
                question: normalizedQuestion,
                meetingID: snapshot.meeting.id,
                language: language,
                reason: .providerDisconnected,
                context: context
            )
        } catch ChatGenerationError.deniedEgress {
            return noAnswer(
                question: normalizedQuestion,
                meetingID: snapshot.meeting.id,
                language: language,
                reason: .userDeniedEgress,
                context: context
            )
        } catch ChatGenerationError.remoteFailure {
            return noAnswer(
                question: normalizedQuestion,
                meetingID: snapshot.meeting.id,
                language: language,
                reason: .remoteHTTPError,
                context: context
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
        let citations: [EvidenceReference]
        switch reason {
        case .noRelevantEvidence:
            citations = []
        case .modelUnavailable, .unsupportedLocale, .invalidGeneratedEvidence,
             .generationFailed, .providerDisconnected, .userDeniedEgress, .remoteHTTPError:
            citations = (try? validator.validateChatCitations(
                excerpts,
                meetingID: meetingID,
                retrievedSegments: context.sourceSegments
            )) ?? []
        }
        return ChatTurnRecord(
            meetingID: meetingID,
            responseLanguage: language,
            question: question,
            answer: Self.noAnswerText(for: language, reason: reason),
            outcome: .noAnswer,
            noAnswerReason: reason,
            citations: citations,
            provider: generator.provider
        )
    }

    static func prompt(
        question: String,
        context: RetrievedMeetingContext,
        priorTurns: [ChatTurnRecord]
    ) -> String {
        var parts: [String] = []
        if !priorTurns.isEmpty {
            let history = priorTurns.map { turn in
                "Q: \(turn.question)\nA: \(turn.answer)"
            }.joined(separator: "\n\n")
            parts.append("Earlier grounded answers from this meeting (not evidence):\n\(history)")
        }
        parts.append("Question:\n\(question)")
        parts.append("Retrieved transcript excerpts:\n\(context.prompt)")
        return parts.joined(separator: "\n\n")
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

    static func noAnswerText(for language: SpokenLanguage, reason: ChatNoAnswerReason) -> String {
        if language.isVietnamese {
            switch reason {
            case .noRelevantEvidence:
                return "Tôi không thể trả lời câu hỏi này từ các đoạn hội thoại đã truy xuất."
            case .modelUnavailable:
                return "Mô hình trên máy này hiện không dùng được."
            case .unsupportedLocale:
                return "Ngôn ngữ trả lời này chưa được mô hình hỗ trợ."
            case .providerDisconnected:
                return "Nhà cung cấp AI chưa được kết nối. Mở Cài đặt để thêm khóa API."
            case .userDeniedEgress:
                return "Bạn chưa cho phép gửi đoạn trích ra khỏi máy này."
            case .remoteHTTPError:
                return "Nhà cung cấp AI từ chối hoặc không phản hồi."
            case .invalidGeneratedEvidence, .generationFailed:
                return "Tôi không thể xác thực một câu trả lời từ các đoạn hội thoại đã truy xuất."
            }
        }
        switch reason {
        case .noRelevantEvidence:
            return "I can’t answer this from the retrieved meeting transcript excerpts."
        case .modelUnavailable:
            return "The on-this-Mac model is unavailable."
        case .unsupportedLocale:
            return "The selected answer language is not supported by the current model."
        case .providerDisconnected:
            return "This AI provider is not connected. Open Settings to add an API key."
        case .userDeniedEgress:
            return "You have not allowed retrieved excerpts to leave this Mac."
        case .remoteHTTPError:
            return "The AI provider refused or failed this request."
        case .invalidGeneratedEvidence, .generationFailed:
            return "I couldn’t validate a grounded answer from the retrieved excerpts."
        }
    }
}

struct ClosureChatGenerator: MeetingChatGenerating {
    let provider: ChatProviderID = .appleOnDevice
    let capabilityHandler: @Sendable (SpokenLanguage) -> MeetingChatModelCapability
    let generateHandler: @Sendable (String) async throws -> MeetingChatGeneration

    init(
        capability: @escaping @Sendable (SpokenLanguage) -> MeetingChatModelCapability,
        generate: @escaping @Sendable (String) async throws -> MeetingChatGeneration
    ) {
        self.capabilityHandler = capability
        self.generateHandler = generate
    }

    func capability(for language: SpokenLanguage) -> MeetingChatModelCapability {
        capabilityHandler(language)
    }

    func generate(_ request: MeetingChatRequest) async throws -> MeetingChatGeneration {
        try await generateHandler(request.prompt)
    }
}
