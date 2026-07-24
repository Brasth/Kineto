import Foundation

private final class RedirectPolicyDelegate: NSObject, URLSessionTaskDelegate {
    private let allowedHosts: Set<String> = ["petdex.dev", "assets.petdex.dev"]

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let to = request.url else { completionHandler(nil); return }
        guard isSafe(to) else { completionHandler(nil); return }
        completionHandler(request)
    }

    private func isSafe(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              allowedHosts.contains(host),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil
        else { return false }
        return true
    }
}

final class PetDexNetworkClient {
    private let session: URLSession
    private let allowedHosts: Set<String> = ["petdex.dev", "assets.petdex.dev"]
    private let redirectDelegate: RedirectPolicyDelegate

    init(configuration: URLSessionConfiguration? = nil) {
        let delegate = RedirectPolicyDelegate()
        self.redirectDelegate = delegate
        if let cfg = configuration {
            self.session = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 60
            config.waitsForConnectivity = false
            self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        }
    }

    convenience init(session: URLSession) {
        self.init(configuration: session.configuration)
    }

    func fetchManifest() async throws -> Data {
        guard let url = URL(string: "https://petdex.dev/api/manifest") else {
            throw makeError(code: 5, message: "Invalid manifest URL")
        }
        return try await performDownload(for: url, maxBytes: 5 * 1024 * 1024, purpose: "manifest")
    }

    func fetchAsset(from url: URL, maxBytes: Int, purpose: String) async throws -> Data {
        guard isAllowedAssetURL(url) else {
            throw makeError(code: 5, message: "Asset URL not permitted")
        }
        return try await performDownload(for: url, maxBytes: maxBytes, purpose: purpose)
    }

    private func performDownload(for url: URL, maxBytes: Int, purpose: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json, image/*", forHTTPHeaderField: "Accept")

        do {
            let (location, response) = try await session.download(for: request)

            guard let http = response as? HTTPURLResponse else {
                throw makeError(code: 2, message: "Non-HTTP response for \(purpose)")
            }
            guard http.statusCode == 200 else {
                throw makeError(code: 2, message: "HTTP \(http.statusCode) for \(purpose)")
            }

            if let final = http.url {
                if !isSafeFinalURL(final) {
                    try? FileManager.default.removeItem(at: location)
                    throw makeError(code: 5, message: "Final URL not permitted")
                }
                if purpose != "manifest" && !isAllowedAssetURL(final) {
                    try? FileManager.default.removeItem(at: location)
                    throw makeError(code: 5, message: "Final asset URL not permitted")
                }
            }

            if let contentLength = http.value(forHTTPHeaderField: "Content-Length"),
               let declared = Int64(contentLength),
               declared > maxBytes {
                try? FileManager.default.removeItem(at: location)
                throw makeError(code: 6, message: "Declared size too large for \(purpose)")
            }

            let data = try Data(contentsOf: location, options: .mappedIfSafe)
            try? FileManager.default.removeItem(at: location)

            if data.count > maxBytes {
                throw makeError(code: 6, message: "Payload too large for \(purpose)")
            }
            return data
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                throw makeError(code: 7, message: "Cancelled")
            }
            if let urlErr = error as? URLError, urlErr.code == .notConnectedToInternet || urlErr.code == .timedOut || urlErr.code == .cannotConnectToHost {
                throw makeError(code: 1, message: "Connection unavailable")
            }
            let ns = error as NSError
            if ns.domain == "KinetoPetCatalog" {
                throw ns
            }
            throw makeError(code: 2, message: "Invalid response")
        }
    }

    private func isAllowedAssetURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              host == "assets.petdex.dev",
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil
        else { return false }
        let p = url.path.lowercased()
        return p.hasPrefix("/pets/") || p.hasPrefix("/curated/") || p.hasPrefix("/manifests/")
    }

    private func isSafeFinalURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              allowedHosts.contains(host),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil
        else { return false }
        return true
    }

    private func makeError(code: Int, message: String) -> NSError {
        NSError(domain: "KinetoPetCatalog", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
