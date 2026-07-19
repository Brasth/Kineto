import CryptoKit
import Foundation
import Testing
@testable import KinetoCore

@Test func modelStoreFailsClosedAndActivatesVerifiedBytes() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let bytes = Data("verified model bytes".utf8)
    let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    let descriptor = ModelDescriptor(
        id: "fixture",
        revision: "revision-1",
        fileName: "fixture.bin",
        downloadURL: URL(string: "https://example.invalid/fixture.bin")!,
        byteCount: Int64(bytes.count),
        sha256: digest,
        license: "fixture"
    )
    let store = ModelStore(rootURL: root)
    let staged = root.appending(path: "fixture.part")
    try bytes.write(to: staged)

    let active = try await store.activate(staged, descriptor: descriptor)
    #expect(try await store.activeModel(for: descriptor) == active)

    var mutated = bytes
    mutated[mutated.startIndex] ^= 0x01
    try mutated.write(to: active, options: .atomic)
    do {
        _ = try await store.activeModel(for: descriptor)
        Issue.record("Mutated model remained active")
    } catch let error as ModelStoreError {
        #expect(error == .checksumMismatch)
    }

    let repair = root.appending(path: "fixture-repair.part")
    try bytes.write(to: repair)
    let repaired = try await store.activate(repair, descriptor: descriptor)
    #expect(try Data(contentsOf: repaired) == bytes)
    #expect(try await store.activeModel(for: descriptor) == repaired)
}
