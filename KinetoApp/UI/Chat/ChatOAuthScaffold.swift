import Foundation
import KinetoCore

/// Official-only OAuth scaffolding. No unofficial subscription clients.
///
/// - Grok / OpenAI: paste a console API key until those vendors issue Kineto a client ID.
/// - Gemini: official Google OAuth for the Gemini API is allowed when
///   `KINETO_GEMINI_OAUTH_CLIENT_ID` is compiled in. Until then, paste an API key.
/// - Never implement Antigravity CLI token reuse.
enum ChatOAuthScaffold {
    static let geminiClientID = ProcessInfo.processInfo.environment["KINETO_GEMINI_OAUTH_CLIENT_ID"]

    static var geminiSignInAvailable: Bool {
        geminiClientID?.isEmpty == false
    }

    static func authorizationURL(for provider: ChatProviderID) -> URL? {
        switch provider {
        case .appleOnDevice, .grok, .openai:
            return nil
        case .gemini:
            guard let clientID = geminiClientID, !clientID.isEmpty else { return nil }
            var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
            components?.queryItems = [
                URLQueryItem(name: "client_id", value: clientID),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/generative-language.retriever"),
                URLQueryItem(name: "redirect_uri", value: "com.huynguyen.Kineto:/oauth/gemini")
            ]
            return components?.url
        }
    }

    static var officialSignInStatus: String {
        if geminiSignInAvailable {
            return "Google sign-in can request a Gemini API token. Grok and OpenAI still use console API keys."
        }
        return "Sign in with Grok or ChatGPT ships only after those vendors issue Kineto a client ID. Paste an official API key for now. Antigravity CLI OAuth is not supported."
    }
}

enum ChatOAuthScaffoldError: Error, Equatable {
    case notConfigured
    case unsupportedProvider
}
