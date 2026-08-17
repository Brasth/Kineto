import Foundation
import Testing
@testable import KinetoCore

@Test func recapKeepsUserParagraphsVerbatimAndDropsInvalidFills() async throws {
    let meetingID = UUID(uuidString: "00000000-0000-0000-0000-000000000701")!
    let segment = Segment(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000702")!,
        meetingID: meetingID,
        source: .selectedSource,
        startTime: 0,
        endTime: 1,
        language: .english,
        text: "Budget approved at twelve thousand.",
        isFinal: true
    )
    let snapshot = MeetingSnapshot(
        meeting: Meeting(id: meetingID, title: "Notes", state: .stopped),
        segments: [segment],
        scratchpad: MeetingScratchpad(
            body: "Budget looks fine\n\nAsk Linh for the date",
            updatedAt: Date(timeIntervalSince1970: 2),
            revision: 3
        )
    )
    let service = MeetingRecapService(
        generator: ClosureChatGenerator(
            capability: { _ in .available },
            generate: { _ in
                MeetingChatGeneration(
                    answer: "The budget is approved at twelve thousand.",
                    citations: [
                        EvidenceReference(segmentID: segment.id, supportingText: "Budget approved at twelve thousand.")
                    ]
                )
            }
        )
    )

    let recap = await service.enhance(snapshot: snapshot, language: .english)
    #expect(recap?.scratchpadRevision == 3)
    #expect(recap?.blocks.map(\.kind) == [.user, .user, .filled])
    #expect(recap?.blocks.map(\.text) == [
        "Budget looks fine",
        "Ask Linh for the date",
        "The budget is approved at twelve thousand."
    ])
}

@Test func recapInterleavesGroundedFillsBetweenUserParagraphs() async throws {
    let meetingID = UUID(uuidString: "00000000-0000-0000-0000-000000000731")!
    let budget = Segment(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000732")!,
        meetingID: meetingID,
        source: .selectedSource,
        startTime: 0,
        endTime: 1,
        language: .english,
        text: "Budget approved at twelve thousand.",
        isFinal: true
    )
    let date = Segment(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000733")!,
        meetingID: meetingID,
        source: .you,
        startTime: 2,
        endTime: 3,
        language: .english,
        text: "We will confirm the date on Thursday.",
        isFinal: true
    )
    let snapshot = MeetingSnapshot(
        meeting: Meeting(id: meetingID, title: "Interleave", state: .stopped),
        segments: [budget, date],
        scratchpad: MeetingScratchpad(
            body: "Budget looks fine\n\nAsk Linh for the date",
            updatedAt: Date(timeIntervalSince1970: 2),
            revision: 4
        )
    )
    let service = MeetingRecapService(
        generator: ClosureChatGenerator(
            capability: { _ in .available },
            generate: { _ in
                MeetingChatGeneration(
                    answer: """
                    {"fills":[
                      {"afterParagraph":1,"text":"Approved at twelve thousand.","citations":[{"segmentID":"\(budget.id.uuidString)","quote":"Budget approved at twelve thousand."}]},
                      {"afterParagraph":2,"text":"Date confirmation is Thursday.","citations":[{"segmentID":"\(date.id.uuidString)","quote":"We will confirm the date on Thursday."}]}
                    ]}
                    """,
                    citations: []
                )
            }
        )
    )

    let recap = await service.enhance(snapshot: snapshot, language: .english)
    #expect(recap?.blocks.map(\.kind) == [.user, .filled, .user, .filled])
    #expect(recap?.blocks.map(\.text) == [
        "Budget looks fine",
        "Approved at twelve thousand.",
        "Ask Linh for the date",
        "Date confirmation is Thursday."
    ])
}

@Test func recapPlacesLeadingFillBeforeTheFirstNoteAndClampsPastTheEnd() {
    let first = RecapBlock(kind: .user, text: "Ship Friday", evidence: [])
    let second = RecapBlock(kind: .user, text: "Need cost", evidence: [])
    let citation = EvidenceReference(
        segmentID: UUID(uuidString: "00000000-0000-0000-0000-000000000740")!,
        supportingText: "quote"
    )
    let blocks = MeetingRecapService.interleave(
        userBlocks: [first, second],
        fills: [
            MeetingRecapFill(afterParagraph: 0, text: "Opened with timeline.", citations: [citation]),
            MeetingRecapFill(afterParagraph: 9, text: "Cost comes next week.", citations: [citation])
        ]
    )
    #expect(blocks.map(\.kind) == [.filled, .user, .user, .filled])
}

@Test func recapPromptNumbersNotesAndAsksForInterleavedFills() {
    let segment = Segment(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000721")!,
        meetingID: UUID(uuidString: "00000000-0000-0000-0000-000000000722")!,
        source: .selectedSource,
        startTime: 0,
        endTime: 1,
        language: .english,
        text: "Price is locked.",
        isFinal: true
    )
    let prompt = MeetingRecapService.prompt(
        notes: "Price locked",
        segments: [segment],
        language: .english
    )
    #expect(prompt.contains("Operator notes:\n[1] Price locked"))
    #expect(prompt.contains("afterParagraph"))
    #expect(prompt.contains("Do not repeat or rewrite"))
}
