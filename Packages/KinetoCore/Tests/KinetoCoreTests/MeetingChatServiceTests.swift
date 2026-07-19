import Foundation
import Testing
@testable import KinetoCore

@Test func lexicalRetrievalRanksDeterministicallyBeforeChronologicalPresentation() {
    let meetingID = fixedUUID("00000000-0000-0000-0000-000000000001")
    let phraseMatch = segment(
        id: fixedUUID("00000000-0000-0000-0000-000000000003"),
        meetingID: meetingID,
        start: 20,
        text: "The local prototype is ready."
    )
    let tokenMatch = segment(
        id: fixedUUID("00000000-0000-0000-0000-000000000002"),
        meetingID: meetingID,
        start: 0,
        text: "The prototype will run locally tomorrow."
    )
    let retriever = MeetingLexicalRetriever(
        configuration: .init(
            maximumSegments: 1,
            maximumContextCharacters: 4_000,
            maximumSegmentExcerptCharacters: 800
        )
    )

    let first = retriever.retrieve(
        question: "LOCAL prototype",
        meetingID: meetingID,
        segments: [tokenMatch, phraseMatch],
        gaps: []
    )
    let second = retriever.retrieve(
        question: "LOCAL prototype",
        meetingID: meetingID,
        segments: [phraseMatch, tokenMatch],
        gaps: []
    )

    #expect(first.sourceSegments.map(\.id) == [phraseMatch.id])
    #expect(second == first)
}

@Test func lexicalRetrievalScopesToFinalSegmentsFromOneMeetingAndIncludesBoundaryGaps() {
    let meetingID = fixedUUID("00000000-0000-0000-0000-000000000011")
    let otherMeetingID = fixedUUID("00000000-0000-0000-0000-000000000012")
    let first = segment(
        id: fixedUUID("00000000-0000-0000-0000-000000000013"),
        meetingID: meetingID,
        start: 10,
        text: "Budget decision is approved."
    )
    let second = segment(
        id: fixedUUID("00000000-0000-0000-0000-000000000014"),
        meetingID: meetingID,
        start: 30,
        text: "Budget owner will share the decision."
    )
    let retriever = MeetingLexicalRetriever()
    let context = retriever.retrieve(
        question: "budget decision",
        meetingID: meetingID,
        segments: [
            segment(meetingID: otherMeetingID, start: 0, text: "Budget decision from another meeting."),
            segment(meetingID: meetingID, start: 5, text: "Budget decision draft.", isFinal: false),
            second,
            first
        ],
        gaps: [
            gap(meetingID: meetingID, timestamp: 8, reason: "before"),
            gap(meetingID: meetingID, timestamp: 20, reason: "within"),
            gap(meetingID: meetingID, timestamp: 35, reason: "after"),
            gap(meetingID: otherMeetingID, timestamp: 20, reason: "other")
        ]
    )

    #expect(context.sourceSegments.map(\.id) == [first.id, second.id])
    #expect(context.gaps.map(\.reason) == ["before", "within", "after"])
    #expect(!context.prompt.contains("another meeting"))
    #expect(!context.prompt.contains("draft"))
}

@Test func chatCitationValidationRequiresLiteralRetrievedFinalSpan() throws {
    let meetingID = fixedUUID("00000000-0000-0000-0000-000000000021")
    let source = segment(meetingID: meetingID, start: 0, text: "The Local prototype ships Friday.")
    let validator = EvidenceValidator()

    let citations = try validator.validateChatCitations(
        [EvidenceReference(segmentID: source.id, supportingText: "Local prototype")],
        meetingID: meetingID,
        retrievedSegments: [source]
    )
    #expect(citations == [EvidenceReference(segmentID: source.id, supportingText: "Local prototype")])

    #expect(throws: EvidenceValidationError.unsupportedText) {
        try validator.validateChatCitations(
            [EvidenceReference(segmentID: source.id, supportingText: "local prototype")],
            meetingID: meetingID,
            retrievedSegments: [source]
        )
    }

    #expect(throws: EvidenceValidationError.citationOutsideRetrievedContext(source.id)) {
        try validator.validateChatCitations(
            [EvidenceReference(segmentID: source.id, supportingText: "Local prototype")],
            meetingID: meetingID,
            retrievedSegments: []
        )
    }
}

@Test func chatReturnsTruthfulNoAnswerWithoutRelevantEvidence() async {
    let meetingID = fixedUUID("00000000-0000-0000-0000-000000000031")
    let service = MeetingChatService(
        capability: { _ in .available },
        generator: { _ in
            MeetingChatGeneration(answer: "This must not run.", citations: [])
        }
    )
    let turn = await service.answer(
        question: "What was the launch date?",
        from: snapshot(meetingID: meetingID, segments: [segment(meetingID: meetingID, start: 0, text: "The budget is approved.")]),
        language: .english
    )

    #expect(turn.outcome == .noAnswer)
    #expect(turn.noAnswerReason == .noRelevantEvidence)
    #expect(turn.citations.isEmpty)
    #expect(turn.answer.contains("can’t answer"))
}

@Test func chatUsesRetrievedExcerptsForUnavailableAndInvalidGeneratedResponses() async {
    let meetingID = fixedUUID("00000000-0000-0000-0000-000000000035")
    let source = segment(meetingID: meetingID, start: 0, text: "The launch date is Friday.")
    let input = snapshot(meetingID: meetingID, segments: [source])
    let unavailable = MeetingChatService(
        capability: { _ in .unavailable },
        generator: { _ in
            MeetingChatGeneration(answer: "This must not run.", citations: [])
        }
    )
    let invalid = MeetingChatService(
        capability: { _ in .available },
        generator: { _ in
            MeetingChatGeneration(
                answer: "The launch date is Friday.",
                citations: [EvidenceReference(segmentID: UUID(), supportingText: "launch date is Friday")]
            )
        }
    )

    let unavailableTurn = await unavailable.answer(question: "When is the launch date?", from: input, language: .english)
    let invalidTurn = await invalid.answer(question: "When is the launch date?", from: input, language: .english)

    #expect(unavailableTurn.noAnswerReason == .modelUnavailable)
    #expect(invalidTurn.noAnswerReason == .invalidGeneratedEvidence)
    #expect(unavailableTurn.citations == [EvidenceReference(segmentID: source.id, supportingText: source.text)])
    #expect(invalidTurn.citations == [EvidenceReference(segmentID: source.id, supportingText: source.text)])
}

@Test func chatDoesNotPromptWithDerivedHistoryOrToolsAndReturnsGroundedAnswer() async {
    let meetingID = fixedUUID("00000000-0000-0000-0000-000000000041")
    let source = segment(meetingID: meetingID, start: 0, text: "The launch date is Friday.")
    let recorder = PromptRecorder()
    let service = MeetingChatService(
        capability: { _ in .available },
        generator: { prompt in
            await recorder.record(prompt)
            return MeetingChatGeneration(
                answer: "The launch date is Friday.",
                citations: [EvidenceReference(segmentID: source.id, supportingText: "launch date is Friday")]
            )
        }
    )
    let derived = TranslationRecord(
        sourceSegmentID: source.id,
        sourceLanguage: .english,
        targetLanguage: .vietnamese,
        text: "TRANSLATION-SENTINEL"
    )
    let summary = SummaryRecord(
        meetingID: meetingID,
        language: .english,
        templateID: "test",
        templateVersion: 1,
        items: [SummaryItem(kind: .overview, text: "SUMMARY-SENTINEL", evidence: [EvidenceReference(segmentID: source.id, supportingText: source.text)])]
    )
    let meeting = Meeting(id: meetingID, title: "Test", state: .stopped)
    let input = MeetingSnapshot(meeting: meeting, segments: [source], translations: [derived], summary: summary)

    let turn = await service.answer(question: "What is the launch date?", from: input, language: .english)
    let prompt = await recorder.value

    #expect(turn.outcome == .grounded)
    #expect(turn.citations == [EvidenceReference(segmentID: source.id, supportingText: "launch date is Friday")])
    #expect(!prompt.contains("TRANSLATION-SENTINEL"))
    #expect(!prompt.contains("SUMMARY-SENTINEL"))
    #expect(!prompt.localizedCaseInsensitiveContains("history"))
    #expect(!prompt.localizedCaseInsensitiveContains("tool"))
}

private actor PromptRecorder {
    private(set) var value = ""

    func record(_ prompt: String) {
        value = prompt
    }
}

private func snapshot(meetingID: UUID, segments: [Segment]) -> MeetingSnapshot {
    MeetingSnapshot(
        meeting: Meeting(id: meetingID, title: "Test", state: .stopped),
        segments: segments
    )
}

private func segment(
    id: UUID = UUID(),
    meetingID: UUID,
    start: TimeInterval,
    text: String,
    isFinal: Bool = true
) -> Segment {
    Segment(
        id: id,
        meetingID: meetingID,
        source: .selectedSource,
        startTime: start,
        endTime: start + 1,
        language: .english,
        text: text,
        isFinal: isFinal
    )
}

private func gap(meetingID: UUID, timestamp: TimeInterval, reason: String) -> TranscriptGap {
    TranscriptGap(meetingID: meetingID, source: .selectedSource, timestamp: timestamp, reason: reason)
}

private func fixedUUID(_ value: String) -> UUID {
    UUID(uuidString: value)!
}
