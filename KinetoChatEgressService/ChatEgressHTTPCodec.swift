import Foundation

/// Pure request/response codec for official Grok, OpenAI, and Gemini HTTP APIs.
/// Compiled into the XPC helper and into tests. Never logs secrets or prompts.
enum ChatEgressHTTPCodec {
    static let allowedHosts: Set<String> = [
        "api.x.ai",
        "api.openai.com",
        "generativelanguage.googleapis.com",
        "oauth2.googleapis.com"
    ]
    static let maximumPromptCharacters = 48_000
    static let maximumResponseBytes = 1_048_576

    static let groundedInstructions = """
        Answer only from the retrieved transcript excerpts in the user prompt.
        Do not infer facts absent from those excerpts. Return an answer only when it is supported.
        Every citation must use a supplied segment UUID and an exact contiguous quote copied from that supplied excerpt.
        Reply with JSON only, no markdown fences:
        {"answer":"...","citations":[{"segmentID":"<uuid>","quote":"<exact excerpt span>"}]}
        """

    enum CodecError: Error, Equatable {
        case unsupportedProvider
        case emptyPrompt
        case promptTooLarge
        case unauthorized
        case remoteFailure(status: Int)
        case invalidResponse
    }

    static func validatePrompt(_ prompt: String) throws {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw CodecError.emptyPrompt }
        if trimmed.count > maximumPromptCharacters { throw CodecError.promptTooLarge }
    }

    static func makeRequest(
        provider: String,
        model: String,
        prompt: String,
        apiKey: String,
        authKind: String = "apiKey"
    ) throws -> URLRequest {
        try validatePrompt(prompt)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw CodecError.unauthorized }

        switch provider {
        case "grok":
            return try openAICompatibleRequest(
                url: URL(string: "https://api.x.ai/v1/chat/completions")!,
                model: model.isEmpty ? "grok-4.6" : model,
                prompt: prompt,
                apiKey: trimmedKey
            )
        case "openai":
            return try openAICompatibleRequest(
                url: URL(string: "https://api.openai.com/v1/chat/completions")!,
                model: model.isEmpty ? "gpt-5" : model,
                prompt: prompt,
                apiKey: trimmedKey
            )
        case "gemini":
            return try geminiRequest(
                model: model.isEmpty ? "gemini-2.5-flash" : model,
                prompt: prompt,
                credential: trimmedKey,
                useBearer: authKind == "oauth"
            )
        default:
            throw CodecError.unsupportedProvider
        }
    }

    static func makeTokenRequest(
        provider: String,
        clientID: String,
        clientSecret: String,
        grantType: String,
        code: String,
        redirectURI: String,
        codeVerifier: String,
        refreshToken: String
    ) throws -> URLRequest {
        guard provider == "gemini" else { throw CodecError.unsupportedProvider }
        let trimmedClient = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedClient.isEmpty else { throw CodecError.unauthorized }

        var items: [URLQueryItem]
        switch grantType {
        case "refresh_token":
            let token = refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { throw CodecError.unauthorized }
            items = [
                URLQueryItem(name: "grant_type", value: "refresh_token"),
                URLQueryItem(name: "refresh_token", value: token),
                URLQueryItem(name: "client_id", value: trimmedClient)
            ]
        case "authorization_code":
            let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedRedirect = redirectURI.trimmingCharacters(in: .whitespacesAndNewlines)
            let verifier = codeVerifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedCode.isEmpty, !trimmedRedirect.isEmpty, !verifier.isEmpty else {
                throw CodecError.emptyPrompt
            }
            items = [
                URLQueryItem(name: "grant_type", value: "authorization_code"),
                URLQueryItem(name: "code", value: trimmedCode),
                URLQueryItem(name: "redirect_uri", value: trimmedRedirect),
                URLQueryItem(name: "client_id", value: trimmedClient),
                URLQueryItem(name: "code_verifier", value: verifier)
            ]
        default:
            throw CodecError.unsupportedProvider
        }
        let secret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        if !secret.isEmpty {
            items.append(URLQueryItem(name: "client_secret", value: secret))
        }
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&="))
        request.httpBody = Data(items.compactMap { item -> String? in
            guard let value = item.value else { return nil }
            let name = item.name.addingPercentEncoding(withAllowedCharacters: allowed) ?? item.name
            let escaped = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(name)=\(escaped)"
        }.joined(separator: "&").utf8)
        return request
    }

    static func parseResponse(provider: String, data: Data, statusCode: Int) throws -> String {
        if statusCode == 401 || statusCode == 403 {
            throw CodecError.unauthorized
        }
        guard (200...299).contains(statusCode) else {
            throw CodecError.remoteFailure(status: statusCode)
        }
        guard data.count <= maximumResponseBytes else {
            throw CodecError.invalidResponse
        }
        switch provider {
        case "grok", "openai":
            return try parseOpenAICompatible(data)
        case "gemini":
            return try parseGemini(data)
        default:
            throw CodecError.unsupportedProvider
        }
    }

    static func isAllowed(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              allowedHosts.contains(host),
              url.user == nil,
              url.password == nil
        else {
            return false
        }
        return true
    }

    private static func openAICompatibleRequest(
        url: URL,
        model: String,
        prompt: String,
        apiKey: String
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": model,
            "temperature": 0,
            "messages": [
                ["role": "system", "content": groundedInstructions],
                ["role": "user", "content": prompt]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func geminiRequest(
        model: String,
        prompt: String,
        credential: String,
        useBearer: Bool
    ) throws -> URLRequest {
        var components = URLComponents(
            string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        )
        if !useBearer {
            components?.queryItems = [URLQueryItem(name: "key", value: credential)]
        }
        guard let url = components?.url else { throw CodecError.unsupportedProvider }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if useBearer {
            request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        }
        let body: [String: Any] = [
            "system_instruction": [
                "parts": [["text": groundedInstructions]]
            ],
            "contents": [
                ["role": "user", "parts": [["text": prompt]]]
            ],
            "generationConfig": ["temperature": 0]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func parseOpenAICompatible(_ data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            throw CodecError.invalidResponse
        }
        if let content = message["content"] as? String {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw CodecError.invalidResponse }
            return trimmed
        }
        if let parts = message["content"] as? [[String: Any]] {
            let text = parts.compactMap { $0["text"] as? String }.joined()
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw CodecError.invalidResponse }
            return trimmed
        }
        throw CodecError.invalidResponse
    }

    private static func parseGemini(_ data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any],
              let candidates = root["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw CodecError.invalidResponse
        }
        let text = parts.compactMap { $0["text"] as? String }.joined()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CodecError.invalidResponse }
        return trimmed
    }
}
