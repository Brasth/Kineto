import Foundation
import Testing
@testable import KinetoCore

@Test func chatProviderIDsUseOfficialConsoleDestinations() {
    #expect(ChatProviderID.grok.displayName == "Grok")
    #expect(ChatProviderID.openai.displayName == "OpenAI")
    #expect(ChatProviderID.gemini.displayName == "Gemini")
    #expect(ChatProviderID.appleOnDevice.sendsMeetingExcerptsOffDevice == false)
    #expect(ChatProviderID.grok.sendsMeetingExcerptsOffDevice)
    #expect(ChatProviderID.grok.defaultModel == "grok-4.6")
    #expect(ChatProviderID.openai.defaultModel == "gpt-5")
    #expect(ChatProviderID.gemini.defaultModel == "gemini-2.5-flash")
    #expect(ChatProviderID.grok.consoleURL.host == "console.x.ai")
    #expect(ChatProviderID.openai.consoleURL.host == "platform.openai.com")
    #expect(ChatProviderID.gemini.consoleURL.host == "aistudio.google.com")
}

@Test func chatProviderPreferencesTrackConsentWithoutStoringSecrets() {
    let suite = "kineto.tests.chat-preferences.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    #expect(ChatProviderPreferences.defaultProvider(defaults: defaults) == .appleOnDevice)
    ChatProviderPreferences.setDefaultProvider(.grok, defaults: defaults)
    #expect(ChatProviderPreferences.defaultProvider(defaults: defaults) == .grok)
    #expect(ChatProviderPreferences.shouldRequestConsent(for: .grok, defaults: defaults))
    #expect(!ChatProviderPreferences.shouldRequestConsent(for: .appleOnDevice, defaults: defaults))
    ChatProviderPreferences.setConsented(true, to: .grok, defaults: defaults)
    #expect(!ChatProviderPreferences.shouldRequestConsent(for: .grok, defaults: defaults))
    ChatProviderPreferences.setAlwaysAskBeforeEgress(true, defaults: defaults)
    #expect(ChatProviderPreferences.shouldRequestConsent(for: .grok, defaults: defaults))
    #expect(ChatProviderPreferences.consentDisclosure(for: .grok).contains("Grok"))
}

@Test func chatReturnsProviderSpecificNoAnswerReasons() async {
    let meetingID = UUID(uuidString: "00000000-0000-0000-0000-000000000061")!
    let source = Segment(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000062")!,
        meetingID: meetingID,
        source: .selectedSource,
        startTime: 0,
        endTime: 1,
        language: .english,
        text: "The launch date is Friday.",
        isFinal: true
    )
    let snapshot = MeetingSnapshot(
        meeting: Meeting(id: meetingID, title: "Test", state: .stopped),
        segments: [source]
    )

    let disconnected = MeetingChatService(
        generator: UnavailableChatGenerator(provider: .grok, result: .providerDisconnected)
    )
    let denied = MeetingChatService(
        generator: UnavailableChatGenerator(provider: .openai, result: .userDeniedEgress)
    )
    let remote = MeetingChatService(
        capability: { _ in .available },
        generator: { _ in throw ChatGenerationError.remoteFailure }
    )

    let disconnectedTurn = await disconnected.answer(
        question: "When is the launch date?",
        from: snapshot,
        language: .english
    )
    let deniedTurn = await denied.answer(
        question: "When is the launch date?",
        from: snapshot,
        language: .english
    )
    let remoteTurn = await remote.answer(
        question: "When is the launch date?",
        from: snapshot,
        language: .english
    )

    #expect(disconnectedTurn.noAnswerReason == .providerDisconnected)
    #expect(disconnectedTurn.provider == .grok)
    #expect(disconnectedTurn.answer.contains("not connected"))
    #expect(deniedTurn.noAnswerReason == .userDeniedEgress)
    #expect(deniedTurn.provider == .openai)
    #expect(remoteTurn.noAnswerReason == .remoteHTTPError)
}

@Test func chatIncludesPriorGroundedTurnsWhenEnabled() async {
    let meetingID = UUID(uuidString: "00000000-0000-0000-0000-000000000071")!
    let source = Segment(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000072")!,
        meetingID: meetingID,
        source: .selectedSource,
        startTime: 0,
        endTime: 1,
        language: .english,
        text: "The launch date is Friday.",
        isFinal: true
    )
    let prior = ChatTurnRecord(
        meetingID: meetingID,
        responseLanguage: .english,
        question: "What ships?",
        answer: "The local prototype.",
        outcome: .grounded,
        citations: [EvidenceReference(segmentID: source.id, supportingText: "launch date is Friday")],
        provider: .grok
    )
    let snapshot = MeetingSnapshot(
        meeting: Meeting(id: meetingID, title: "Test", state: .stopped),
        segments: [source],
        chatTurns: [prior]
    )
    let recorder = PromptRecorder()
    let service = MeetingChatService(
        retriever: MeetingLexicalRetriever(),
        validator: EvidenceValidator(),
        generator: ClosureChatGenerator(
            capability: { _ in .available },
            generate: { prompt in
                await recorder.record(prompt)
                return MeetingChatGeneration(
                    answer: "The launch date is Friday.",
                    citations: [EvidenceReference(segmentID: source.id, supportingText: "launch date is Friday")]
                )
            }
        ),
        includePriorTurns: true
    )

    let turn = await service.answer(
        question: "When is the launch date?",
        from: snapshot,
        language: .english
    )
    let prompt = await recorder.value

    #expect(turn.outcome == .grounded)
    #expect(turn.provider == .appleOnDevice)
    #expect(prompt.contains("Earlier grounded answers"))
    #expect(prompt.contains("What ships?"))
    #expect(prompt.contains("The local prototype."))
}

@Test func remoteGeneratorMapsCapabilityAndParsesTransportPayload() async throws {
    let segmentID = UUID(uuidString: "00000000-0000-0000-0000-000000000081")!
    let transport = ScriptedChatEgressTransport(
        result: """
        {"answer":"Friday.","citations":[{"segmentID":"\(segmentID.uuidString)","quote":"Friday"}]}
        """
    )
    let generator = RemoteChatGenerator(
        provider: .grok,
        transport: transport,
        isConnected: true,
        egressAllowed: true,
        resolveAPIKey: { "xai-test-key-abcd" }
    )
    let generation = try await generator.generate(
        MeetingChatRequest(prompt: "Question:\nWhen?\n\nRetrieved transcript excerpts:\nFriday", language: .english)
    )
    #expect(generation.answer == "Friday.")
    #expect(generation.citations.first?.segmentID == segmentID)
    #expect(generator.capability(for: .english) == .available)
    #expect(
        RemoteChatGenerator(
            provider: .openai,
            transport: transport,
            isConnected: false,
            egressAllowed: true,
            resolveAPIKey: { nil }
        ).capability(for: .english) == .providerDisconnected
    )
    #expect(
        RemoteChatGenerator(
            provider: .gemini,
            transport: transport,
            isConnected: true,
            egressAllowed: false,
            resolveAPIKey: { "key" }
        ).capability(for: .english) == .userDeniedEgress
    )
}

@Test func inMemoryAccountStoreNeverExposesFullKeyInHint() async throws {
    let store = InMemoryChatProviderAccountStore()
    try await store.saveAPIKey("sk-test-secret-key-zyxw", for: .openai)
    let account = await store.account(for: .openai)
    #expect(account.isConnected)
    #expect(account.displayHint.contains("zyxw"))
    #expect(!account.displayHint.contains("sk-test-secret-key"))
    try await store.deleteAPIKey(for: .openai)
    #expect(await store.isConnected(.openai) == false)
}

@Test func chatTurnRecordDecodesLegacySnapshotsWithoutProvider() throws {
    let meetingID = UUID(uuidString: "00000000-0000-0000-0000-000000000091")!
    let segmentID = UUID(uuidString: "00000000-0000-0000-0000-000000000092")!
    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    let legacy = """
        {
          "id": "00000000-0000-0000-0000-000000000093",
          "meetingID": "\(meetingID.uuidString)",
          "createdAt": \(createdAt.timeIntervalSinceReferenceDate),
          "responseLanguage": "en",
          "question": "When?",
          "answer": "Friday.",
          "outcome": "grounded",
          "citations": [{"segmentID":"\(segmentID.uuidString)","supportingText":"Friday"}]
        }
        """
    let decoded = try JSONDecoder().decode(ChatTurnRecord.self, from: Data(legacy.utf8))
    #expect(decoded.provider == nil)
    #expect(decoded.outcome == .grounded)
}

private actor PromptRecorder {
    private(set) var value = ""

    func record(_ prompt: String) {
        value = prompt
    }
}

private struct ScriptedChatEgressTransport: ChatEgressTransporting {
    let result: String

    func complete(
        provider: ChatProviderID,
        model: String,
        prompt: String,
        apiKey: String
    ) async throws -> String {
        result
    }
}
