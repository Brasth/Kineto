import Foundation
import KinetoCore

/// Main-app transport. The application target still has no network entitlement.
final class ChatEgressXPCClient: ChatEgressTransporting, @unchecked Sendable {
    static let serviceName = "com.huynguyen.Kineto.ChatEgressService"

    private var connection: NSXPCConnection?

    private func makeConnection() -> NSXPCConnection {
        let conn = NSXPCConnection(serviceName: Self.serviceName)
        conn.remoteObjectInterface = NSXPCInterface(with: ChatEgressServiceProtocol.self)
        conn.interruptionHandler = { [weak self] in
            self?.connection = nil
        }
        conn.invalidationHandler = { [weak self] in
            self?.connection = nil
        }
        conn.resume()
        return conn
    }

    func complete(
        provider: ChatProviderID,
        model: String,
        prompt: String,
        apiKey: String
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let conn = self.connection ?? self.makeConnection()
            self.connection = conn

            guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
                continuation.resume(throwing: error)
            }) as? ChatEgressServiceProtocol else {
                continuation.resume(
                    throwing: ChatEgressXPCError.make(code: ChatEgressXPCError.connection, message: "XPC proxy unavailable")
                )
                return
            }

            proxy.complete(
                provider: provider.rawValue,
                model: model,
                prompt: prompt,
                apiKey: apiKey
            ) { text, error in
                if let error {
                    continuation.resume(throwing: Self.map(error))
                    return
                }
                guard let text, (text as String).isEmpty == false else {
                    continuation.resume(throwing: ChatGenerationError.invalidPayload)
                    return
                }
                continuation.resume(returning: text as String)
            }
        }
    }

    private static func map(_ error: Error) -> Error {
        let nsError = error as NSError
        if nsError.domain == ChatEgressXPCError.domain {
            switch nsError.code {
            case ChatEgressXPCError.unauthorized:
                return ChatGenerationError.disconnected
            case ChatEgressXPCError.cancelled:
                return CancellationError()
            case ChatEgressXPCError.invalidRequest:
                return ChatGenerationError.invalidPayload
            default:
                return ChatGenerationError.remoteFailure
            }
        }
        return ChatGenerationError.remoteFailure
    }
}
