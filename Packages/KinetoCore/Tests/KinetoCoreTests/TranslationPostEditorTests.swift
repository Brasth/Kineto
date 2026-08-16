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
    let context = TranslationContext(scenario: .sales, speaker: .selectedSource)
    let edited = editor.edit(
        source: "The warehouse will ship the hardware tomorrow.",
        draft: "Kho sẽ vận chuyển phần cứng vào ngày mai.",
        sourceLanguage: .english,
        targetLanguage: .vietnamese,
        context: context
    )
    #expect(edited.contains("vận chuyển"))
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
