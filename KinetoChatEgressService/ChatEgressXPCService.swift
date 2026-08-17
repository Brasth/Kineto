import Foundation

final class ChatEgressXPCService: NSObject, ChatEgressServiceProtocol, @unchecked Sendable {
    private let client = ChatEgressHTTPClient()

    func complete(
        provider: String,
        model: String,
        prompt: String,
        apiKey: String,
        withReply reply: @escaping @Sendable (NSString?, NSError?) -> Void
    ) {
        let once = OnceReply(reply)
        Task {
            do {
                let text = try await client.complete(
                    provider: provider,
                    model: model,
                    prompt: prompt,
                    apiKey: apiKey
                )
                once.send(text as NSString, nil)
            } catch is CancellationError {
                once.send(nil, ChatEgressXPCError.make(code: ChatEgressXPCError.cancelled, message: "Cancelled"))
            } catch ChatEgressHTTPCodec.CodecError.unauthorized {
                once.send(nil, ChatEgressXPCError.make(code: ChatEgressXPCError.unauthorized, message: "Provider rejected the API key."))
            } catch ChatEgressHTTPCodec.CodecError.emptyPrompt {
                once.send(nil, ChatEgressXPCError.make(code: ChatEgressXPCError.invalidRequest, message: "Invalid chat request."))
            } catch ChatEgressHTTPCodec.CodecError.unsupportedProvider {
                once.send(nil, ChatEgressXPCError.make(code: ChatEgressXPCError.invalidRequest, message: "Invalid chat request."))
            } catch ChatEgressHTTPCodec.CodecError.promptTooLarge {
                once.send(nil, ChatEgressXPCError.make(code: ChatEgressXPCError.tooLarge, message: "Retrieved excerpt prompt exceeds the send limit."))
            } catch {
                once.send(nil, ChatEgressXPCError.make(code: ChatEgressXPCError.remoteFailure, message: "The AI provider refused or failed this request."))
            }
        }
    }
}

private final class OnceReply: @unchecked Sendable {
    private let lock = NSLock()
    private var reply: (@Sendable (NSString?, NSError?) -> Void)?

    init(_ reply: @escaping @Sendable (NSString?, NSError?) -> Void) {
        self.reply = reply
    }

    func send(_ value: NSString?, _ error: NSError?) {
        lock.lock()
        let pending = reply
        reply = nil
        lock.unlock()
        pending?(value, error)
    }
}
