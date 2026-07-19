import CryptoKit
import Foundation
import Testing
@testable import KinetoCore

private actor MemoryMeetingKeyStore: MeetingKeyStore {
    private var values: [String: SymmetricKey] = [:]
    private var generations: [UUID: UUID] = [:]

    func createKey(for meetingID: UUID, purpose: MeetingKeyPurpose) throws -> SymmetricKey {
        let account = key(meetingID, purpose)
        guard values[account] == nil else {
            throw MeetingKeyStoreError.duplicate
        }
        let value = SymmetricKey(size: .bits256)
        values[account] = value
        return value
    }

    func key(for meetingID: UUID, purpose: MeetingKeyPurpose) throws -> SymmetricKey {
        guard let value = values[key(meetingID, purpose)] else {
            throw MeetingKeyStoreError.missing
        }
        return value
    }

    func deleteKey(for meetingID: UUID, purpose: MeetingKeyPurpose) {
        values.removeValue(forKey: key(meetingID, purpose))
    }

    func deleteKeys(for meetingID: UUID) {
        values.removeValue(forKey: key(meetingID, .text))
        values.removeValue(forKey: key(meetingID, .audio))
        generations[meetingID] = nil
    }

    func setGeneration(_ generation: UUID, for meetingID: UUID) {
        generations[meetingID] = generation
    }

    func generation(for meetingID: UUID) throws -> UUID {
        guard let generation = generations[meetingID] else {
            throw MeetingKeyStoreError.missing
        }
        return generation
    }

    func deleteGeneration(for meetingID: UUID) {
        generations[meetingID] = nil
    }

    private func key(_ meetingID: UUID, _ purpose: MeetingKeyPurpose) -> String {
        "\(meetingID.uuidString).\(purpose.rawValue)"
    }
}

private struct LegacyMeetingSnapshot: Codable {
    let meeting: Meeting
    let segments: [Segment]
    let gaps: [TranscriptGap]
    let translations: [TranslationRecord]
    let summary: SummaryRecord?
}

private struct ManifestTopology: Codable {
    let version: Int
    let generation: UUID
    let meetingID: UUID
    let segmentIDs: [UUID]
    let gapIDs: [UUID]
    let translationIDs: [UUID]
    let chatTurnIDs: [UUID]
    let hasSummary: Bool
    let retainsAudio: Bool
}

private func packageAAD(meetingID: UUID, generation: UUID, file: String) -> Data {
    Data("kineto/v1/\(meetingID.uuidString)/\(generation.uuidString)/\(file)".utf8)
}

private struct LegacyManifestTopology: Codable {
    let version: Int
    let generation: UUID
    let meetingID: UUID
    let segmentIDs: [UUID]
    let gapIDs: [UUID]
    let translationIDs: [UUID]
    let hasSummary: Bool
    let retainsAudio: Bool
}

private func sealForPackage<T: Encodable>(
    _ value: T,
    key: SymmetricKey,
    context: Data
) throws -> Data {
    let plaintext = try JSONEncoder().encode(value)
    guard let combined = try AES.GCM.seal(plaintext, using: key, authenticating: context).combined else {
        throw MeetingStoreError.corrupted
    }
    return combined
}

@Test func encryptedMeetingLifecyclePersistsOnlyFinalSourceRecords() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let keys = MemoryMeetingKeyStore()
    let store = MeetingPackageStore(rootURL: root, keys: keys)
    let meeting = Meeting(title: "Bilingual planning", retainsAudio: false)

    try await store.create(meeting)
    let empty = try await store.snapshot(for: meeting.id)
    #expect(empty.meeting == meeting)
    #expect(empty.segments.isEmpty)

    let volatile = Segment(
        meetingID: meeting.id,
        source: .selectedSource,
        startTime: 0,
        endTime: 1,
        language: .english,
        text: "Planning",
        isFinal: false
    )
    do {
        try await store.append(volatile)
        Issue.record("Volatile transcript was persisted")
    } catch let error as MeetingStoreError {
        #expect(error == .nonFinalSegment)
    }

    let final = Segment(
        meetingID: meeting.id,
        source: .selectedSource,
        startTime: 0,
        endTime: 2,
        language: .english,
        text: "Ship the local prototype.",
        confidence: 0.94,
        isFinal: true
    )
    try await store.append(final)
    try await store.updateState(.recording, for: meeting.id)
    try await store.updateState(.stopped, for: meeting.id)

    let summary = SummaryRecord(
        meetingID: meeting.id,
        language: .english,
        items: [
            SummaryItem(
                kind: .decision,
                text: "Ship the local prototype.",
                evidence: [EvidenceReference(segmentID: final.id, supportingText: final.text)]
            )
        ]
    )
    try await store.save(summary)

    let reopened = try await store.snapshot(for: meeting.id)
    #expect(reopened.meeting.state == .stopped)
    #expect(reopened.segments == [final])
    #expect(reopened.summary == summary)

    do {
        _ = try await keys.key(for: meeting.id, purpose: .audio)
        Issue.record("Audio-off meeting created an audio key")
    } catch let error as MeetingKeyStoreError {
        #expect(error == .missing)
    }
}

@Test func meetingStoreBatchesMultipleFinalSegmentsInOneCommit() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = MeetingPackageStore(rootURL: root, keys: MemoryMeetingKeyStore())
    let meeting = Meeting(title: "Batch append")
    try await store.create(meeting)
    try await store.updateState(.recording, for: meeting.id)

    let first = Segment(
        meetingID: meeting.id,
        source: .selectedSource,
        startTime: 0,
        endTime: 1,
        language: .english,
        text: "One",
        isFinal: true
    )
    let second = Segment(
        meetingID: meeting.id,
        source: .selectedSource,
        startTime: 1,
        endTime: 2,
        language: .english,
        text: "Two",
        isFinal: true
    )
    try await store.append(segments: [first, second])

    let snapshot = try await store.snapshot(for: meeting.id)
    #expect(snapshot.segments.map(\.text) == ["One", "Two"])
}

@Test func authenticatedMeetingPackageRejectsMutationAndDeletesKeysFirst() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let keys = MemoryMeetingKeyStore()
    let store = MeetingPackageStore(rootURL: root, keys: keys)
    let meeting = Meeting(title: "Tamper test")
    try await store.create(meeting)

    let packageURL = root.appending(path: meeting.id.uuidString)
    let generation = try String(contentsOf: packageURL.appending(path: "current"), encoding: .utf8)
    let textURL = packageURL
        .appending(path: generation.trimmingCharacters(in: .whitespacesAndNewlines))
        .appending(path: "text.knt")
    var bytes = try Data(contentsOf: textURL)
    bytes[bytes.startIndex] ^= 0x01
    try bytes.write(to: textURL, options: .atomic)

    do {
        _ = try await store.snapshot(for: meeting.id)
        Issue.record("Mutated ciphertext was accepted")
    } catch let error as MeetingStoreError {
        #expect(error == .corrupted)
    }

    try await store.delete(meetingID: meeting.id)
    #expect(!FileManager.default.fileExists(atPath: packageURL.path))
    do {
        _ = try await keys.key(for: meeting.id, purpose: .text)
        Issue.record("Deleted meeting key remained available")
    } catch let error as MeetingKeyStoreError {
        #expect(error == .missing)
    }
}

@Test func meetingLibraryListsAndAtomicallyExportsReopenableSnapshots() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let keys = MemoryMeetingKeyStore()
    let store = MeetingPackageStore(rootURL: root, keys: keys)
    let meeting = Meeting(title: "Export boundary")
    try await store.create(meeting)
    try await store.updateState(.recording, for: meeting.id)
    try await store.updateState(.stopped, for: meeting.id)

    let ids = try await store.meetingIDs()
    #expect(ids == [meeting.id])

    let destination = root.appending(path: "meeting.json")
    try await store.export(meetingID: meeting.id, to: destination)
    let exported = try JSONDecoder().decode(
        MeetingSnapshot.self,
        from: Data(contentsOf: destination)
    )
    #expect(exported.meeting.id == meeting.id)
    #expect(exported.meeting.state == .stopped)
}

@Test func stoppedMeetingRejectsLateTranscriptRecords() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = MeetingPackageStore(rootURL: root, keys: MemoryMeetingKeyStore())
    let meeting = Meeting(title: "Terminal state")
    try await store.create(meeting)
    try await store.updateState(.recording, for: meeting.id)
    let source = Segment(
        meetingID: meeting.id,
        source: .selectedSource,
        startTime: 0,
        endTime: 1,
        language: .english,
        text: "Existing source",
        isFinal: true
    )
    try await store.append(source)
    try await store.updateState(.stopped, for: meeting.id)

    let lateSegment = Segment(
        meetingID: meeting.id,
        source: .selectedSource,
        startTime: 1,
        endTime: 2,
        language: .english,
        text: "Too late",
        isFinal: true
    )
    let gap = TranscriptGap(
        meetingID: meeting.id,
        source: .selectedSource,
        timestamp: 1,
        reason: "too-late"
    )
    for operation in [
        { try await store.append(lateSegment) },
        { try await store.append(gap) }
    ] {
        do {
            try await operation()
            Issue.record("Stopped meeting accepted a transcript record")
        } catch let error as MeetingStoreError {
            #expect(error == .invalidState)
        }
    }

    let translation = TranslationRecord(
        sourceSegmentID: source.id,
        sourceLanguage: .english,
        targetLanguage: .vietnamese,
        text: "Bản dịch muộn"
    )
    try await store.append(translation, meetingID: meeting.id)
    // Idempotent retry after stop must not fail.
    try await store.append(translation, meetingID: meeting.id)
    let snapshot = try await store.snapshot(for: meeting.id)
    #expect(snapshot.translations.count == 1)
    #expect(snapshot.translations.first?.text == "Bản dịch muộn")
}

@Test func keychainGenerationPreventsCurrentPointerRollback() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let keys = MemoryMeetingKeyStore()
    let store = MeetingPackageStore(rootURL: root, keys: keys)
    let meeting = Meeting(title: "Rollback defense")
    try await store.create(meeting)
    let currentURL = root.appending(path: meeting.id.uuidString).appending(path: "current")
    let firstGeneration = try Data(contentsOf: currentURL)
    let segment = Segment(
        meetingID: meeting.id,
        source: .selectedSource,
        startTime: 0,
        endTime: 1,
        language: .english,
        text: "Newest committed transcript",
        isFinal: true
    )
    try await store.append(segment)

    try firstGeneration.write(to: currentURL, options: .atomic)
    let snapshot = try await store.snapshot(for: meeting.id)
    #expect(snapshot.segments == [segment])
}

@Test func deletionTombstoneRecoversInterruptedDeletion() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let keys = MemoryMeetingKeyStore()
    let store = MeetingPackageStore(rootURL: root, keys: keys)
    let meeting = Meeting(title: "Deletion recovery")
    try await store.create(meeting)
    let tombstone = root.appending(path: ".deleted-\(meeting.id.uuidString)")
    try Data(meeting.id.uuidString.utf8).write(to: tombstone)

    #expect(try await store.meetingIDs().isEmpty)
    try await store.recoverInterruptedDeletions()
    #expect(!FileManager.default.fileExists(atPath: root.appending(path: meeting.id.uuidString).path))
    #expect(!FileManager.default.fileExists(atPath: tombstone.path))
    do {
        _ = try await keys.key(for: meeting.id, purpose: .text)
        Issue.record("Recovered deletion retained the text key")
    } catch let error as MeetingKeyStoreError {
        #expect(error == .missing)
    }
}

@Test func chatTurnsPersistInV2ReopenExportAndDeletion() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let keys = MemoryMeetingKeyStore()
    let store = MeetingPackageStore(rootURL: root, keys: keys)
    let meeting = Meeting(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
        createdAt: Date(timeIntervalSince1970: 1),
        title: "Chat persistence"
    )
    let segment = Segment(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
        meetingID: meeting.id,
        source: .selectedSource,
        startTime: 0,
        endTime: 1,
        language: .english,
        text: "The launch is scheduled for Tuesday.",
        isFinal: true
    )
    let turn = ChatTurnRecord(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!,
        meetingID: meeting.id,
        createdAt: Date(timeIntervalSince1970: 2),
        responseLanguage: .english,
        question: "When is the launch?",
        answer: "The launch is scheduled for Tuesday.",
        outcome: .grounded,
        citations: [EvidenceReference(segmentID: segment.id, supportingText: segment.text)]
    )

    let noAnswerTurn = ChatTurnRecord(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000104")!,
        meetingID: meeting.id,
        createdAt: Date(timeIntervalSince1970: 3),
        responseLanguage: .english,
        question: "Who owns the launch?",
        answer: "I couldn't find that in the finalized transcript.",
        outcome: .noAnswer,
        noAnswerReason: .noRelevantEvidence,
        citations: []
    )

    try await store.create(meeting)
    try await store.updateState(.recording, for: meeting.id)
    try await store.append(segment)
    try await store.updateState(.stopped, for: meeting.id)
    try await store.append(turn)
    try await store.append(noAnswerTurn)

    let reopenedStore = MeetingPackageStore(rootURL: root, keys: keys)
    let reopened = try await reopenedStore.snapshot(for: meeting.id)
    #expect(reopened.chatTurns == [turn, noAnswerTurn])

    let generation = try await keys.generation(for: meeting.id)
    let key = try await keys.key(for: meeting.id, purpose: .text)
    let manifestURL = root
        .appending(path: meeting.id.uuidString)
        .appending(path: generation.uuidString)
        .appending(path: "manifest.knt")
    let manifestBox = try AES.GCM.SealedBox(combined: Data(contentsOf: manifestURL))
    let manifest = try JSONDecoder().decode(
        ManifestTopology.self,
        from: AES.GCM.open(
            manifestBox,
            using: key,
            authenticating: packageAAD(meetingID: meeting.id, generation: generation, file: "manifest")
        )
    )
    #expect(manifest.version == 2)
    #expect(manifest.chatTurnIDs == [turn.id, noAnswerTurn.id])

    let exportURL = root.appending(path: "chat.json")
    try await reopenedStore.export(meetingID: meeting.id, to: exportURL)
    let exported = try JSONDecoder().decode(MeetingSnapshot.self, from: Data(contentsOf: exportURL))
    #expect(exported.chatTurns == [turn, noAnswerTurn])

    try await reopenedStore.delete(meetingID: meeting.id)
    #expect(!FileManager.default.fileExists(atPath: root.appending(path: meeting.id.uuidString).path))
}

@Test func v1PackagesDecodeAsEmptyChatHistoryAndUpgradeOnChatAppend() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let keys = MemoryMeetingKeyStore()
    let store = MeetingPackageStore(rootURL: root, keys: keys)
    let meeting = Meeting(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
        createdAt: Date(timeIntervalSince1970: 1),
        title: "Legacy package",
        state: .stopped
    )
    let segment = Segment(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!,
        meetingID: meeting.id,
        source: .selectedSource,
        startTime: 0,
        endTime: 1,
        language: .english,
        text: "A legacy source segment.",
        isFinal: true
    )
    try await store.create(meeting)

    let legacyGeneration = UUID(uuidString: "00000000-0000-0000-0000-000000000203")!
    let legacySnapshot = LegacyMeetingSnapshot(
        meeting: meeting,
        segments: [segment],
        gaps: [],
        translations: [],
        summary: nil
    )
    let legacyManifest = LegacyManifestTopology(
        version: 1,
        generation: legacyGeneration,
        meetingID: meeting.id,
        segmentIDs: [segment.id],
        gapIDs: [],
        translationIDs: [],
        hasSummary: false,
        retainsAudio: false
    )
    let key = try await keys.key(for: meeting.id, purpose: .text)
    let generationURL = root
        .appending(path: meeting.id.uuidString)
        .appending(path: legacyGeneration.uuidString)
    try FileManager.default.createDirectory(at: generationURL, withIntermediateDirectories: false)
    try sealForPackage(
        legacyManifest,
        key: key,
        context: packageAAD(meetingID: meeting.id, generation: legacyGeneration, file: "manifest")
    ).write(to: generationURL.appending(path: "manifest.knt"))
    try sealForPackage(
        legacySnapshot,
        key: key,
        context: packageAAD(meetingID: meeting.id, generation: legacyGeneration, file: "text")
    ).write(to: generationURL.appending(path: "text.knt"))
    await keys.setGeneration(legacyGeneration, for: meeting.id)

    #expect(try await store.snapshot(for: meeting.id).chatTurns.isEmpty)

    let turn = ChatTurnRecord(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000204")!,
        meetingID: meeting.id,
        createdAt: Date(timeIntervalSince1970: 2),
        responseLanguage: .english,
        question: "What source was preserved?",
        answer: "A legacy source segment.",
        outcome: .grounded,
        citations: [EvidenceReference(segmentID: segment.id, supportingText: segment.text)]
    )
    try await store.append(turn)
    let upgradedGeneration = try await keys.generation(for: meeting.id)
    let upgradedManifestData = try Data(contentsOf: root
        .appending(path: meeting.id.uuidString)
        .appending(path: upgradedGeneration.uuidString)
        .appending(path: "manifest.knt"))
    let upgradedBox = try AES.GCM.SealedBox(combined: upgradedManifestData)
    let upgradedManifest = try JSONDecoder().decode(
        ManifestTopology.self,
        from: AES.GCM.open(
            upgradedBox,
            using: key,
            authenticating: packageAAD(meetingID: meeting.id, generation: upgradedGeneration, file: "manifest")
        )
    )
    #expect(upgradedManifest.version == 2)
    #expect(try await store.snapshot(for: meeting.id).chatTurns == [turn])
}

@Test func chatTurnsRejectInvalidStateDuplicateAndCrossMeetingEvidence() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = MeetingPackageStore(rootURL: root, keys: MemoryMeetingKeyStore())
    let meeting = Meeting(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!,
        createdAt: Date(timeIntervalSince1970: 1),
        title: "Chat validation"
    )
    let segment = Segment(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000302")!,
        meetingID: meeting.id,
        source: .selectedSource,
        startTime: 0,
        endTime: 1,
        language: .english,
        text: "Release the build tomorrow.",
        isFinal: true
    )
    let validTurn = ChatTurnRecord(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000303")!,
        meetingID: meeting.id,
        createdAt: Date(timeIntervalSince1970: 2),
        responseLanguage: .english,
        question: "When is the release?",
        answer: "Release the build tomorrow.",
        outcome: .grounded,
        citations: [EvidenceReference(segmentID: segment.id, supportingText: segment.text)]
    )
    try await store.create(meeting)
    try await store.updateState(.recording, for: meeting.id)
    try await store.append(segment)

    do {
        try await store.append(validTurn)
        Issue.record("Active meeting accepted a chat turn")
    } catch let error as MeetingStoreError {
        #expect(error == .invalidState)
    }

    try await store.updateState(.stopped, for: meeting.id)
    let invalidEvidence = ChatTurnRecord(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000304")!,
        meetingID: meeting.id,
        createdAt: Date(timeIntervalSince1970: 3),
        responseLanguage: .english,
        question: "When is the release?",
        answer: "Release the build tomorrow.",
        outcome: .grounded,
        citations: [EvidenceReference(segmentID: segment.id, supportingText: "release the build tomorrow.")]
    )
    do {
        try await store.append(invalidEvidence)
        Issue.record("Non-literal chat evidence was accepted")
    } catch let error as MeetingStoreError {
        #expect(error == .corrupted)
    }
    let noRelevantEvidenceWithCitation = ChatTurnRecord(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000307")!,
        meetingID: meeting.id,
        createdAt: Date(timeIntervalSince1970: 3.5),
        responseLanguage: .english,
        question: "When is the release?",
        answer: "No grounded answer was found.",
        outcome: .noAnswer,
        noAnswerReason: .noRelevantEvidence,
        citations: [EvidenceReference(segmentID: segment.id, supportingText: segment.text)]
    )
    do {
        try await store.append(noRelevantEvidenceWithCitation)
        Issue.record("No-evidence chat turn accepted a transcript citation")
    } catch let error as MeetingStoreError {
        #expect(error == .corrupted)
    }

    try await store.append(validTurn)
    do {
        try await store.append(validTurn)
        Issue.record("Duplicate chat turn was accepted")
    } catch let error as MeetingStoreError {
        #expect(error == .duplicateRecord)
    }

    let otherMeeting = Meeting(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000305")!,
        createdAt: Date(timeIntervalSince1970: 4),
        title: "Other meeting",
        state: .stopped
    )
    try await store.create(otherMeeting)
    let crossMeetingTurn = ChatTurnRecord(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000306")!,
        meetingID: otherMeeting.id,
        createdAt: Date(timeIntervalSince1970: 5),
        responseLanguage: .english,
        question: "When is the release?",
        answer: "Release the build tomorrow.",
        outcome: .grounded,
        citations: [EvidenceReference(segmentID: segment.id, supportingText: segment.text)]
    )
    do {
        try await store.append(crossMeetingTurn)
        Issue.record("Cross-meeting chat evidence was accepted")
    } catch let error as MeetingStoreError {
        #expect(error == .corrupted)
    }
}

@Test func chatManifestTopologyMismatchesFailClosed() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let keys = MemoryMeetingKeyStore()
    let store = MeetingPackageStore(rootURL: root, keys: keys)
    let meeting = Meeting(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000401")!,
        createdAt: Date(timeIntervalSince1970: 1),
        title: "Topology validation"
    )
    let segment = Segment(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000402")!,
        meetingID: meeting.id,
        source: .selectedSource,
        startTime: 0,
        endTime: 1,
        language: .english,
        text: "The manifest lists exact turn order.",
        isFinal: true
    )
    let turn = ChatTurnRecord(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000403")!,
        meetingID: meeting.id,
        createdAt: Date(timeIntervalSince1970: 2),
        responseLanguage: .english,
        question: "What does the manifest list?",
        answer: "The manifest lists exact turn order.",
        outcome: .grounded,
        citations: [EvidenceReference(segmentID: segment.id, supportingText: segment.text)]
    )
    try await store.create(meeting)
    try await store.append(segment)
    try await store.updateState(.recording, for: meeting.id)
    try await store.updateState(.stopped, for: meeting.id)
    try await store.append(turn)

    let generation = try await keys.generation(for: meeting.id)
    let key = try await keys.key(for: meeting.id, purpose: .text)
    let malformedManifest = ManifestTopology(
        version: 2,
        generation: generation,
        meetingID: meeting.id,
        segmentIDs: [segment.id],
        gapIDs: [],
        translationIDs: [],
        chatTurnIDs: [],
        hasSummary: false,
        retainsAudio: false
    )
    let manifestURL = root
        .appending(path: meeting.id.uuidString)
        .appending(path: generation.uuidString)
        .appending(path: "manifest.knt")
    try sealForPackage(
        malformedManifest,
        key: key,
        context: packageAAD(meetingID: meeting.id, generation: generation, file: "manifest")
    ).write(to: manifestURL, options: .atomic)

    do {
        _ = try await store.snapshot(for: meeting.id)
        Issue.record("Manifest chat-turn topology mismatch was accepted")
    } catch let error as MeetingStoreError {
        #expect(error == .corrupted)
    }
}
