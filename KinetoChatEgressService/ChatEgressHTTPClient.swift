import Foundation

private final class ChatEgressRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, ChatEgressHTTPCodec.isAllowed(url) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

final class ChatEgressHTTPClient {
    private let session: URLSession
    private let redirectDelegate: ChatEgressRedirectDelegate

    init(session: URLSession? = nil) {
        let delegate = ChatEgressRedirectDelegate()
        self.redirectDelegate = delegate
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 45
            config.timeoutIntervalForResource = 75
            config.waitsForConnectivity = false
            self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        }
    }

    func complete(
        provider: String,
        model: String,
        prompt: String,
        apiKey: String
    ) async throws -> String {
        let request = try ChatEgressHTTPCodec.makeRequest(
            provider: provider,
            model: model,
            prompt: prompt,
            apiKey: apiKey
        )
        guard let url = request.url, ChatEgressHTTPCodec.isAllowed(url) else {
            throw ChatEgressHTTPCodec.CodecError.unsupportedProvider
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ChatEgressHTTPCodec.CodecError.invalidResponse
        }
        return try ChatEgressHTTPCodec.parseResponse(
            provider: provider,
            data: data,
            statusCode: http.statusCode
        )
    }
}
