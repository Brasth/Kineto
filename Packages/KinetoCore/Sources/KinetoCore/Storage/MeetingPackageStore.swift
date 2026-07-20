import CryptoKit
import Darwin
import Foundation

public enum MeetingStoreError: Error, Equatable {
    case alreadyExists
    case missing
    case invalidState
    case nonFinalSegment
    case duplicateRecord
    case corrupted
    case audioNotRetained
}

public struct MeetingSnapshot: Codable, Equatable, Sendable {
    public var meeting: Meeting
    public var segments: [Segment]
    public var gaps: [TranscriptGap]
    public var translations: [TranslationRecord]
    public var summary: SummaryRecord?
    public var chatTurns: [ChatTurnRecord]

    public init(
        meeting: Meeting,
        segments: [Segment] = [],
        gaps: [TranscriptGap] = [],
        translations: [TranslationRecord] = [],
        summary: SummaryRecord? = nil,
        chatTurns: [ChatTurnRecord] = []
    ) {
        self.meeting = meeting
        self.segments = segments
        self.gaps = gaps
        self.translations = translations
        self.summary = summary
        self.chatTurns = chatTurns
    }

    private enum CodingKeys: String, CodingKey {
        case meeting
        case segments
        case gaps
        case translations
        case summary
        case chatTurns
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        meeting = try values.decode(Meeting.self, forKey: .meeting)
        segments = try values.decode([Segment].self, forKey: .segments)
        gaps = try values.decode([TranscriptGap].self, forKey: .gaps)
        translations = try values.decode([TranslationRecord].self, forKey: .translations)
        summary = try values.decodeIfPresent(SummaryRecord.self, forKey: .summary)
        chatTurns = try values.decodeIfPresent([ChatTurnRecord].self, forKey: .chatTurns) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(meeting, forKey: .meeting)
        try values.encode(segments, forKey: .segments)
        try values.encode(gaps, forKey: .gaps)
        try values.encode(translations, forKey: .translations)
        try values.encodeIfPresent(summary, forKey: .summary)
        try values.encode(chatTurns, forKey: .chatTurns)
    }
}

public actor MeetingPackageStore {

    private struct Manifest: Codable {
        let version: Int
        let generation: UUID
        let meetingID: UUID
        let segmentIDs: [UUID]
        let gapIDs: [UUID]
        let translationIDs: [UUID]
        let chatTurnIDs: [UUID]
        let hasSummary: Bool
        let retainsAudio: Bool

        private enum CodingKeys: String, CodingKey {
            case version
            case generation
            case meetingID
            case segmentIDs
            case gapIDs
            case translationIDs
            case chatTurnIDs
            case hasSummary
            case retainsAudio
        }

        init(
            version: Int,
            generation: UUID,
            meetingID: UUID,
            segmentIDs: [UUID],
            gapIDs: [UUID],
            translationIDs: [UUID],
            chatTurnIDs: [UUID],
            hasSummary: Bool,
            retainsAudio: Bool
        ) {
            self.version = version
            self.generation = generation
            self.meetingID = meetingID
            self.segmentIDs = segmentIDs
            self.gapIDs = gapIDs
            self.translationIDs = translationIDs
            self.chatTurnIDs = chatTurnIDs
            self.hasSummary = hasSummary
            self.retainsAudio = retainsAudio
        }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            version = try values.decode(Int.self, forKey: .version)
            generation = try values.decode(UUID.self, forKey: .generation)
            meetingID = try values.decode(UUID.self, forKey: .meetingID)
            segmentIDs = try values.decode([UUID].self, forKey: .segmentIDs)
            gapIDs = try values.decode([UUID].self, forKey: .gapIDs)
            translationIDs = try values.decode([UUID].self, forKey: .translationIDs)
            chatTurnIDs = version == 1
                ? []
                : try values.decode([UUID].self, forKey: .chatTurnIDs)
            hasSummary = try values.decode(Bool.self, forKey: .hasSummary)
            retainsAudio = try values.decode(Bool.self, forKey: .retainsAudio)
        }
    }

    private struct TranscriptExport: Encodable {
        let meeting: Meeting
        let segments: [Segment]
        let gaps: [TranscriptGap]
        let translations: [TranslationRecord]
        let summary: SummaryRecord?
        let chatTurns: [ChatTurnRecord]

        init(_ snapshot: MeetingSnapshot) {
            meeting = snapshot.meeting
            segments = snapshot.segments
            gaps = snapshot.gaps
            translations = snapshot.translations
            summary = snapshot.summary
            chatTurns = snapshot.chatTurns
        }
    }

    private let rootURL: URL
    private let keys: any MeetingKeyStore
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let mutationMutex = AsyncMutex()

    public init(
        rootURL: URL,
        keys: any MeetingKeyStore = KeychainMeetingKeyStore(),
        fileManager: FileManager = .default
    ) {
        self.rootURL = rootURL
        self.keys = keys
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public func create(_ meeting: Meeting) async throws {
        let packageURL = packageURL(for: meeting.id)
        guard !fileManager.fileExists(atPath: packageURL.path) else {
            throw MeetingStoreError.alreadyExists
        }
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let stageURL = rootURL.appending(
            path: ".create-\(meeting.id.uuidString)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )

        var published = false
        do {
            try fileManager.createDirectory(at: stageURL, withIntermediateDirectories: false)
            _ = try await keys.createKey(for: meeting.id, purpose: .text)
            if meeting.retainsAudio {
                _ = try await keys.createKey(for: meeting.id, purpose: .audio)
            }
            try await commit(MeetingSnapshot(meeting: meeting), packageURL: stageURL)
            try fileManager.moveItem(at: stageURL, to: packageURL)
            published = true
            try syncDirectory(rootURL)
        } catch {
            if !published {
                try? await keys.deleteKeys(for: meeting.id)
                try? fileManager.removeItem(at: stageURL)
            }
            throw error
        }
    }

    public func meetingIDs() throws -> [UUID] {
        guard fileManager.fileExists(atPath: rootURL.path) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .compactMap { URL -> UUID? in
            guard let id = UUID(uuidString: URL.lastPathComponent),
                  !fileManager.fileExists(atPath: tombstoneURL(for: id).path) else {
                return nil
            }
            return id
        }
    }

    public func snapshot(for meetingID: UUID) async throws -> MeetingSnapshot {
        let generation = try await currentGeneration(for: meetingID)
        let key = try await keys.key(for: meetingID, purpose: .text)
        let generationURL = packageURL(for: meetingID).appending(path: generation.uuidString)

        let manifestData = try Data(contentsOf: generationURL.appending(path: "manifest.knt"))
        let payloadData = try Data(contentsOf: generationURL.appending(path: "text.knt"))
        let manifest = try decrypt(
            Manifest.self,
            data: manifestData,
            key: key,
            context: context(meetingID: meetingID, generation: generation, file: "manifest")
        )
        let snapshot = try decrypt(
            MeetingSnapshot.self,
            data: payloadData,
            key: key,
            context: context(meetingID: meetingID, generation: generation, file: "text")
        )
        try validate(manifest: manifest, snapshot: snapshot, meetingID: meetingID, generation: generation)
        return snapshot
    }

    public func updateState(_ state: MeetingState, for meetingID: UUID) async throws {
        try await mutationMutex.withLock {
            try await self.updateStateUnlocked(state, for: meetingID)
        }
    }

    public func append(_ segment: Segment) async throws {
        try await append(segments: [segment])
    }

    /// Append one or more finalized segments in a single generation commit (L1).
    public func append(segments: [Segment]) async throws {
        guard !segments.isEmpty else { return }
        try await mutationMutex.withLock {
            try await self.appendSegmentsUnlocked(segments)
        }
    }

    public func append(_ gap: TranscriptGap) async throws {
        try await mutationMutex.withLock {
            try await self.appendGapUnlocked(gap)
        }
    }

    public func append(_ translation: TranslationRecord, meetingID: UUID) async throws {
        try await mutationMutex.withLock {
            try await self.appendTranslationUnlocked(translation, meetingID: meetingID)
        }
    }

    public func append(_ chatTurn: ChatTurnRecord) async throws {
        try await mutationMutex.withLock {
            try await self.appendChatTurnUnlocked(chatTurn)
        }
    }

    public func save(_ summary: SummaryRecord) async throws {
        try await mutationMutex.withLock {
            try await self.saveSummaryUnlocked(summary)
        }
    }


    private func updateStateUnlocked(_ state: MeetingState, for meetingID: UUID) async throws {
        try ensureNotDeleting(meetingID)
        var value = try await snapshot(for: meetingID)
        guard isValidTransition(from: value.meeting.state, to: state) else {
            throw MeetingStoreError.invalidState
        }
        value.meeting.state = state
        try await commit(value)
    }

    private func appendSegmentsUnlocked(_ segments: [Segment]) async throws {
        let meetingID = segments[0].meetingID
        try ensureNotDeleting(meetingID)
        var value = try await snapshot(for: meetingID)
        guard value.meeting.state != .stopped else {
            throw MeetingStoreError.invalidState
        }
        for segment in segments {
            guard segment.meetingID == meetingID else {
                throw MeetingStoreError.corrupted
            }
            guard segment.isFinal else {
                throw MeetingStoreError.nonFinalSegment
            }
            guard !value.segments.contains(where: { $0.id == segment.id }) else {
                throw MeetingStoreError.duplicateRecord
            }
            value.segments.append(segment)
        }
        try await commit(value)
    }

    private func appendGapUnlocked(_ gap: TranscriptGap) async throws {
        try ensureNotDeleting(gap.meetingID)
        var value = try await snapshot(for: gap.meetingID)
        guard value.meeting.state != .stopped else {
            throw MeetingStoreError.invalidState
        }
        guard !value.gaps.contains(where: { $0.id == gap.id }) else {
            throw MeetingStoreError.duplicateRecord
        }
        value.gaps.append(gap)
        try await commit(value)
    }

    private func appendTranslationUnlocked(
        _ translation: TranslationRecord,
        meetingID: UUID
    ) async throws {
        try ensureNotDeleting(meetingID)
        var value = try await snapshot(for: meetingID)
        // Source sealing rejects segments/gaps after stop; derived translations may finish after seal.
        guard value.meeting.state == .recording
            || value.meeting.state == .paused
            || value.meeting.state == .stopped else {
            throw MeetingStoreError.invalidState
        }
        guard value.segments.contains(where: { $0.id == translation.sourceSegmentID }) else {
            throw MeetingStoreError.corrupted
        }
        guard !value.translations.contains(where: {
            $0.sourceSegmentID == translation.sourceSegmentID &&
            $0.targetLanguage == translation.targetLanguage
        }) else {
            // Idempotent completion after stop/relaunch.
            return
        }
        value.translations.append(translation)
        try await commit(value)
    }

    private func appendChatTurnUnlocked(_ chatTurn: ChatTurnRecord) async throws {
        try ensureNotDeleting(chatTurn.meetingID)
        var value = try await snapshot(for: chatTurn.meetingID)
        guard value.meeting.state == .stopped,
              chatTurn.meetingID == value.meeting.id else {
            throw MeetingStoreError.invalidState
        }
        guard !value.chatTurns.contains(where: { $0.id == chatTurn.id }) else {
            throw MeetingStoreError.duplicateRecord
        }
        try validate(chatTurn: chatTurn, in: value)
        value.chatTurns.append(chatTurn)
        try await commit(value)
    }

    private func saveSummaryUnlocked(_ summary: SummaryRecord) async throws {
        try ensureNotDeleting(summary.meetingID)
        var value = try await snapshot(for: summary.meetingID)
        guard value.meeting.state == .stopped else {
            throw MeetingStoreError.invalidState
        }
        value.summary = summary
        try await commit(value)
    }

    public func deleteRetainedAudio(for meetingID: UUID) async throws {
        let value = try await snapshot(for: meetingID)
        guard value.meeting.retainsAudio else {
            throw MeetingStoreError.audioNotRetained
        }
        try await keys.deleteKey(for: meetingID, purpose: .audio)
        let audioURL = packageURL(for: meetingID).appending(path: "audio")
        if fileManager.fileExists(atPath: audioURL.path) {
            try fileManager.removeItem(at: audioURL)
        }
    }

    public func export(meetingID: UUID, to destination: URL) async throws {
        let value = try await snapshot(for: meetingID)
        let data = try encoder.encode(TranscriptExport(value))
        try data.write(to: destination, options: [.atomic, .completeFileProtection])
    }

    public func delete(meetingID: UUID) async throws {
        try await mutationMutex.withLock {
            try await self.deleteUnlocked(meetingID: meetingID)
        }
    }

    private func deleteUnlocked(meetingID: UUID) async throws {
        let packageURL = packageURL(for: meetingID)
        guard fileManager.fileExists(atPath: packageURL.path) else {
            throw MeetingStoreError.missing
        }
        let tombstoneURL = tombstoneURL(for: meetingID)
        if !fileManager.fileExists(atPath: tombstoneURL.path) {
            try writeDurably(Data(meetingID.uuidString.utf8), to: tombstoneURL)
            try syncDirectory(rootURL)
        }
        try await finishDeletion(meetingID: meetingID)
    }

    public func recoverInterruptedDeletions() async throws {
        guard fileManager.fileExists(atPath: rootURL.path) else { return }
        let tombstones = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: []
        ).filter { $0.lastPathComponent.hasPrefix(".deleted-") }
        for tombstone in tombstones {
            let rawID = String(tombstone.lastPathComponent.dropFirst(".deleted-".count))
            guard let meetingID = UUID(uuidString: rawID) else { continue }
            try await mutationMutex.withLock {
                try await self.finishDeletion(meetingID: meetingID)
            }
        }
        let abandonedCreations = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: []
        ).filter { $0.lastPathComponent.hasPrefix(".create-") }
        for stageURL in abandonedCreations {
            let raw = String(stageURL.lastPathComponent.dropFirst(".create-".count))
            guard raw.count >= 36,
                  let meetingID = UUID(uuidString: String(raw.prefix(36))) else {
                continue
            }
            try await keys.deleteKeys(for: meetingID)
            try fileManager.removeItem(at: stageURL)
            try syncDirectory(rootURL)
        }
        for meetingID in try meetingIDs() {
            try await mutationMutex.withLock {
                try await self.recoverInterruptedCommitArtifacts(for: meetingID)
                try await self.removeRetiredPackageArtifacts(for: meetingID)
            }
        }
    }

    private func recoverInterruptedCommitArtifacts(for meetingID: UUID) async throws {
        let packageURL = packageURL(for: meetingID)
        let stages = try fileManager.contentsOfDirectory(
            at: packageURL,
            includingPropertiesForKeys: nil,
            options: []
        ).filter { $0.lastPathComponent.hasPrefix(".stage-") }
        for stageURL in stages {
            try fileManager.removeItem(at: stageURL)
        }
        if !stages.isEmpty {
            try syncDirectory(packageURL)
        }
    }

    private func removeRetiredPackageArtifacts(for meetingID: UUID) async throws {
        let packageURL = packageURL(for: meetingID)
        let retiredArtifactsURL = packageURL.appending(path: "attachments", directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: retiredArtifactsURL.path) {
            try fileManager.removeItem(at: retiredArtifactsURL)
            try syncDirectory(packageURL)
        }
        try await keys.removeRetiredKeyMaterial(for: meetingID)
    }
    private func finishDeletion(meetingID: UUID) async throws {
        try await keys.deleteKeys(for: meetingID)
        let packageURL = packageURL(for: meetingID)
        if fileManager.fileExists(atPath: packageURL.path) {
            try fileManager.removeItem(at: packageURL)
            try syncDirectory(rootURL)
        }
        let tombstoneURL = tombstoneURL(for: meetingID)
        if fileManager.fileExists(atPath: tombstoneURL.path) {
            try fileManager.removeItem(at: tombstoneURL)
            try syncDirectory(rootURL)
        }
    }

    private func commit(_ snapshot: MeetingSnapshot, packageURL suppliedPackageURL: URL? = nil) async throws {
        let meetingID = snapshot.meeting.id
        let generation = UUID()
        let packageURL = suppliedPackageURL ?? packageURL(for: meetingID)
        let stageURL = packageURL.appending(path: ".stage-\(generation.uuidString)")
        let generationURL = packageURL.appending(path: generation.uuidString)
        let key = try await keys.key(for: meetingID, purpose: .text)
        let manifest = Manifest(
            version: 3,
            generation: generation,
            meetingID: meetingID,
            segmentIDs: snapshot.segments.map(\.id),
            gapIDs: snapshot.gaps.map(\.id),
            translationIDs: snapshot.translations.map(\.id),
            chatTurnIDs: snapshot.chatTurns.map(\.id),
            hasSummary: snapshot.summary != nil,
            retainsAudio: snapshot.meeting.retainsAudio
        )

        do {
            try fileManager.createDirectory(at: stageURL, withIntermediateDirectories: false)
            try writeDurably(
                try encrypt(manifest, key: key, context: context(meetingID: meetingID, generation: generation, file: "manifest")),
                to: stageURL.appending(path: "manifest.knt")
            )
            try writeDurably(
                try encrypt(snapshot, key: key, context: context(meetingID: meetingID, generation: generation, file: "text")),
                to: stageURL.appending(path: "text.knt")
            )
            try syncDirectory(stageURL)
            try fileManager.moveItem(at: stageURL, to: generationURL)
            try syncDirectory(packageURL)
            try replaceCurrentPointer(generation: generation, packageURL: packageURL)
            try syncDirectory(packageURL)
            try await keys.setGeneration(generation, for: meetingID)
        } catch {
            try? fileManager.removeItem(at: stageURL)
            throw error
        }
    }

    private func validate(
        manifest: Manifest,
        snapshot: MeetingSnapshot,
        meetingID: UUID,
        generation: UUID
    ) throws {
        guard (1...3).contains(manifest.version),
              manifest.generation == generation,
              manifest.meetingID == meetingID,
              snapshot.meeting.id == meetingID,
              manifest.segmentIDs == snapshot.segments.map(\.id),
              manifest.gapIDs == snapshot.gaps.map(\.id),
              manifest.translationIDs == snapshot.translations.map(\.id),
              manifest.chatTurnIDs == snapshot.chatTurns.map(\.id),
              manifest.hasSummary == (snapshot.summary != nil),
              manifest.retainsAudio == snapshot.meeting.retainsAudio,
              snapshot.segments.allSatisfy(\.isFinal),
              Set(manifest.segmentIDs).count == manifest.segmentIDs.count,
              Set(manifest.gapIDs).count == manifest.gapIDs.count,
              Set(manifest.translationIDs).count == manifest.translationIDs.count,
              Set(manifest.chatTurnIDs).count == manifest.chatTurnIDs.count,
              snapshot.translations.allSatisfy({ translation in
                  manifest.segmentIDs.contains(translation.sourceSegmentID)
              }) else {
            throw MeetingStoreError.corrupted
        }
        for chatTurn in snapshot.chatTurns {
            try validate(chatTurn: chatTurn, in: snapshot)
        }
    }


    private func validate(chatTurn: ChatTurnRecord, in snapshot: MeetingSnapshot) throws {
        guard chatTurn.meetingID == snapshot.meeting.id,
              !chatTurn.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !chatTurn.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MeetingStoreError.corrupted
        }

        switch chatTurn.outcome {
        case .grounded:
            guard chatTurn.noAnswerReason == nil, !chatTurn.citations.isEmpty else {
                throw MeetingStoreError.corrupted
            }
        case .noAnswer:
            guard let reason = chatTurn.noAnswerReason else {
                throw MeetingStoreError.corrupted
            }
            if reason == .noRelevantEvidence {
                guard chatTurn.citations.isEmpty else {
                    throw MeetingStoreError.corrupted
                }
            } else {
                guard !chatTurn.citations.isEmpty else {
                    throw MeetingStoreError.corrupted
                }
            }
        }

        for citation in chatTurn.citations {
            let quote = citation.supportingText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !quote.isEmpty,
                  let segment = snapshot.segments.first(where: { $0.id == citation.segmentID }),
                  segment.meetingID == chatTurn.meetingID,
                  segment.isFinal,
                  segment.text.range(of: quote) != nil else {
                throw MeetingStoreError.corrupted
            }
        }
    }

    private func isValidTransition(from: MeetingState, to: MeetingState) -> Bool {
        switch (from, to) {
        case (.ready, .recording), (.recording, .paused), (.paused, .recording),
             (.recording, .stopped), (.paused, .stopped):
            true
        default:
            false
        }
    }

    private func ensureNotDeleting(_ meetingID: UUID) throws {
        guard !fileManager.fileExists(atPath: tombstoneURL(for: meetingID).path) else {
            throw MeetingStoreError.missing
        }
    }

    private func currentGeneration(for meetingID: UUID) async throws -> UUID {
        let generation = try await keys.generation(for: meetingID)
        let generationURL = packageURL(for: meetingID).appending(path: generation.uuidString)
        guard fileManager.fileExists(atPath: generationURL.path) else {
            throw MeetingStoreError.corrupted
        }
        return generation
    }

    private func replaceCurrentPointer(generation: UUID, packageURL: URL) throws {
        let currentURL = packageURL.appending(path: "current")
        let temporaryURL = packageURL.appending(path: ".current-\(generation.uuidString)")
        try writeDurably(Data(generation.uuidString.utf8), to: temporaryURL)
        if fileManager.fileExists(atPath: currentURL.path) {
            _ = try fileManager.replaceItemAt(currentURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: currentURL)
        }
    }

    private func encrypt<T: Encodable>(_ value: T, key: SymmetricKey, context: Data) throws -> Data {
        let plaintext = try encoder.encode(value)
        guard let combined = try AES.GCM.seal(plaintext, using: key, authenticating: context).combined else {
            throw MeetingStoreError.corrupted
        }
        return combined
    }

    private func decrypt<T: Decodable>(
        _ type: T.Type,
        data: Data,
        key: SymmetricKey,
        context: Data
    ) throws -> T {
        do {
            let box = try AES.GCM.SealedBox(combined: data)
            let plaintext = try AES.GCM.open(box, using: key, authenticating: context)
            return try decoder.decode(type, from: plaintext)
        } catch {
            throw MeetingStoreError.corrupted
        }
    }

    private func context(meetingID: UUID, generation: UUID, file: String) -> Data {
        Data("kineto/v1/\(meetingID.uuidString)/\(generation.uuidString)/\(file)".utf8)
    }


    private func packageURL(for meetingID: UUID) -> URL {
        rootURL.appending(path: meetingID.uuidString, directoryHint: .isDirectory)
    }

    private func tombstoneURL(for meetingID: UUID) -> URL {
        rootURL.appending(path: ".deleted-\(meetingID.uuidString)")
    }

    private func writeDurably(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .withoutOverwriting)
        let handle = try FileHandle(forWritingTo: url)
        try handle.synchronize()
        try handle.close()
    }

    private func syncDirectory(_ url: URL) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY)
        guard descriptor >= 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
