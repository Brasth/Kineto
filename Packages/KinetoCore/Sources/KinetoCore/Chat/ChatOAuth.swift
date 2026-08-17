import CryptoKit
import Foundation

public enum ChatCredentialKind: String, Codable, Sendable, Equatable {
    case apiKey
    case oauth
}

public struct ChatProviderSecret: Codable, Equatable, Sendable {
    public var kind: ChatCredentialKind
    public var apiKey: String?
    public var accessToken: String?
    public var refreshToken: String?
    public var expiresAt: Date?
    public var tokenType: String?
    public var scope: String?
    public var clientID: String?

    public init(
        kind: ChatCredentialKind,
        apiKey: String? = nil,
        accessToken: String? = nil,
        refreshToken: String? = nil,
        expiresAt: Date? = nil,
        tokenType: String? = nil,
        scope: String? = nil,
        clientID: String? = nil
    ) {
        self.kind = kind
        self.apiKey = apiKey
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.tokenType = tokenType
        self.scope = scope
        self.clientID = clientID
    }

    public static func apiKey(_ key: String) -> ChatProviderSecret {
        ChatProviderSecret(kind: .apiKey, apiKey: key)
    }

    public var requestToken: String? {
        switch kind {
        case .apiKey:
            let trimmed = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        case .oauth:
            let trimmed = accessToken?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }
    }

    public var needsRefresh: Bool {
        guard kind == .oauth, refreshToken?.isEmpty == false else { return false }
        guard let expiresAt else { return true }
        return expiresAt.timeIntervalSinceNow < 90
    }
}

public struct ChatOAuthClientConfig: Codable, Equatable, Sendable {
    public var clientID: String
    public var clientSecret: String?

    public init(clientID: String, clientSecret: String? = nil) {
        self.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = clientSecret?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.clientSecret = (secret?.isEmpty == false) ? secret : nil
    }
}

public struct ChatOAuthTokenResponse: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date?
    public var tokenType: String?
    public var scope: String?

    public init(
        accessToken: String,
        refreshToken: String? = nil,
        expiresAt: Date? = nil,
        tokenType: String? = nil,
        scope: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.tokenType = tokenType
        self.scope = scope
    }

    public func applying(to existing: ChatProviderSecret?, clientID: String) -> ChatProviderSecret {
        ChatProviderSecret(
            kind: .oauth,
            accessToken: accessToken,
            refreshToken: refreshToken ?? existing?.refreshToken,
            expiresAt: expiresAt,
            tokenType: tokenType ?? "Bearer",
            scope: scope,
            clientID: clientID
        )
    }
}

public enum ChatOAuthPKCE {
    public static func makeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    public static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }
}

public enum ChatOAuthEndpoints {
    public static let kinetoCallbackScheme = "com.huynguyen.Kineto"
    public static let geminiScope = "https://www.googleapis.com/auth/generative-language.retriever"
    public static let googleAuthorization = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    public static let googleToken = URL(string: "https://oauth2.googleapis.com/token")!

    public static func supportsSignIn(_ provider: ChatProviderID) -> Bool {
        provider == .gemini
    }

    public static func authorizationURL(
        provider: ChatProviderID,
        clientID: String,
        state: String,
        codeChallenge: String
    ) -> URL? {
        guard provider == .gemini else { return nil }
        var components = URLComponents(url: googleAuthorization, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI(clientID: clientID, provider: provider).absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: geminiScope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        return components?.url
    }

    public static func redirectURI(clientID: String, provider: ChatProviderID) -> URL {
        if provider == .gemini, let google = googleNativeRedirectURI(clientID: clientID) {
            return google
        }
        return URL(string: "\(kinetoCallbackScheme):/oauth/\(provider.rawValue)")!
    }

    public static func callbackScheme(clientID: String, provider: ChatProviderID) -> String {
        if provider == .gemini, let scheme = googleNativeScheme(clientID: clientID) {
            return scheme
        }
        return kinetoCallbackScheme
    }

    public static func authorizationCode(from callback: URL, expectedState: String) -> String? {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let state = items.first(where: { $0.name == "state" })?.value
        guard state == expectedState else { return nil }
        let code = items.first(where: { $0.name == "code" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (code?.isEmpty == false) ? code : nil
    }

    public static func parseTokenResponse(_ data: Data, now: Date = Date()) throws -> ChatOAuthTokenResponse {
        let decoded = try JSONDecoder().decode(GoogleTokenPayload.self, from: data)
        let access = decoded.access_token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !access.isEmpty else { throw ChatGenerationError.invalidPayload }
        let refresh = decoded.refresh_token?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ChatOAuthTokenResponse(
            accessToken: access,
            refreshToken: (refresh?.isEmpty == false) ? refresh : nil,
            expiresAt: decoded.expires_in.map { now.addingTimeInterval(TimeInterval($0)) },
            tokenType: decoded.token_type,
            scope: decoded.scope
        )
    }

    private static func googleNativeScheme(clientID: String) -> String? {
        guard clientID.hasSuffix(".apps.googleusercontent.com") else { return nil }
        let prefix = String(clientID.dropLast(".apps.googleusercontent.com".count))
        guard !prefix.isEmpty else { return nil }
        return "com.googleusercontent.apps.\(prefix)"
    }

    private static func googleNativeRedirectURI(clientID: String) -> URL? {
        guard let scheme = googleNativeScheme(clientID: clientID) else { return nil }
        return URL(string: "\(scheme):/oauth2redirect")
    }
}

private struct GoogleTokenPayload: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int?
    let token_type: String?
    let scope: String?
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
