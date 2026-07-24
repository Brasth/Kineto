import Foundation

/// Concrete transport that talks to the embedded XPC service from the main app.
/// The main app must never link or compile the network implementation files.
final class PetDexXPCClient: PetDexCatalogTransport, @unchecked Sendable {
    private var connection: NSXPCConnection?
    private let serviceName = "com.huynguyen.Kineto.PetCatalogService"

    private func makeConnection() -> NSXPCConnection {
        let conn = NSXPCConnection(serviceName: serviceName)
        conn.remoteObjectInterface = NSXPCInterface(with: PetDexCatalogServiceProtocol.self)
        conn.interruptionHandler = { [weak self] in
            self?.connection = nil
        }
        conn.invalidationHandler = { [weak self] in
            self?.connection = nil
        }
        conn.resume()
        return conn
    }

    private func withProxy<T: Sendable>(
        _ perform: @escaping @Sendable (PetDexCatalogServiceProtocol, @escaping @Sendable (T) -> Void, @escaping @Sendable (Error) -> Void) -> Void
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let conn = self.connection ?? self.makeConnection()
            self.connection = conn

            guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
                continuation.resume(throwing: error)
            }) as? PetDexCatalogServiceProtocol else {
                continuation.resume(throwing: self.makeError(code: 1, message: "XPC proxy unavailable"))
                return
            }

            perform(proxy, { value in
                continuation.resume(returning: value)
            }, { error in
                continuation.resume(throwing: error)
            })
        }
    }

    func refreshCatalog() async throws -> Data {
        try await withProxy { (proxy: PetDexCatalogServiceProtocol, success: @escaping @Sendable (Data) -> Void, failure: @escaping @Sendable (Error) -> Void) in
            proxy.refreshCatalog { data, error in
                if let error { failure(error); return }
                guard let data else {
                    failure(self.makeError(code: 2, message: "Empty catalog response"))
                    return
                }
                success(data as Data)
            }
        }
    }

    func downloadPet(slug: String) async throws -> (petJSON: Data, sprite: Data, manifestItem: Data) {
        try await withProxy { (proxy: PetDexCatalogServiceProtocol, success: @escaping @Sendable ((Data, Data, Data)) -> Void, failure: @escaping @Sendable (Error) -> Void) in
            proxy.downloadPet(slug: slug) { petJSON, sprite, item, error in
                if let error { failure(error); return }
                guard let petJSON, let sprite, let item else {
                    failure(self.makeError(code: 2, message: "Incomplete pet download response"))
                    return
                }
                success((petJSON as Data, sprite as Data, item as Data))
            }
        }
    }

    private func makeError(code: Int, message: String) -> NSError {
        NSError(domain: "KinetoPetCatalog", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

/// Abstraction used by the repository so tests can inject fakes.
protocol PetDexCatalogTransport: Sendable {
    func refreshCatalog() async throws -> Data
    func downloadPet(slug: String) async throws -> (petJSON: Data, sprite: Data, manifestItem: Data)
}
