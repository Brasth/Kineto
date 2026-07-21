@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import Speech

public struct VolatileTranscript: Sendable, Equatable, Identifiable {
    public let id: String
    public let source: AudioSource
    public let text: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let language: SpokenLanguage

    public init(
        id: String,
        source: AudioSource,
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        language: SpokenLanguage
    ) {
        self.id = id
        self.source = source
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.language = language
    }

    public static func id(for source: AudioSource) -> String {
        "volatile-\(source.rawValue)"
    }
}
enum AppleSpeechStreamerError: Error {
    case unavailable
    case formatUnavailable
}

enum TranscriptText {
    static func isMeaningful(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }
}

private final class PCMBufferInput: @unchecked Sendable {
    private let lock = NSLock()
    private let buffer: AVAudioPCMBuffer
    private var supplied = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        lock.withLock {
            guard !supplied else {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
    }
}

/// One capture-track Apple SpeechAnalyzer session with volatile + final results.
actor AppleSpeechSourceSession {
    private let meetingID: UUID
    private let source: AudioSource
    private let language: SpokenLanguage
    private let localeIdentifier: String
    private let store: MeetingPackageStore
    private let output: AsyncStream<TranscriptEvent>.Continuation
    private let capability: AppleSpeechCapability

    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var analyzerFormat: AVAudioFormat?
    private var finished = false
    private var requiresRestart = false
    private var lastInputEndTime: TimeInterval = 0
    private var recoveryTimestamp: TimeInterval?

    enum InputOutcome {
        case accepted
        case discarded
        case requiresRestart(TimeInterval)
    }

    init(
        meetingID: UUID,
        source: AudioSource,
        language: SpokenLanguage,
        localeIdentifier: String,
        capability: AppleSpeechCapability,
        store: MeetingPackageStore,
        output: AsyncStream<TranscriptEvent>.Continuation
    ) {
        self.meetingID = meetingID
        self.source = source
        self.language = language
        self.localeIdentifier = localeIdentifier
        self.capability = capability
        self.store = store
        self.output = output
    }

    func start() async throws {
        guard SpeechTranscriber.isAvailable else { throw AppleSpeechStreamerError.unavailable }
        let transcriber = try await capability.makeTranscriber(localeIdentifier: localeIdentifier)

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw AppleSpeechStreamerError.formatUnavailable
        }
        analyzerFormat = format

        let analyzer = SpeechAnalyzer(
            modules: [transcriber],
            options: SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .whileInUse)
        )
        self.analyzer = analyzer
        try await analyzer.prepareToAnalyze(in: format)

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        input = continuation

        resultsTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await result in transcriber.results {
                    await self.handle(result)
                }
                await self.markForRestart()
            } catch is CancellationError {
                return
            } catch {
                await self.markForRestart()
            }
        }

        try await analyzer.start(inputSequence: stream)
    }

    func push(frame: AudioFrame) -> InputOutcome {
        guard !finished, !requiresRestart, let input, let analyzerFormat else {
            return .requiresRestart(recoveryTimestamp ?? frame.timestamp)
        }
        guard let buffer = makePCMBuffer(samples: frame.samples, format: analyzerFormat) else {
            return .discarded
        }
        let start = CMTime(seconds: max(0, frame.timestamp), preferredTimescale: 16_000)
        lastInputEndTime = frame.timestamp
            + TimeInterval(frame.samples.count) / AudioFrame.sampleRate
        input.yield(AnalyzerInput(buffer: buffer, bufferStartTime: start))
        return .accepted
    }

    func finish() async {
        guard !finished else { return }
        finished = true
        input?.finish()
        input = nil
        if let analyzer, !requiresRestart {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        await resultsTask?.value
        resultsTask = nil
        clearVolatile()
    }

    func cancel() async {
        finished = true
        input?.finish()
        input = nil
        resultsTask?.cancel()
        resultsTask = nil
        if let analyzer {
            await analyzer.cancelAndFinishNow()
        }
        clearVolatile()
    }

    func recoveryGap() -> CaptureGap? {
        guard requiresRestart else { return nil }
        return CaptureGap(
            source: source,
            timestamp: recoveryTimestamp ?? lastInputEndTime,
            reason: "speech-restarting"
        )
    }
    private func handle(_ result: SpeechTranscriber.Result) async {
        let text = String(result.text.characters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let start = max(0, CMTimeGetSeconds(result.range.start))
        let end = max(start, CMTimeGetSeconds(result.range.start + result.range.duration))

        guard TranscriptText.isMeaningful(text) else {
            if result.isFinal {
                clearVolatile(start: start, end: end)
            }
            return
        }
        if result.isFinal {
            let segment = Segment(
                meetingID: meetingID,
                source: source,
                speakerLabel: .default(for: source),
                startTime: start,
                endTime: end,
                language: language,
                text: text,
                isFinal: true
            )
            do {
                try await store.append(segment)
            } catch {
                output.yield(.failed("segment-persistence-failed"))
                return
            }
            output.yield(.finalized(segment))
            clearVolatile(start: start, end: end)
        } else {
            output.yield(
                .volatile(
                    VolatileTranscript(
                        id: VolatileTranscript.id(for: source),
                        source: source,
                        text: text,
                        startTime: start,
                        endTime: end,
                        language: language
                    )
                )
            )
        }
    }

    private func clearVolatile(start: TimeInterval = 0, end: TimeInterval = 0) {
        output.yield(
            .volatile(
                VolatileTranscript(
                    id: VolatileTranscript.id(for: source),
                    source: source,
                    text: "",
                    startTime: start,
                    endTime: end,
                    language: language
                )
            )
        )
    }

    private func markForRestart() {
        guard !finished, !requiresRestart else { return }
        requiresRestart = true
        recoveryTimestamp = lastInputEndTime > 0 ? lastInputEndTime : nil
        input?.finish()
        input = nil
        clearVolatile()
    }

    private func makePCMBuffer(samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if format.commonFormat == .pcmFormatFloat32,
           format.channelCount == 1,
           abs(format.sampleRate - AudioFrame.sampleRate) < 0.5
        {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
                return nil
            }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            if let channel = buffer.floatChannelData?[0] {
                samples.withUnsafeBufferPointer { src in
                    if let base = src.baseAddress {
                        channel.update(from: base, count: samples.count)
                    }
                }
            }
            return buffer
        }

        guard let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: AudioFrame.sampleRate,
            channels: 1,
            interleaved: false
        ),
            let converter = AVAudioConverter(from: sourceFormat, to: format),
            let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(samples.count))
        else {
            return nil
        }
        sourceBuffer.frameLength = AVAudioFrameCount(samples.count)
        if let channel = sourceBuffer.floatChannelData?[0] {
            samples.withUnsafeBufferPointer { src in
                if let base = src.baseAddress {
                    channel.update(from: base, count: samples.count)
                }
            }
        }

        let ratio = format.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(samples.count) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            return nil
        }
        let input = PCMBufferInput(buffer: sourceBuffer)
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            input.next(status: inputStatus)
        }
        guard error == nil, status != .error else { return nil }
        return out
    }
}

/// Multi-source Apple Speech pipeline over capture events.
public actor AppleSpeechMeetingPipeline {
    private let meetingID: UUID
    private let localeIdentifier: String
    private let language: SpokenLanguage
    private let store: MeetingPackageStore
    private let capability: AppleSpeechCapability
    private var sessions: [AudioSource: AppleSpeechSourceSession] = [:]
    private var consumer: Task<Void, Never>?
    private var output: AsyncStream<TranscriptEvent>.Continuation?
    private var cancelled = false
    private var nextStartAttempt: [AudioSource: TimeInterval] = [:]
    private var pendingRecoveryGaps: [AudioSource: CaptureGap] = [:]

    public init(
        meetingID: UUID,
        localeIdentifier: String,
        language: SpokenLanguage = .english,
        capability: AppleSpeechCapability,
        store: MeetingPackageStore
    ) {
        self.meetingID = meetingID
        self.localeIdentifier = localeIdentifier
        self.language = language
        self.capability = capability
        self.store = store
    }

    public func start(events: AsyncStream<CaptureEvent>) async throws -> AsyncStream<TranscriptEvent> {
        nextStartAttempt.removeAll()
        pendingRecoveryGaps.removeAll()
        let (stream, continuation) = AsyncStream<TranscriptEvent>.makeStream(bufferingPolicy: .unbounded)
        output = continuation
        cancelled = false

        consumer = Task { [weak self] in
            guard let self else { return }
            for await event in events {
                if Task.isCancelled { break }
                await self.handle(event)
            }
            await self.finishAll()
        }
        return stream
    }

    public func cancel() async {
        cancelled = true
        consumer?.cancel()
        consumer = nil
        for session in sessions.values {
            await session.cancel()
        }
        nextStartAttempt.removeAll()
        pendingRecoveryGaps.removeAll()
        sessions.removeAll()
        output?.finish()
        output = nil
    }

    private func handle(_ event: CaptureEvent) async {
        guard !cancelled, let output else { return }
        switch event {
        case let .audio(frame):
            if frame.timestamp < nextStartAttempt[frame.source, default: 0] {
                extendPendingRecoveryGap(with: frame)
                return
            }
            do {
                let session = try await session(for: frame.source)
                switch await session.push(frame: frame) {
                case .accepted:
                    await persistPendingRecoveryGap(for: frame.source)
                    nextStartAttempt[frame.source] = nil
                case .discarded:
                    await persistPendingRecoveryGap(for: frame.source)
                    await persistGap(
                        CaptureGap(
                            source: frame.source,
                            timestamp: frame.timestamp,
                            duration: frameDuration(for: frame),
                            reason: "audio-frame-discarded"
                        )
                    )
                case let .requiresRestart(timestamp):
                    await session.cancel()
                    sessions[frame.source] = nil
                    beginRecoveryGap(
                        source: frame.source,
                        timestamp: timestamp,
                        including: frame,
                        reason: "speech-restarting"
                    )
                    nextStartAttempt[frame.source] = frame.timestamp + 1
                }
            } catch {
                beginRecoveryGap(
                    source: frame.source,
                    timestamp: frame.timestamp,
                    including: frame,
                    reason: pendingRecoveryGaps[frame.source] == nil
                        ? "speech-start-failed"
                        : "speech-restarting"
                )
                nextStartAttempt[frame.source] = frame.timestamp + 1
            }
        case let .gap(gap):
            await persistGap(gap)
        case let .sourceLost(timestamp):
            await persistGap(
                CaptureGap(source: .selectedSource, timestamp: timestamp, reason: "source-lost")
            )
        case let .failed(reason):
            output.yield(.failed(reason))
        }
    }

    private func session(for source: AudioSource) async throws -> AppleSpeechSourceSession {
        if let existing = sessions[source] {
            return existing
        }
        guard let output else { throw AppleSpeechStreamerError.unavailable }
        let created = AppleSpeechSourceSession(
            meetingID: meetingID,
            source: source,
            language: language,
            localeIdentifier: localeIdentifier,
            capability: capability,
            store: store,
            output: output
        )
        try await created.start()
        sessions[source] = created
        return created
    }

    private func frameDuration(for frame: AudioFrame) -> TimeInterval {
        TimeInterval(frame.samples.count) / AudioFrame.sampleRate
    }

    private func beginRecoveryGap(
        source: AudioSource,
        timestamp: TimeInterval,
        including frame: AudioFrame,
        reason: String
    ) {
        if pendingRecoveryGaps[source] != nil {
            extendPendingRecoveryGap(with: frame)
            return
        }
        let end = max(timestamp, frame.timestamp + frameDuration(for: frame))
        pendingRecoveryGaps[source] = CaptureGap(
            source: source,
            timestamp: timestamp,
            duration: end - timestamp,
            reason: reason
        )
    }

    private func extendPendingRecoveryGap(with frame: AudioFrame) {
        guard let gap = pendingRecoveryGaps[frame.source] else { return }
        let end = max(gap.timestamp + gap.duration, frame.timestamp + frameDuration(for: frame))
        pendingRecoveryGaps[frame.source] = CaptureGap(
            source: gap.source,
            timestamp: gap.timestamp,
            duration: end - gap.timestamp,
            reason: gap.reason
        )
    }

    private func persistPendingRecoveryGap(for source: AudioSource) async {
        guard let gap = pendingRecoveryGaps.removeValue(forKey: source) else { return }
        await persistGap(gap)
    }

    private func persistGap(_ sourceGap: CaptureGap) async {
        guard let output else { return }
        let gap = TranscriptGap(
            meetingID: meetingID,
            source: sourceGap.source,
            timestamp: sourceGap.timestamp,
            duration: sourceGap.duration,
            reason: sourceGap.reason
        )
        do {
            try await store.append(gap)
            output.yield(.gap(gap))
        } catch {
            output.yield(.failed("gap-persistence-failed"))
        }
    }

    private func finishAll() async {
        for session in sessions.values {
            await session.finish()
            if let recoveryGap = await session.recoveryGap(),
               pendingRecoveryGaps[recoveryGap.source] == nil
            {
                pendingRecoveryGaps[recoveryGap.source] = recoveryGap
            }
        }
        sessions.removeAll()
        for source in Array(pendingRecoveryGaps.keys) {
            await persistPendingRecoveryGap(for: source)
        }
        nextStartAttempt.removeAll()
        output?.finish()
        output = nil
        consumer = nil
    }
}
