import Foundation

/// Isolated Chat Egress XPC. The helper receives only the already-retrieved
/// excerpt prompt plus a short-lived API key. It never opens meeting packages.
@objc protocol ChatEgressServiceProtocol {
    func complete(
        provider: String,
        model: String,
        prompt: String,
        apiKey: String,
        withReply reply: @escaping @Sendable (NSString?, NSError?) -> Void
    )
}

enum ChatEgressXPCError {
    static let domain = "KinetoChatEgress"

    static func make(code: Int, message: String) -> NSError {
        NSError(domain: domain, code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }

    static let connection = 1
    static let invalidRequest = 2
    static let unauthorized = 3
    static let remoteFailure = 4
    static let cancelled = 5
    static let tooLarge = 6
}
