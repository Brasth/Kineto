import Foundation

public enum TranscriptEvent: Sendable {
    case finalized(Segment)
    /// Live partial caption (UI only; never durable).
    case volatile(VolatileTranscript)
    /// Live pipeline stage timings for L0 diagnostics.
    case timing(RecognitionTiming)
    case gap(TranscriptGap)
    case failed(String)
}

public actor TranscriptCoordinator {
    private struct SourceBuffer {
        var samples: [Float] = []
        var startTime: TimeInterval?
    }

    private struct RecognitionJob: Sendable {
        let source: AudioSource
        let startTime: TimeInterval
        let samples: [Float]
        let enqueuedAt: ContinuousClock.Instant
    }

    private let meetingID: UUID
    private let recognizers: SourceRecognizerMap
    private let store: MeetingPackageStore
    private let maxChunkSampleCount: Int
    private let minChunkSampleCount: Int
    private let silenceSampleCount: Int
    private let silenceRMSThreshold: Float
    private let silenceRelativeFactor: Float
    private let hardBufferSampleCount: Int
    private let maximumQueuedJobsPerSource: Int
    /// Samples retained at the end of a max-chunk cut so the next job has boundary context (L1).
    private let overlapSampleCount: Int

    private var buffers: [AudioSource: SourceBuffer] = [:]
    private var queuedJobs: [AudioSource: [RecognitionJob]] = [:]
    private var inFlight: Set<AudioSource> = []
    private var recognitionTasks: [AudioSource: Task<Void, Never>] = [:]
    private var captureEnded = false
    private var cancelled = false
    private var output: AsyncStream<TranscriptEvent>.Continuation?
    private var consumer: Task<Void, Never>?

    public init(
        meetingID: UUID,
        recognizer: any SpeechRecognizing,
        store: MeetingPackageStore,
        chunkDuration: TimeInterval = 2.0,
        minChunkDuration: TimeInterval = 0.8,
        silenceDuration: TimeInterval = 0.4,
        silenceRMSThreshold: Float = 0.008,
        silenceRelativeFactor: Float = 0.15,
        hardBufferDuration: TimeInterval = 12.0,
        maximumQueuedJobsPerSource: Int = 4,
        overlapDuration: TimeInterval = 0.5
    ) {
        self.init(
            meetingID: meetingID,
            recognizers: SourceRecognizerMap(shared: recognizer),
            store: store,
            chunkDuration: chunkDuration,
            minChunkDuration: minChunkDuration,
            silenceDuration: silenceDuration,
            silenceRMSThreshold: silenceRMSThreshold,
            silenceRelativeFactor: silenceRelativeFactor,
            hardBufferDuration: hardBufferDuration,
            maximumQueuedJobsPerSource: maximumQueuedJobsPerSource,
            overlapDuration: overlapDuration
        )
    }

    public init(
        meetingID: UUID,
        recognizers: SourceRecognizerMap,
        store: MeetingPackageStore,
        chunkDuration: TimeInterval = 2.0,
        minChunkDuration: TimeInterval = 0.8,
        silenceDuration: TimeInterval = 0.4,
        silenceRMSThreshold: Float = 0.008,
        silenceRelativeFactor: Float = 0.15,
        hardBufferDuration: TimeInterval = 12.0,
        maximumQueuedJobsPerSource: Int = 4,
        overlapDuration: TimeInterval = 0.5
    ) {
        self.meetingID = meetingID
        self.recognizers = recognizers
        self.store = store
        let maxCount = max(1, Int((chunkDuration * AudioFrame.sampleRate).rounded(.down)))
        let minCount = max(1, Int((minChunkDuration * AudioFrame.sampleRate).rounded(.down)))
        self.maxChunkSampleCount = maxCount
        self.minChunkSampleCount = min(maxCount, minCount)
        self.silenceSampleCount = max(1, Int((silenceDuration * AudioFrame.sampleRate).rounded(.down)))
        self.silenceRMSThreshold = max(0, silenceRMSThreshold)
        self.silenceRelativeFactor = min(1, max(0.01, silenceRelativeFactor))
        self.hardBufferSampleCount = max(
            maxCount * 2,
            Int((hardBufferDuration * AudioFrame.sampleRate).rounded(.down))
        )
        self.maximumQueuedJobsPerSource = max(1, maximumQueuedJobsPerSource)
        let overlap = max(0, Int((overlapDuration * AudioFrame.sampleRate).rounded(.down)))
        // Never retain more than 25% of a max chunk as overlap.
        self.overlapSampleCount = min(overlap, max(0, maxCount / 4))
    }

    public func start(events: AsyncStream<CaptureEvent>) throws -> AsyncStream<TranscriptEvent> {
        guard consumer == nil else { throw MeetingCaptureError.alreadyRunning }
        let (stream, continuation) = AsyncStream<TranscriptEvent>.makeStream(bufferingPolicy: .unbounded)
        output = continuation
        captureEnded = false
        cancelled = false
        consumer = Task { [weak self] in
            guard let self else { return }
            for await event in events {
                if Task.isCancelled { break }
                await self.consume(event)
            }
            await self.captureDidEnd()
        }
        return stream
    }

    public func cancel() async {
        cancelled = true
        consumer?.cancel()
        consumer = nil
        let tasks = Array(recognitionTasks.values)
        tasks.forEach { $0.cancel() }
        for task in tasks {
            await task.value
        }
        recognitionTasks.removeAll(keepingCapacity: false)
        inFlight.removeAll(keepingCapacity: false)
        queuedJobs.removeAll(keepingCapacity: false)
        buffers.removeAll(keepingCapacity: false)
        output?.finish()
        output = nil
    }

    private func consume(_ event: CaptureEvent) async {
        guard !cancelled else { return }
        switch event {
        case let .audio(frame):
            await enqueue(frame)
        case let .gap(gap):
            await recordGap(gap)
        case let .sourceLost(timestamp):
            await recordGap(
                CaptureGap(
                    source: .selectedSource,
                    timestamp: timestamp,
                    reason: "source-lost"
                )
            )
        case let .failed(reason):
            output?.yield(.failed(reason))
        }
    }

    private func enqueue(_ frame: AudioFrame) async {
        var buffer = buffers[frame.source, default: SourceBuffer()]
        if let startTime = buffer.startTime, !buffer.samples.isEmpty {
            let expectedTimestamp = startTime
                + TimeInterval(buffer.samples.count) / AudioFrame.sampleRate
            let missingDuration = frame.timestamp - expectedTimestamp
            if missingDuration > (1 / AudioFrame.sampleRate) {
                if hasQueueCapacity(for: frame.source) {
                    cutJob(source: frame.source, sampleCount: buffer.samples.count, retainOverlap: false)
                }
                await persistGap(CaptureGap(
                    source: frame.source,
                    timestamp: expectedTimestamp,
                    duration: missingDuration,
                    reason: "capture-discontinuity"
                ))
                buffer = buffers[frame.source, default: SourceBuffer()]
            }
        }
        if buffer.samples.isEmpty {
            buffer.startTime = frame.timestamp
        }
        buffer.samples.append(contentsOf: frame.samples)
        buffers[frame.source] = buffer
        await drainSource(frame.source)
    }

    private func drainSource(_ source: AudioSource) async {
        while let current = buffers[source], !current.samples.isEmpty {
            if hasQueueCapacity(for: source) {
                if current.samples.count >= maxChunkSampleCount {
                    cutJob(source: source, sampleCount: maxChunkSampleCount, retainOverlap: true)
                    continue
                }
                if current.samples.count >= minChunkSampleCount,
                   shouldFlushOnTrailingSilence(current.samples)
                {
                    cutJob(source: source, sampleCount: current.samples.count, retainOverlap: false)
                    continue
                }
                if captureEnded {
                    cutJob(source: source, sampleCount: current.samples.count, retainOverlap: false)
                    continue
                }
                break
            }

            if current.samples.count >= hardBufferSampleCount {
                await dropOldestChunkAsBackpressureGap(source: source)
                continue
            }
            break
        }
        scheduleIfPossible(source: source)
    }

    private func hasQueueCapacity(for source: AudioSource) -> Bool {
        queuedJobs[source, default: []].count < maximumQueuedJobsPerSource
    }

    private func shouldFlushOnTrailingSilence(_ samples: [Float]) -> Bool {
        guard samples.count >= minChunkSampleCount,
              samples.count >= silenceSampleCount
        else {
            return false
        }
        let tail = samples.suffix(silenceSampleCount)
        let speech = samples.dropLast(silenceSampleCount)
        guard !speech.isEmpty else { return false }

        let speechRMS = rms(speech)
        guard speechRMS >= silenceRMSThreshold else { return false }

        let tailRMS = rms(tail)
        let relativeCutoff = max(silenceRMSThreshold, speechRMS * silenceRelativeFactor)
        return tailRMS < relativeCutoff
    }

    private func rms<S: Sequence>(_ samples: S) -> Float where S.Element == Float {
        var sum: Float = 0
        var count = 0
        for sample in samples {
            sum += sample * sample
            count += 1
        }
        guard count > 0 else { return 0 }
        return sqrt(sum / Float(count))
    }

    private func cutJob(source: AudioSource, sampleCount: Int, retainOverlap: Bool) {
        guard var buffer = buffers[source], !buffer.samples.isEmpty else { return }
        guard hasQueueCapacity(for: source) else { return }

        let count = min(sampleCount, buffer.samples.count)
        let startTime = buffer.startTime ?? 0
        let jobSamples = Array(buffer.samples.prefix(count))
        let retain: Int = {
            guard retainOverlap, overlapSampleCount > 0 else { return 0 }
            return min(overlapSampleCount, max(0, count / 2))
        }()
        let removeCount = max(1, count - retain)

        let job = RecognitionJob(
            source: source,
            startTime: startTime,
            samples: jobSamples,
            enqueuedAt: ContinuousClock.now
        )
        buffer.samples.removeFirst(removeCount)
        buffer.startTime = buffer.samples.isEmpty
            ? nil
            : startTime + TimeInterval(removeCount) / AudioFrame.sampleRate
        buffers[source] = buffer

        var queue = queuedJobs[source, default: []]
        queue.append(job)
        queuedJobs[source] = queue
    }

    private func dropOldestChunkAsBackpressureGap(source: AudioSource) async {
        guard var buffer = buffers[source], !buffer.samples.isEmpty else { return }
        let count = min(maxChunkSampleCount, buffer.samples.count)
        let startTime = buffer.startTime ?? 0
        let duration = TimeInterval(count) / AudioFrame.sampleRate
        buffer.samples.removeFirst(count)
        buffer.startTime = buffer.samples.isEmpty ? nil : startTime + duration
        buffers[source] = buffer
        await persistGap(
            CaptureGap(
                source: source,
                timestamp: startTime,
                duration: duration,
                reason: "recognition-backpressure"
            )
        )
    }

    private func scheduleIfPossible(source: AudioSource) {
        guard !cancelled, !inFlight.contains(source) else {
            completeIfDrained()
            return
        }
        guard var queue = queuedJobs[source], !queue.isEmpty else {
            completeIfDrained()
            return
        }
        let job = queue.removeFirst()
        queuedJobs[source] = queue
        inFlight.insert(source)
        let task = Task { [weak self] in
            guard let self else { return }
            await self.run(job)
        }
        recognitionTasks[source] = task
    }

    private func run(_ job: RecognitionJob) async {
        await perform(job)
        inFlight.remove(job.source)
        recognitionTasks[job.source] = nil
        guard !cancelled else { return }
        await drainSource(job.source)
        let other: AudioSource = job.source == .you ? .selectedSource : .you
        await drainSource(other)
        completeIfDrained()
    }

    private func perform(_ job: RecognitionJob) async {
        guard !cancelled else { return }
        let queueWaitMs = milliseconds(since: job.enqueuedAt)
        let audioDurationMs = Double(job.samples.count) / AudioFrame.sampleRate * 1_000.0
        let recognizer = recognizers.recognizer(for: job.source)

        do {
            let inferenceStarted = ContinuousClock.now
            let segments = try await recognizer.transcribe(
                samples: job.samples,
                sampleRate: AudioFrame.sampleRate,
                meetingID: meetingID,
                source: job.source,
                startTime: job.startTime
            )
            let inferenceMs = milliseconds(since: inferenceStarted)
            guard !cancelled else { return }

            let ordered = segments.sorted { $0.startTime < $1.startTime }
            for segment in ordered {
                guard !cancelled else { return }
                output?.yield(.finalized(segment))
            }

            var storeMs = 0.0
            if !ordered.isEmpty {
                let storeStarted = ContinuousClock.now
                do {
                    try await store.append(segments: ordered)
                    storeMs = milliseconds(since: storeStarted)
                } catch {
                    if !cancelled {
                        output?.yield(.failed("segment-persistence-failed"))
                    }
                    return
                }
            }

            output?.yield(
                .timing(
                    RecognitionTiming(
                        queueWaitMs: max(0, queueWaitMs),
                        inferenceMs: max(0, inferenceMs),
                        storeMs: max(0, storeMs),
                        audioDurationMs: audioDurationMs
                    )
                )
            )
        } catch SpeechRecognitionError.cancelled {
            if !cancelled { output?.yield(.failed("recognition-cancelled")) }
        } catch {
            guard !cancelled else { return }
            await persistGap(
                CaptureGap(
                    source: job.source,
                    timestamp: job.startTime,
                    duration: TimeInterval(job.samples.count) / AudioFrame.sampleRate,
                    reason: "recognition-failed"
                )
            )
        }
    }

    private func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: .now)
        return Double(duration.components.seconds) * 1_000.0
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000.0 * 1_000.0
    }

    private func recordGap(_ sourceGap: CaptureGap) async {
        if let buffer = buffers[sourceGap.source],
           !buffer.samples.isEmpty,
           hasQueueCapacity(for: sourceGap.source)
        {
            cutJob(source: sourceGap.source, sampleCount: buffer.samples.count, retainOverlap: false)
        }
        await persistGap(sourceGap)
        await drainSource(sourceGap.source)
    }

    private func persistGap(_ sourceGap: CaptureGap) async {
        let gap = TranscriptGap(
            meetingID: meetingID,
            source: sourceGap.source,
            timestamp: sourceGap.timestamp,
            duration: sourceGap.duration,
            reason: sourceGap.reason
        )
        do {
            try await store.append(gap)
            output?.yield(.gap(gap))
        } catch {
            if !cancelled { output?.yield(.failed("gap-persistence-failed")) }
        }
    }

    private func captureDidEnd() async {
        guard !cancelled else { return }
        captureEnded = true

        for source in [AudioSource.you, .selectedSource] {
            await drainSource(source)
        }

        while !cancelled {
            if inFlight.isEmpty,
               queuedJobs.values.allSatisfy(\.isEmpty),
               buffers.values.allSatisfy({ $0.samples.isEmpty })
            {
                break
            }

            for source in [AudioSource.you, .selectedSource] where !inFlight.contains(source) {
                await drainSource(source)
            }

            if let task = recognitionTasks.values.first {
                await task.value
                continue
            }

            if inFlight.isEmpty {
                var forced = false
                for source in [AudioSource.you, .selectedSource] {
                    if let buffer = buffers[source], !buffer.samples.isEmpty {
                        var queue = queuedJobs[source, default: []]
                        queue.append(
                            RecognitionJob(
                                source: source,
                                startTime: buffer.startTime ?? 0,
                                samples: buffer.samples,
                                enqueuedAt: ContinuousClock.now
                            )
                        )
                        queuedJobs[source] = queue
                        buffers[source] = SourceBuffer()
                        forced = true
                        scheduleIfPossible(source: source)
                    }
                }
                if !forced {
                    break
                }
            } else {
                await Task.yield()
            }
        }

        completeIfDrained()
    }

    private func completeIfDrained() {
        guard captureEnded,
              inFlight.isEmpty,
              queuedJobs.values.allSatisfy(\.isEmpty),
              buffers.values.allSatisfy({ $0.samples.isEmpty }) else { return }
        output?.finish()
        output = nil
        consumer = nil
    }
}
