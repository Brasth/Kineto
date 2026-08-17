import XCTest

final class ChatEgressHTTPCodecTests: XCTestCase {
    func testGrokRequestUsesOfficialHostAndDoesNotPutKeyInURL() throws {
        let request = try ChatEgressHTTPCodec.makeRequest(
            provider: "grok",
            model: "grok-4.6",
            prompt: "Question:\nWhen?\n\nRetrieved transcript excerpts:\nFriday",
            apiKey: "xai-secret-should-not-appear-in-url"
        )
        XCTAssertEqual(request.url?.host, "api.x.ai")
        XCTAssertEqual(request.url?.path, "/v1/chat/completions")
        XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer xai-secret-should-not-appear-in-url")
        XCTAssertFalse(request.url?.absoluteString.contains("xai-secret") == true)
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("Retrieved transcript excerpts"))
        XCTAssertFalse(body.contains("xai-secret"))
    }

    func testOpenAIRequestUsesOfficialHost() throws {
        let request = try ChatEgressHTTPCodec.makeRequest(
            provider: "openai",
            model: "gpt-5",
            prompt: "Question:\nWhen?\n\nRetrieved transcript excerpts:\nFriday",
            apiKey: "sk-test"
        )
        XCTAssertEqual(request.url?.host, "api.openai.com")
        XCTAssertEqual(request.url?.path, "/v1/chat/completions")
    }

    func testGeminiRequestUsesOfficialGenerateContentEndpoint() throws {
        let request = try ChatEgressHTTPCodec.makeRequest(
            provider: "gemini",
            model: "gemini-2.5-flash",
            prompt: "Question:\nWhen?\n\nRetrieved transcript excerpts:\nFriday",
            apiKey: "AIza-test"
        )
        XCTAssertEqual(request.url?.host, "generativelanguage.googleapis.com")
        XCTAssertTrue(request.url?.path.contains("gemini-2.5-flash:generateContent") == true)
    }

    func testAppleProviderIsRejectedByTheHelper() {
        XCTAssertThrowsError(
            try ChatEgressHTTPCodec.makeRequest(
                provider: "appleOnDevice",
                model: "",
                prompt: "Question:\nWhen?",
                apiKey: "unused"
            )
        )
    }

    func testPromptCapRejectsMeetingSizedPayloads() {
        let huge = String(repeating: "a", count: ChatEgressHTTPCodec.maximumPromptCharacters + 1)
        XCTAssertThrowsError(
            try ChatEgressHTTPCodec.makeRequest(
                provider: "grok",
                model: "grok-4.6",
                prompt: huge,
                apiKey: "xai-test"
            )
        ) { error in
            XCTAssertEqual(error as? ChatEgressHTTPCodec.CodecError, .promptTooLarge)
        }
    }

    func testOpenAICompatibleParserReadsMessageContent() throws {
        let data = Data(#"{"choices":[{"message":{"content":"{\"answer\":\"Friday.\"}"}}]}"#.utf8)
        let text = try ChatEgressHTTPCodec.parseResponse(provider: "grok", data: data, statusCode: 200)
        XCTAssertTrue(text.contains("Friday"))
    }

    func testUnauthorizedStatusMapsToReconnect() {
        XCTAssertThrowsError(
            try ChatEgressHTTPCodec.parseResponse(provider: "openai", data: Data("{}".utf8), statusCode: 401)
        ) { error in
            XCTAssertEqual(error as? ChatEgressHTTPCodec.CodecError, .unauthorized)
        }
    }

    func testGeminiParserReadsFirstCandidateText() throws {
        let json = """
        {"candidates":[{"content":{"parts":[{"text":"{\\"answer\\":\\"Friday.\\"}"}]}}]}
        """
        let text = try ChatEgressHTTPCodec.parseResponse(
            provider: "gemini",
            data: Data(json.utf8),
            statusCode: 200
        )
        XCTAssertTrue(text.contains("Friday"))
    }
}
