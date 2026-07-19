import CryptoKit
import Foundation
import Testing
@testable import KinetoCore

private actor CoordinatorKeyStore: MeetingKeyStore {
    private var keys: [String: SymmetricKey] = [:]
    private var generations: [UUID: UUID] = [:]

    func createKey(for meetingID: UUID, purpose: MeetingKeyPurpose) throws -> SymmetricKey {
        let value = SymmetricKey(size: .bits256)
        keys[id(meetingID, purpose)] = value
        return value
    }

    func key(for meetingID: UUID, purpose: MeetingKeyPurpose) throws -> SymmetricKey {
        guard let value = keys[id(meetingID, purpose)] else { throw MeetingKeyStoreError.missing }
        return value
    }

    func deleteKey(for meetingID: UUID, purpose: MeetingKeyPurpose) {
        keys[id(meetingID, purpose)] = nil
    }

    func deleteKeys(for meetingID: UUID) {
        keys[id(meetingID, .text)] = nil
        keys[id(meetingID, .audio)] = nil
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

    private func id(_ meetingID: UUID, _ purpose: MeetingKeyPurpose) -> String {
        "\(meetingID).\(purpose.rawValue)"
    }
}

private actor FixtureRecognizer: SpeechRecognizing {
    func transcribe(
        samples: [Float],
        sampleRate: Double,
        meetingID: UUID,
        source: AudioSource,
        startTime: TimeInterval
    ) async throws -> [Segment] {
        [Segment(
            meetingID: meetingID,
            source: source,
            speakerLabel: .default(for: source),
            startTime: startTime,
            endTime: startTime + Double(samples.count) / sampleRate,
            language: .english,
            text: "Final fixture",
            isFinal: true
        )]
    }
}

private actor RecordingRecognizer: SpeechRecognizing {
    private(set) var jobSampleCounts: [Int] = []
    private let delayNanoseconds: UInt64

    init(delayNanoseconds: UInt64 = 0) {
        self.delayNanoseconds = delayNanoseconds
    }

    func transcribe(
        samples: [Float],
        sampleRate: Double,
        meetingID: UUID,
        source: AudioSource,
        startTime: TimeInterval
    ) async throws -> [Segment] {
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        jobSampleCounts.append(samples.count)
        return [Segment(
            meetingID: meetingID,
            source: source,
            speakerLabel: .default(for: source),
            startTime: startTime,
            endTime: startTime + Double(samples.count) / sampleRate,
            language: .english,
            text: "job",
            isFinal: true
        )]
    }
}

@Test func transcriptCoordinatorFlushesFinalSegmentsAndPersistsGaps() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let meeting = Meeting(title: "Coordinator")
    let store = MeetingPackageStore(rootURL: root, keys: CoordinatorKeyStore())
    try await store.create(meeting)
    let coordinator = TranscriptCoordinator(
        meetingID: meeting.id,
        recognizer: FixtureRecognizer(),
        store: store,
        chunkDuration: 0.01,
        overlapDuration: 0
    )
    let (captureEvents, captureContinuation) = AsyncStream<CaptureEvent>.makeStream()
    let transcriptEvents = try await coordinator.start(events: captureEvents)

    captureContinuation.yield(.audio(AudioFrame(
        source: .selectedSource,
        timestamp: 2,
        samples: Array(repeating: 0.1, count: 160)
    )))
    captureContinuation.yield(.gap(CaptureGap(
        source: .you,
        timestamp: 2.1,
        reason: "fixture-gap"
    )))
    captureContinuation.finish()

    var finalized = 0
    var gaps = 0
    for await event in transcriptEvents {
        switch event {
        case .finalized:
            finalized += 1
        case .gap:
            gaps += 1
        case .timing, .volatile:
            break
        case .failed:
            Issue.record("Coordinator emitted failure")
        }
    }

    let snapshot = try await store.snapshot(for: meeting.id)
    #expect(finalized == 1)
    #expect(gaps == 1)
    #expect(snapshot.segments.count == 1)
    #expect(snapshot.gaps.count == 1)
    #expect(snapshot.gaps.first?.reason == "fixture-gap")
}

@Test func transcriptCoordinatorRecordsTimestampDiscontinuities() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let meeting = Meeting(title: "Discontinuity")
    let store = MeetingPackageStore(rootURL: root, keys: CoordinatorKeyStore())
    try await store.create(meeting)
    let coordinator = TranscriptCoordinator(
        meetingID: meeting.id,
        recognizer: FixtureRecognizer(),
        store: store,
        chunkDuration: 1
    )
    let (captureEvents, captureContinuation) = AsyncStream<CaptureEvent>.makeStream()
    let transcriptEvents = try await coordinator.start(events: captureEvents)

    captureContinuation.yield(.audio(AudioFrame(
        source: .selectedSource,
        timestamp: 2,
        samples: Array(repeating: 0.1, count: 160)
    )))
    captureContinuation.yield(.audio(AudioFrame(
        source: .selectedSource,
        timestamp: 2.02,
        samples: Array(repeating: 0.2, count: 160)
    )))
    captureContinuation.finish()

    for await event in transcriptEvents {
        if case .failed = event {
            Issue.record("Coordinator emitted failure")
        }
    }

    let snapshot = try await store.snapshot(for: meeting.id)
    #expect(snapshot.segments.count == 2)
    #expect(snapshot.gaps.count == 1)
    #expect(snapshot.gaps.first?.reason == "capture-discontinuity")
    #expect(snapshot.gaps.first?.timestamp == 2.01)
    #expect(abs((snapshot.gaps.first?.duration ?? 0) - 0.01) < 0.000_001)
}

@Test func transcriptCoordinatorFlushesEarlyAfterTrailingSilence() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let meeting = Meeting(title: "Silence flush")
    let store = MeetingPackageStore(rootURL: root, keys: CoordinatorKeyStore())
    try await store.create(meeting)
    let recognizer = RecordingRecognizer()
    let coordinator = TranscriptCoordinator(
        meetingID: meeting.id,
        recognizer: recognizer,
        store: store,
        chunkDuration: 2.0,
        minChunkDuration: 0.8,
        silenceDuration: 0.4,
        silenceRMSThreshold: 0.008,
        silenceRelativeFactor: 0.15
    )
    let (captureEvents, captureContinuation) = AsyncStream<CaptureEvent>.makeStream()
    let transcriptEvents = try await coordinator.start(events: captureEvents)

    // 1.0s speech + 0.45s quieter room tone → early flush before 2s max.
    let speechCount = 16_000
    let silenceCount = 7_200
    captureContinuation.yield(.audio(AudioFrame(
        source: .selectedSource,
        timestamp: 0,
        samples: Array(repeating: Float(0.2), count: speechCount)
    )))
    captureContinuation.yield(.audio(AudioFrame(
        source: .selectedSource,
        timestamp: Double(speechCount) / AudioFrame.sampleRate,
        samples: Array(repeating: Float(0.01), count: silenceCount)
    )))
    captureContinuation.finish()

    var finalized = 0
    for await event in transcriptEvents {
        if case .finalized = event {
            finalized += 1
        }
    }

    let snapshot = try await store.snapshot(for: meeting.id)
    let jobCounts = await recognizer.jobSampleCounts
    #expect(finalized == 1)
    #expect(snapshot.segments.count == 1)
    #expect(jobCounts.count == 1)
    #expect(jobCounts[0] == speechCount + silenceCount)
    #expect(jobCounts[0] < 32_000)
}

@Test func transcriptCoordinatorHoldsAudioInsteadOfBackpressureGaps() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let meeting = Meeting(title: "Hold buffer")
    let store = MeetingPackageStore(rootURL: root, keys: CoordinatorKeyStore())
    try await store.create(meeting)
    // Slow recognizer so queue fills while more audio arrives.
    let recognizer = RecordingRecognizer(delayNanoseconds: 30_000_000)
    let coordinator = TranscriptCoordinator(
        meetingID: meeting.id,
        recognizer: recognizer,
        store: store,
        chunkDuration: 0.2,
        minChunkDuration: 0.2,
        silenceDuration: 0.05,
        hardBufferDuration: 12.0,
        maximumQueuedJobsPerSource: 1,
        overlapDuration: 0
    )
    let (captureEvents, captureContinuation) = AsyncStream<CaptureEvent>.makeStream()
    let transcriptEvents = try await coordinator.start(events: captureEvents)

    // 1.0s continuous speech as five 0.2s frames → would have dropped under old drop-on-full queue.
    let frameCount = 3_200
    for index in 0..<5 {
        captureContinuation.yield(.audio(AudioFrame(
            source: .selectedSource,
            timestamp: Double(index * frameCount) / AudioFrame.sampleRate,
            samples: Array(repeating: Float(0.2), count: frameCount)
        )))
    }
    captureContinuation.finish()

    var gaps = 0
    var finalized = 0
    for await event in transcriptEvents {
        switch event {
        case .finalized:
            finalized += 1
        case .gap:
            gaps += 1
        case .timing, .volatile:
            break
        case .failed:
            Issue.record("Coordinator emitted failure")
        }
    }

    let snapshot = try await store.snapshot(for: meeting.id)
    let jobCounts = await recognizer.jobSampleCounts
    #expect(gaps == 0)
    #expect(snapshot.gaps.isEmpty)
    #expect(finalized >= 1)
    #expect(jobCounts.reduce(0, +) == frameCount * 5)
}

@Test func transcriptCoordinatorDoesNotSilenceFlushBeforeMinimum() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let meeting = Meeting(title: "Min chunk")
    let store = MeetingPackageStore(rootURL: root, keys: CoordinatorKeyStore())
    try await store.create(meeting)
    let recognizer = RecordingRecognizer()
    let coordinator = TranscriptCoordinator(
        meetingID: meeting.id,
        recognizer: recognizer,
        store: store,
        chunkDuration: 2.0,
        minChunkDuration: 0.8,
        silenceDuration: 0.4,
        silenceRMSThreshold: 0.008
    )
    let (captureEvents, captureContinuation) = AsyncStream<CaptureEvent>.makeStream()
    let transcriptEvents = try await coordinator.start(events: captureEvents)

    // 0.3s speech + 0.4s silence = 0.7s (< 0.8 min) then more speech.
    let preSpeech = 4_800
    let silence = 6_400
    let postSpeech = 4_800
    captureContinuation.yield(.audio(AudioFrame(
        source: .selectedSource,
        timestamp: 0,
        samples: Array(repeating: Float(0.2), count: preSpeech)
    )))
    captureContinuation.yield(.audio(AudioFrame(
        source: .selectedSource,
        timestamp: Double(preSpeech) / AudioFrame.sampleRate,
        samples: Array(repeating: Float(0), count: silence)
    )))
    captureContinuation.yield(.audio(AudioFrame(
        source: .selectedSource,
        timestamp: Double(preSpeech + silence) / AudioFrame.sampleRate,
        samples: Array(repeating: Float(0.2), count: postSpeech)
    )))
    captureContinuation.finish()

    for await _ in transcriptEvents {}

    let jobCounts = await recognizer.jobSampleCounts
    #expect(jobCounts == [preSpeech + silence + postSpeech])
}

private actor CountingRecognizer: SpeechRecognizing {
    private(set) var callCount = 0

    func transcribe(
        samples: [Float],
        sampleRate: Double,
        meetingID: UUID,
        source: AudioSource,
        startTime: TimeInterval
    ) async throws -> [Segment] {
        callCount += 1
        return [Segment(
            meetingID: meetingID,
            source: source,
            speakerLabel: .default(for: source),
            startTime: startTime,
            endTime: startTime + Double(samples.count) / sampleRate,
            language: .english,
            text: source == .you ? "you" : "selected",
            isFinal: true
        )]
    }
}

@Test func transcriptCoordinatorRoutesSourcesToSeparateRecognizers() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let meeting = Meeting(title: "Dual context")
    let store = MeetingPackageStore(rootURL: root, keys: CoordinatorKeyStore())
    try await store.create(meeting)
    let selected = CountingRecognizer()
    let you = CountingRecognizer()
    let coordinator = TranscriptCoordinator(
        meetingID: meeting.id,
        recognizers: SourceRecognizerMap(selectedSource: selected, you: you),
        store: store,
        chunkDuration: 0.05,
        minChunkDuration: 0.05,
        silenceDuration: 0.05,
        overlapDuration: 0
    )
    let (captureEvents, captureContinuation) = AsyncStream<CaptureEvent>.makeStream()
    let transcriptEvents = try await coordinator.start(events: captureEvents)

    let samples = Array(repeating: Float(0.2), count: 2_400)
    captureContinuation.yield(.audio(AudioFrame(
        source: .selectedSource,
        timestamp: 0,
        samples: samples
    )))
    captureContinuation.yield(.audio(AudioFrame(
        source: .you,
        timestamp: 0,
        samples: samples
    )))
    captureContinuation.finish()

    var texts: [String] = []
    for await event in transcriptEvents {
        if case let .finalized(segment) = event {
            texts.append(segment.text)
        }
    }
    #expect(await selected.callCount >= 1)
    #expect(await you.callCount >= 1)
    #expect(Set(texts) == Set(["selected", "you"]))
}

@Test func transcriptCoordinatorEmitsRecognitionTiming() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let meeting = Meeting(title: "Timing")
    let store = MeetingPackageStore(rootURL: root, keys: CoordinatorKeyStore())
    try await store.create(meeting)
    let coordinator = TranscriptCoordinator(
        meetingID: meeting.id,
        recognizer: FixtureRecognizer(),
        store: store,
        chunkDuration: 0.05,
        overlapDuration: 0
    )
    let (captureEvents, captureContinuation) = AsyncStream<CaptureEvent>.makeStream()
    let transcriptEvents = try await coordinator.start(events: captureEvents)

    captureContinuation.yield(.audio(AudioFrame(
        source: .selectedSource,
        timestamp: 0,
        samples: Array(repeating: 0.2, count: 1_600)
    )))
    captureContinuation.finish()

    var sawTiming = false
    for await event in transcriptEvents {
        if case let .timing(timing) = event {
            #expect(timing.audioDurationMs > 0)
            #expect(timing.inferenceMs >= 0)
            #expect(timing.storeMs >= 0)
            sawTiming = true
        }
    }
    #expect(sawTiming)
}
