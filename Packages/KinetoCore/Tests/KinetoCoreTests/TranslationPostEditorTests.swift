import Foundation
import Testing
@testable import KinetoCore

@Test func standupShipIsReleaseNotFreight() {
    let editor = TranslationPostEditor()
    let context = TranslationContext(scenario: .standup, speaker: .selectedSource)
    let edited = editor.edit(
        source: "We'll ship the checkout fix on Friday.",
        draft: "Chúng tôi sẽ vận chuyển bản sửa checkout vào thứ Sáu.",
        sourceLanguage: .english,
        targetLanguage: .vietnamese,
        context: context
    )
    #expect(edited.contains("phát hành"))
    #expect(!edited.contains("vận chuyển"))
}

@Test func circleBackAndOfflineBecomeLaterDiscussion() {
    let editor = TranslationPostEditor()
    let context = TranslationContext(scenario: .clientCall, speaker: .you)
    let circled = editor.edit(
        source: "Let's circle back after the legal review.",
        draft: "Hãy quay lại vòng tròn sau khi xem xét pháp lý.",
        sourceLanguage: .english,
        targetLanguage: .vietnamese,
        context: context
    )
    #expect(circled.contains("bàn lại sau"))
    #expect(!circled.contains("vòng tròn"))

    let offline = editor.edit(
        source: "Can we take this offline?",
        draft: "Chúng ta có thể đưa cái này ngoại tuyến không?",
        sourceLanguage: .english,
        targetLanguage: .vietnamese,
        context: context
    )
    #expect(offline.contains("bàn riêng sau"))
    #expect(!offline.contains("ngoại tuyến"))
}

@Test func engineeringNounsStayInEnglishForStandup() {
    let editor = TranslationPostEditor()
    let context = TranslationContext(scenario: .standup, speaker: .you)
    let edited = editor.edit(
        source: "The only blocker is the payment PR, then we can merge.",
        draft: "Người chặn duy nhất là quan hệ công chúng thanh toán, rồi chúng ta có thể sáp nhập.",
        sourceLanguage: .english,
        targetLanguage: .vietnamese,
        context: context
    )
    #expect(edited.contains("blocker"))
    #expect(edited.contains("PR"))
    #expect(edited.contains("merge"))
    #expect(!edited.contains("Người chặn"))
    #expect(!edited.contains("quan hệ công chúng"))
}

@Test func ownerIsPersonInChargeNotPropertyHolder() {
    let editor = TranslationPostEditor()
    let context = TranslationContext(scenario: .planning, speaker: .selectedSource)
    let edited = editor.edit(
        source: "Who is the owner of this ticket?",
        draft: "Ai là chủ sở hữu của vé này?",
        sourceLanguage: .english,
        targetLanguage: .vietnamese,
        context: context
    )
    #expect(edited.contains("người phụ trách"))
    #expect(edited.contains("ticket"))
    #expect(!edited.contains("chủ sở hữu"))
    #expect(!edited.contains("vé này"))
}

@Test func vietnameseKinshipAddressDoesNotBecomeFamilyInEnglish() {
    let editor = TranslationPostEditor()
    let context = TranslationContext(scenario: .standup, speaker: .you)
    let edited = editor.edit(
        source: "Ok anh, em follow up ticket này.",
        draft: "Okay older brother, little sibling follow this admission ticket.",
        sourceLanguage: .vietnamese,
        targetLanguage: .english,
        context: context
    )
    #expect(!edited.lowercased().contains("older brother"))
    #expect(!edited.lowercased().contains("little sibling"))
    #expect(!edited.lowercased().contains("admission ticket"))
}

@Test func chotMeansFinalizeNotLock() {
    let editor = TranslationPostEditor()
    let context = TranslationContext(scenario: .planning, speaker: .selectedSource)
    let edited = editor.edit(
        source: "Mình chốt scope sprint này trước trưa.",
        draft: "I lock this sprint scope before noon.",
        sourceLanguage: .vietnamese,
        targetLanguage: .english,
        context: context
    )
    #expect(edited.lowercased().contains("finalize"))
    #expect(!edited.lowercased().contains("lock"))
}

@Test func scenarioDoesNotRewriteUnrelatedFreightShip() {
    let editor = TranslationPostEditor()
    let sales = editor.edit(
        source: "The warehouse will ship the hardware tomorrow.",
        draft: "Kho sẽ vận chuyển phần cứng vào ngày mai.",
        sourceLanguage: .english,
        targetLanguage: .vietnamese,
        context: TranslationContext(scenario: .sales, speaker: .selectedSource)
    )
    #expect(sales.contains("vận chuyển"))

    let general = editor.edit(
        source: "We ship packages every morning.",
        draft: "Chúng tôi vận chuyển các gói hàng mỗi sáng.",
        sourceLanguage: .english,
        targetLanguage: .vietnamese,
        context: TranslationContext(scenario: .general, speaker: .selectedSource)
    )
    #expect(general.contains("vận chuyển"))
    #expect(!general.contains("phát hành"))
}

@Test func generalScenarioStillRewritesSoftwareShip() {
    let editor = TranslationPostEditor()
    let edited = editor.edit(
        source: "We'll ship the checkout fix on Friday.",
        draft: "Chúng tôi sẽ vận chuyển bản sửa checkout vào thứ Sáu.",
        sourceLanguage: .english,
        targetLanguage: .vietnamese,
        context: TranslationContext(scenario: .general, speaker: .selectedSource)
    )
    #expect(edited.contains("phát hành"))
    #expect(!edited.contains("vận chuyển"))
}

@Test func foldedVietnameseTriggersStillMatch() {
    let editor = TranslationPostEditor()
    let context = TranslationContext(scenario: .planning, speaker: .you)
    let da = editor.edit(
        source: "Dạ em follow ticket này.",
        draft: "Yes sir, little sibling follow this admission ticket.",
        sourceLanguage: .vietnamese,
        targetLanguage: .english,
        context: context
    )
    #expect(!da.lowercased().contains("yes sir"))
    #expect(!da.lowercased().contains("little sibling"))
    #expect(da.lowercased().contains("ticket"))
}

@Test func droppedIdentifiersAreRestoredFromSource() {
    let editor = TranslationPostEditor()
    let edited = editor.edit(
        source: "Open KNT42 and check https://status.kineto.app please.",
        draft: "Hãy mở và kiểm tra giúp.",
        sourceLanguage: .english,
        targetLanguage: .vietnamese,
        context: TranslationContext(scenario: .support, speaker: .you)
    )
    #expect(edited.contains("KNT42"))
    #expect(edited.contains("https://status.kineto.app"))
}

@Test func protectedTokenCasingIsRestored() {
    let editor = TranslationPostEditor()
    let edited = editor.edit(
        source: "Ask OrbitFox about CheckOutAPI.",
        draft: "Hỏi orbitfox về checkoutapi.",
        sourceLanguage: .english,
        targetLanguage: .vietnamese,
        context: TranslationContext(scenario: .standup, speaker: .you)
    )
    #expect(edited.contains("OrbitFox"))
    #expect(edited.contains("CheckOutAPI"))
}

@Test func precedingTurnsIgnoreLaterSpeech() {
    let meetingID = UUID()
    let opening = Segment(
        meetingID: meetingID,
        source: .selectedSource,
        startTime: 0,
        endTime: 2,
        language: .english,
        text: "Let's start with the checkout bug.",
        isFinal: true
    )
    let middle = Segment(
        meetingID: meetingID,
        source: .you,
        startTime: 3,
        endTime: 5,
        language: .english,
        text: "I can take the ticket.",
        isFinal: true
    )
    let closing = Segment(
        meetingID: meetingID,
        source: .selectedSource,
        startTime: 20,
        endTime: 22,
        language: .english,
        text: "We will ship Friday.",
        isFinal: true
    )
    let turns = TranslationContext.precedingTurns(
        from: [closing, opening, middle],
        translations: [
            TranslationRecord(
                sourceSegmentID: middle.id,
                sourceLanguage: .english,
                targetLanguage: .vietnamese,
                text: "Mình nhận ticket."
            ),
        ],
        before: middle
    )
    #expect(turns.count == 1)
    #expect(turns[0].sourceText == opening.text)
    #expect(turns[0].translatedText == nil)
}

@Test func emptyDraftPassesThrough() {
    let editor = TranslationPostEditor()
    let edited = editor.edit(
        source: "Hello",
        draft: "   ",
        sourceLanguage: .english,
        targetLanguage: .vietnamese,
        context: .empty
    )
    #expect(edited == "   ")
}

@Test func refineRequestInstructionsNameTheScenario() {
    let request = TranslationRefineRequest(
        sourceText: "Let's circle back on the PR.",
        draftText: "Hãy bàn lại sau về PR.",
        sourceLanguage: .english,
        targetLanguage: .vietnamese,
        context: TranslationContext(scenario: .standup, speaker: .you)
    )
    let instructions = TranslationRefiner.instructions(for: request)
    #expect(instructions.contains("Standup / sync"))
    #expect(instructions.contains("Circle back"))
    #expect(instructions.contains("You"))
}

@Test func finalizeDraftUsesRefinerWhenPresent() async {
    let service = TranslationService(refiner: { request in
        "refined:\(request.draftText)"
    })
    let result = await service.finalizeDraft(
        source: "Sounds good, I'll take a look.",
        draft: "Nghe có vẻ tốt, tôi sẽ nhìn một cái.",
        sourceLanguage: .english,
        targetLanguage: .vietnamese,
        context: TranslationContext(scenario: .standup, speaker: .you)
    )
    #expect(result.hasPrefix("refined:"))
    #expect(result.contains("ok"))
    #expect(result.contains("xem giúp"))
}

@Test func meetingScenarioPersistsStableRawValues() {
    #expect(MeetingScenario.standup.rawValue == "standup")
    #expect(MeetingScenario.oneOnOne.rawValue == "one-on-one")
    #expect(MeetingScenario(rawValue: "client-call") == .clientCall)
    #expect(MeetingScenario.allCases.count == 9)
}

@Test func generalScenarioDoesNotRewritePropertyOwner() {
    let editor = TranslationPostEditor()
    let edited = editor.edit(
        source: "The owner sold the building.",
        draft: "Chủ sở hữu đã bán tòa nhà.",
        sourceLanguage: .english,
        targetLanguage: .vietnamese,
        context: TranslationContext(scenario: .general, speaker: .selectedSource)
    )
    #expect(edited.contains("Chủ sở hữu"))
    #expect(!edited.contains("người phụ trách"))
}

@Test func generalScenarioRewritesTaskOwner() {
    let editor = TranslationPostEditor()
    let edited = editor.edit(
        source: "Who is the owner of this ticket?",
        draft: "Ai là chủ sở hữu của vé này?",
        sourceLanguage: .english,
        targetLanguage: .vietnamese,
        context: TranslationContext(scenario: .general, speaker: .selectedSource)
    )
    #expect(edited.contains("người phụ trách"))
    #expect(edited.contains("ticket"))
}

@Test func phraseReplacementRespectsWordBoundaries() {
    let editor = TranslationPostEditor()
    let edited = editor.edit(
        source: "Mình chốt lúc ba giờ.",
        draft: "Lock it at three o'clock.",
        sourceLanguage: .vietnamese,
        targetLanguage: .english,
        context: TranslationContext(scenario: .planning, speaker: .you)
    )
    #expect(edited.lowercased().contains("finalize"))
    #expect(edited.lowercased().contains("o'clock"))
    #expect(!edited.lowercased().contains("o'finalize"))
}

@Test func refineCannotDropProtectedTokens() async {
    let service = TranslationService(refiner: { _ in "Hãy xem giúp." })
    let result = await service.finalizeDraft(
        source: "Open KNT42 and check https://status.kineto.app please.",
        draft: "Hãy mở KNT42 và kiểm tra https://status.kineto.app.",
        sourceLanguage: .english,
        targetLanguage: .vietnamese,
        context: TranslationContext(scenario: .support, speaker: .you)
    )
    #expect(result.contains("KNT42"))
    #expect(result.contains("https://status.kineto.app"))
}
