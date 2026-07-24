import Foundation
import XCTest
@testable import Kineto

final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var redirect: ((URLRequest) -> (HTTPURLResponse, URLRequest)?)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let redirect = Self.redirect,
           let (response, redirectedRequest) = redirect(request) {
            client?.urlProtocol(
                self,
                wasRedirectedTo: redirectedRequest,
                redirectResponse: response
            )
            return
        }
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "test", code: -1))
            return
        }
        do {
            let (resp, data) = try handler(request)
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func stubSession() -> URLSession {
    let cfg = URLSessionConfiguration.ephemeral
    cfg.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: cfg)
}

final class PetDexNetworkServiceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.handler = nil
        StubURLProtocol.redirect = nil
    }

    func test_fetchManifestUsesFixedURLAndRejectsNon200() async throws {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        let client = PetDexNetworkClient(configuration: cfg)

        StubURLProtocol.handler = { req in
            XCTAssertEqual(req.url?.absoluteString, "https://petdex.dev/api/manifest")
            let resp = HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (resp, Data())
        }

        do {
            _ = try await client.fetchManifest()
            XCTFail("Expected error for non-200")
        } catch let error as NSError {
            XCTAssertEqual(error.domain, "KinetoPetCatalog")
            XCTAssertEqual(error.code, 2)
        }
    }

    func testFetchManifestAllowsPetDexRedirectToAssetsHost() async throws {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        let client = PetDexNetworkClient(configuration: cfg)
        let destination = URL(string: "https://assets.petdex.dev/manifests/petdex-v1.json")!

        StubURLProtocol.redirect = { request in
            guard request.url?.host == "petdex.dev" else { return nil }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 302,
                httpVersion: nil,
                headerFields: ["Location": destination.absoluteString]
            )!
            return (response, URLRequest(url: destination))
        }
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url, destination)
            let response = HTTPURLResponse(
                url: destination,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(#"{"pets":[]}"#.utf8))
        }

        let manifest = try await client.fetchManifest()
        XCTAssertEqual(manifest, Data(#"{"pets":[]}"#.utf8))
    }

    func test_fetchManifestRejectsOversize() async throws {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        let client = PetDexNetworkClient(configuration: cfg)

        StubURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Length": "\(6 * 1024 * 1024)"])!
            return (resp, Data(repeating: 0, count: 6 * 1024 * 1024))
        }

        do {
            _ = try await client.fetchManifest()
            XCTFail("Should reject >5MiB")
        } catch let error as NSError {
            XCTAssertEqual(error.code, 6)
        }
    }

    func test_downloadPetRejectsInvalidAssetHost() async throws {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        let client = PetDexNetworkClient(configuration: cfg)

        let badURL = URL(string: "https://evil.com/pets/foo.png")!
        do {
            _ = try await client.fetchAsset(from: badURL, maxBytes: 1024, purpose: "test")
            XCTFail("Should reject bad host")
        } catch let error as NSError {
            XCTAssertEqual(error.code, 5)
        }
    }

    func test_assetURLPolicyAllowsOnlyManifestOwnedPathsOnAssetsHost() async throws {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        let client = PetDexNetworkClient(configuration: cfg)

        StubURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data("ok".utf8))
        }

        let good = URL(string: "https://assets.petdex.dev/pets/boba/spritesheet.png")!
        let data = try await client.fetchAsset(from: good, maxBytes: 1024, purpose: "sprite")
        XCTAssertEqual(data, Data("ok".utf8))

        let badPath = URL(string: "https://assets.petdex.dev/other/boba.png")!
        do {
            _ = try await client.fetchAsset(from: badPath, maxBytes: 1024, purpose: "bad")
            XCTFail("Bad path prefix should be rejected")
        } catch let error as NSError {
            XCTAssertEqual(error.code, 5)
        }
    }

    func test_enforcesPerTypeSizeCaps() async throws {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        let client = PetDexNetworkClient(configuration: cfg)

        StubURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Length": "17000000"])!
            return (resp, Data(repeating: 0, count: 17000000))
        }

        let url = URL(string: "https://assets.petdex.dev/pets/x/s.png")!
        do {
            _ = try await client.fetchAsset(from: url, maxBytes: 16 * 1024 * 1024, purpose: "sprite")
            XCTFail("Sprite >16MiB rejected")
        } catch let error as NSError {
            XCTAssertEqual(error.code, 6)
        }
    }

    func test_cancellationMapsToCode7() async throws {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        let client = PetDexNetworkClient(configuration: cfg)

        StubURLProtocol.handler = { req in
            Thread.sleep(forTimeInterval: 5)
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data())
        }

        let task = Task {
            try await client.fetchManifest()
        }

        try? await Task.sleep(nanoseconds: 10_000_000)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch let error as NSError {
            XCTAssertTrue(error.code == 7 || error.domain.contains("NSURLError") || error.domain.contains("URLError"))
        }
    }

}
