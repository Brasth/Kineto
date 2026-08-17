import Foundation

/// Sends the already-retrieved excerpt prompt through an isolated transport.
/// The transport must never receive meeting packages, keys, or audio.
public protocol ChatEgressTransporting: Sendable {
    func complete(
        provider: ChatProviderID,
        model: String,
        prompt: String,
        apiKey: String
    ) async throws -> String
}

/// Cloud generator. Retrieval and citation validation stay in `MeetingChatService`.
public struct RemoteChatGenerator: MeetingChatGenerating {
    public let provider: ChatProviderID
    public let model: String
    private let transport: any ChatEgressTransporting
    private let resolveAPIKey: @Sendable () async throws -> String?
    private let connected: Bool
    private let egressAllowed: Bool

    public init(
        provider: ChatProviderID,
        transport: any ChatEgressTransporting,
        model: String? = nil,
        isConnected: Bool,
        egressAllowed: Bool,
        resolveAPIKey: @escaping @Sendable () async throws -> String?
    ) {
        self.provider = provider
        self.model = model ?? provider.defaultModel
        self.transport = transport
        self.connected = isConnected
        self.egressAllowed = egressAllowed
        self.resolveAPIKey = resolveAPIKey
    }

    public func capability(for language: SpokenLanguage) -> MeetingChatModelCapability {
        if !connected { return .providerDisconnected }
        if !egressAllowed { return .userDeniedEgress }
        return .available
    }

    public func generate(_ request: MeetingChatRequest) async throws -> MeetingChatGeneration {
        if !connected { throw ChatGenerationError.disconnected }
        if !egressAllowed { throw ChatGenerationError.deniedEgress }
        guard let key = try await resolveAPIKey(), !key.isEmpty else {
            throw ChatGenerationError.disconnected
        }
        do {
            let raw = try await transport.complete(
                provider: provider,
                model: model,
                prompt: request.prompt,
                apiKey: key
            )
            return try RemoteChatPayloadParser.parse(raw)
        } catch let error as ChatGenerationError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ChatGenerationError.remoteFailure
        }
    }
}
