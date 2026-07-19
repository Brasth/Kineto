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

/// One capture-track Apple SpeechAnalyzer session with volatile + final results.
actor AppleSpeechSourceSession {
    private let meetingID: UUID
    private let source: AudioSource
    private let language: SpokenLanguage
    private let localeIdentifier: String
    private let store: MeetingPackageStore
    private let output: AsyncStream<TranscriptEvent>.Continuation

    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var analyzerFormat: AVAudioFormat?
    private var finished = false

    init(
        meetingID: UUID,
        source: AudioSource,
        language: SpokenLanguage,
        localeIdentifier: String,
        store: MeetingPackageStore,
        output: AsyncStream<TranscriptEvent>.Continuation
    ) {
        self.meetingID = meetingID
        self.source = source
        self.language = language
        self.localeIdentifier = localeIdentifier
        self.store = store
        self.output = output
    }

    func start() async throws {
        guard SpeechTranscriber.isAvailable else { throw AppleSpeechStreamerError.unavailable }
        let capability = AppleSpeechCapability()
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
            } catch is CancellationError {
                return
            } catch {
                await self.emitFailed("apple-speech-results-failed")
            }
        }

        try await analyzer.start(inputSequence: stream)
    }

    func push(frame: AudioFrame) {
        guard !finished, let input, let analyzerFormat else { return }
        guard let buffer = makePCMBuffer(samples: frame.samples, format: analyzerFormat) else {
            return
        }
        let start = CMTime(seconds: max(0, frame.timestamp), preferredTimescale: 16_000)
        input.yield(AnalyzerInput(buffer: buffer, bufferStartTime: start))
    }

    func finish() async {
        guard !finished else { return }
        finished = true
        input?.finish()
        input = nil
        if let analyzer {
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

    private func handle(_ result: SpeechTranscriber.Result) async {
        let text = String(result.text.characters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || result.isFinal else { return }

        let start = max(0, CMTimeGetSeconds(result.range.start))
        let end = max(start, CMTimeGetSeconds(result.range.start + result.range.duration))

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

    private func emitFailed(_ reason: String) {
        output.yield(.failed(reason))
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
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return sourceBuffer
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
    private var sessions: [AudioSource: AppleSpeechSourceSession] = [:]
    private var consumer: Task<Void, Never>?
    private var output: AsyncStream<TranscriptEvent>.Continuation?
    private var cancelled = false

    public init(
        meetingID: UUID,
        localeIdentifier: String,
        language: SpokenLanguage = .english,
        store: MeetingPackageStore
    ) {
        self.meetingID = meetingID
        self.localeIdentifier = localeIdentifier
        self.language = language
        self.store = store
    }

    public func start(events: AsyncStream<CaptureEvent>) async throws -> AsyncStream<TranscriptEvent> {
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
        sessions.removeAll()
        output?.finish()
        output = nil
    }

    private func handle(_ event: CaptureEvent) async {
        guard !cancelled, let output else { return }
        switch event {
        case let .audio(frame):
            do {
                let session = try await session(for: frame.source)
                await session.push(frame: frame)
            } catch {
                output.yield(.failed("apple-speech-start-failed"))
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
            store: store,
            output: output
        )
        try await created.start()
        sessions[source] = created
        return created
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
        }
        sessions.removeAll()
        output?.finish()
        output = nil
        consumer = nil
    }
}
