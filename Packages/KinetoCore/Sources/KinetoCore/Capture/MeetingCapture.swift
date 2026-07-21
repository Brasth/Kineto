@preconcurrency import AVFoundation
@preconcurrency import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

public struct CaptureTarget: @unchecked Sendable {
    public let name: String
    let filter: SCContentFilter

    public init(name: String, filter: SCContentFilter) {
        self.name = name
        self.filter = filter
    }
}

public struct CaptureGap: Equatable, Sendable {
    public let source: AudioSource
    public let timestamp: TimeInterval
    public let duration: TimeInterval
    public let reason: String

    public init(
        source: AudioSource,
        timestamp: TimeInterval,
        duration: TimeInterval = 0,
        reason: String
    ) {
        self.source = source
        self.timestamp = timestamp
        self.duration = duration
        self.reason = reason
    }
}

public enum CaptureEvent: Sendable {
    case audio(AudioFrame)
    case gap(CaptureGap)
    case sourceLost(TimeInterval)
    case failed(String)
}

public enum MeetingCaptureError: Error {
    case alreadyRunning
    case notRunning
    case audioBufferInvalid
}

private final class PCMBufferBox: @unchecked Sendable {
    let value: AVAudioPCMBuffer

    init(_ value: AVAudioPCMBuffer) {
        self.value = value
    }
}

private final class BoundedAdmission: @unchecked Sendable {
    private let semaphore: DispatchSemaphore

    init(capacity: Int) {
        semaphore = DispatchSemaphore(value: capacity)
    }

    func tryEnter() -> Bool {
        semaphore.wait(timeout: .now()) == .success
    }

    func leave() {
        semaphore.signal()
    }
}

private final class MicrophoneClock: @unchecked Sendable {
    private let lock = NSLock()
    private var framePosition: Int64 = 0

    func reset() {
        lock.withLock { framePosition = 0 }
    }

    func advance(frameLength: AVAudioFrameCount, sampleRate: Double) -> TimeInterval {
        lock.withLock {
            let timestamp = TimeInterval(framePosition) / sampleRate
            framePosition += Int64(frameLength)
            return timestamp
        }
    }
}

private final class CaptureDropAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var gaps: [AudioSource: CaptureGap] = [:]

    func record(source: AudioSource, timestamp: TimeInterval, duration: TimeInterval) {
        lock.withLock {
            let incomingEnd = timestamp + duration
            if let existing = gaps[source] {
                let start = min(existing.timestamp, timestamp)
                let end = max(existing.timestamp + existing.duration, incomingEnd)
                gaps[source] = CaptureGap(
                    source: source,
                    timestamp: start,
                    duration: max(0, end - start),
                    reason: "capture-ingress-backpressure"
                )
            } else {
                gaps[source] = CaptureGap(
                    source: source,
                    timestamp: timestamp,
                    duration: duration,
                    reason: "capture-ingress-backpressure"
                )
            }
        }
    }

    func take(source: AudioSource) -> CaptureGap? {
        lock.withLock { gaps.removeValue(forKey: source) }
    }

    func takeAll() -> [CaptureGap] {
        lock.withLock {
            let result = Array(gaps.values)
            gaps.removeAll(keepingCapacity: true)
            return result
        }
    }
}

private final class CaptureOutputProxy: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    var onAudio: (@Sendable (PCMBufferBox, TimeInterval) -> Void)?
    var onStop: (@Sendable (Error) -> Void)?

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio, sampleBuffer.isValid, sampleBuffer.dataReadiness == .ready else {
            return
        }
        guard let formatDescription = sampleBuffer.formatDescription,
              let description = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return
        }
        var streamDescription = description.pointee
        guard let format = AVAudioFormat(streamDescription: &streamDescription) else { return }
        let frameCount = AVAudioFrameCount(sampleBuffer.numSamples)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: buffer.mutableAudioBufferList
        )
        guard status == noErr else { return }
        onAudio?(PCMBufferBox(buffer), sampleBuffer.presentationTimeStamp.seconds)
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        onStop?(error)
    }
}

public actor MeetingCapture {
    private enum State {
        case idle
        case running
        case paused
        case stopping
    }

    private let systemNormalizer = AudioNormalizer()
    private let microphoneNormalizer = AudioNormalizer()
    private let outputQueue = DispatchQueue(label: "com.huynguyen.Kineto.capture-output", qos: .userInitiated)
    private let outputProxy = CaptureOutputProxy()
    private let normalizationGroup = DispatchGroup()
    private let systemAdmission = BoundedAdmission(capacity: 4)
    private let microphoneAdmission = BoundedAdmission(capacity: 4)
    private let microphoneClock = MicrophoneClock()
    private let ingressDrops = CaptureDropAccumulator()
    private var state: State = .idle
    private var stream: SCStream?
    private var audioEngine: AVAudioEngine?
    private var continuation: AsyncStream<CaptureEvent>.Continuation?
    private var pendingOutputGaps: [AudioSource: CaptureGap] = [:]
    private var lastSystemAudioEnd: TimeInterval = 0

    public init() {}

    public func start(target: CaptureTarget, includeMicrophone: Bool) async throws -> AsyncStream<CaptureEvent> {
        guard state == .idle else { throw MeetingCaptureError.alreadyRunning }
        let (events, continuation) = AsyncStream<CaptureEvent>.makeStream(bufferingPolicy: .bufferingOldest(256))
        self.continuation = continuation
        pendingOutputGaps.removeAll(keepingCapacity: true)
        _ = ingressDrops.takeAll()
        microphoneClock.reset()
        continuation.onTermination = { [weak self] _ in
            Task { await self?.stopAfterTermination() }
        }

        let systemAdmission = systemAdmission
        let ingressDrops = ingressDrops
        outputProxy.onAudio = { [weak self, normalizationGroup] buffer, timestamp in
            let duration = TimeInterval(buffer.value.frameLength) / buffer.value.format.sampleRate
            guard systemAdmission.tryEnter() else {
                ingressDrops.record(source: .selectedSource, timestamp: timestamp, duration: duration)
                return
            }
            normalizationGroup.enter()
            Task {
                await self?.receiveSystemAudio(buffer, timestamp: timestamp)
                systemAdmission.leave()
                normalizationGroup.leave()
            }
        }
        outputProxy.onStop = { [weak self] _ in
            Task { await self?.receiveSourceLoss() }
        }

        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.showsCursor = false

        let stream = SCStream(filter: target.filter, configuration: configuration, delegate: outputProxy)
        try stream.addStreamOutput(outputProxy, type: .audio, sampleHandlerQueue: outputQueue)
        self.stream = stream

        lastSystemAudioEnd = 0
        do {
            if includeMicrophone {
                try startMicrophone()
            }
            try await stream.startCapture()
            state = .running
            return events
        } catch {
            stopMicrophone()
            self.stream = nil
            self.continuation = nil
            continuation.finish()
            throw error
        }
    }

    public func pause() async throws {
        guard state == .running, let stream else { throw MeetingCaptureError.notRunning }
        try await stream.stopCapture()
        stopMicrophone()
        await drainNormalization()
        flushIngressDrops()
        state = .paused
    }

    public func resume(includeMicrophone: Bool) async throws {
        guard state == .paused, let stream else { throw MeetingCaptureError.notRunning }
        do {
            try await stream.startCapture()
            if includeMicrophone {
                try startMicrophone()
            }
            state = .running
        } catch {
            stopMicrophone()
            try? await stream.stopCapture()
            throw error
        }
    }

    public func stop() async throws {
        guard state != .idle else { throw MeetingCaptureError.notRunning }
        let wasRunning = state == .running
        state = .stopping
        if wasRunning, let stream {
            try await stream.stopCapture()
        }
        stopMicrophone()
        await drainNormalization()
        flushIngressDrops()
        await finishCapture()
    }

    private func startMicrophone() throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let microphoneAdmission = microphoneAdmission
        let microphoneClock = microphoneClock
        let ingressDrops = ingressDrops
        input.installTap(onBus: 0, bufferSize: 2_048, format: format) { [weak self, normalizationGroup] buffer, _ in
            let timestamp = microphoneClock.advance(
                frameLength: buffer.frameLength,
                sampleRate: buffer.format.sampleRate
            )
            let duration = TimeInterval(buffer.frameLength) / buffer.format.sampleRate
            guard microphoneAdmission.tryEnter() else {
                ingressDrops.record(source: .you, timestamp: timestamp, duration: duration)
                return
            }
            guard let owned = Self.copy(buffer) else {
                microphoneAdmission.leave()
                return
            }
            normalizationGroup.enter()
            Task {
                await self?.receiveMicrophoneAudio(PCMBufferBox(owned), timestamp: timestamp)
                microphoneAdmission.leave()
                normalizationGroup.leave()
            }
        }
        engine.prepare()
        try engine.start()
        audioEngine = engine
    }

    private func stopMicrophone() {
        guard let audioEngine else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        self.audioEngine = nil
    }

    private func receiveSystemAudio(_ box: PCMBufferBox, timestamp: TimeInterval) async {
        guard state == .running || state == .stopping else { return }
        flushIngressDrop(for: .selectedSource)
        do {
            let frame = try await systemNormalizer.normalize(
                box.value,
                source: .selectedSource,
                timestamp: timestamp
            )
            yield(.audio(frame), source: .selectedSource, timestamp: timestamp)
            lastSystemAudioEnd = timestamp + TimeInterval(frame.samples.count) / AudioFrame.sampleRate
        } catch {
            yield(
                .gap(CaptureGap(
                    source: .selectedSource,
                    timestamp: timestamp,
                    duration: TimeInterval(box.value.frameLength) / box.value.format.sampleRate,
                    reason: "audio-normalization"
                )),
                source: .selectedSource,
                timestamp: timestamp
            )
        }
    }

    private func receiveMicrophoneAudio(_ box: PCMBufferBox, timestamp: TimeInterval) async {
        guard state == .running || state == .stopping else { return }
        flushIngressDrop(for: .you)
        do {
            let frame = try await microphoneNormalizer.normalize(box.value, source: .you, timestamp: timestamp)
            yield(.audio(frame), source: .you, timestamp: timestamp)
        } catch {
            yield(
                .gap(CaptureGap(
                    source: .you,
                    timestamp: timestamp,
                    duration: TimeInterval(box.value.frameLength) / box.value.format.sampleRate,
                    reason: "audio-normalization"
                )),
                source: .you,
                timestamp: timestamp
            )
        }
    }

    private func receiveSourceLoss() async {
        guard state == .running else { return }
        state = .stopping
        stopMicrophone()
        await drainNormalization()
        flushIngressDrops()
        yield(.sourceLost(lastSystemAudioEnd), source: .selectedSource, timestamp: lastSystemAudioEnd)
        await finishCapture()
    }

    private func yield(_ event: CaptureEvent, source: AudioSource, timestamp: TimeInterval) {
        guard let continuation else { return }
        flushPendingOutputGap(for: source)
        guard pendingOutputGaps[source] == nil else {
            recordPendingOutputGap(for: event)
            return
        }
        if case let .dropped(dropped) = continuation.yield(event) {
            recordPendingOutputGap(for: dropped)
        }
    }

    private func flushIngressDrop(for source: AudioSource) {
        guard let gap = ingressDrops.take(source: source) else { return }
        yield(.gap(gap), source: source, timestamp: gap.timestamp)
    }

    private func flushIngressDrops() {
        for gap in ingressDrops.takeAll() {
            yield(.gap(gap), source: gap.source, timestamp: gap.timestamp)
        }
    }

    private func flushPendingOutputGap(for source: AudioSource) {
        guard let continuation, let gap = pendingOutputGaps[source] else { return }
        switch continuation.yield(.gap(gap)) {
        case .enqueued:
            pendingOutputGaps[source] = nil
        case .terminated:
            pendingOutputGaps[source] = nil
        case .dropped:
            break
        @unknown default:
            break
        }
    }

    private func recordPendingOutputGap(for event: CaptureEvent) {
        guard let gap = Self.gap(for: event) else { return }
        if let existing = pendingOutputGaps[gap.source] {
            let start = min(existing.timestamp, gap.timestamp)
            let end = max(existing.timestamp + existing.duration, gap.timestamp + gap.duration)
            pendingOutputGaps[gap.source] = CaptureGap(
                source: gap.source,
                timestamp: start,
                duration: max(0, end - start),
                reason: "capture-backpressure"
            )
        } else {
            pendingOutputGaps[gap.source] = gap
        }
    }

    private func flushPendingOutputBeforeFinish() async {
        for source in Array(pendingOutputGaps.keys) {
            flushPendingOutputGap(for: source)
        }
        pendingOutputGaps.removeAll(keepingCapacity: true)
    }

    private func drainNormalization() async {
        await withCheckedContinuation { continuation in
            normalizationGroup.notify(queue: outputQueue) {
                continuation.resume()
            }
        }
    }

    private static func copy(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let destination = AVAudioPCMBuffer(
            pcmFormat: source.format,
            frameCapacity: source.frameLength
        ) else { return nil }
        destination.frameLength = source.frameLength
        let sourceBuffers = UnsafeMutableAudioBufferListPointer(source.mutableAudioBufferList)
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(destination.mutableAudioBufferList)
        guard sourceBuffers.count == destinationBuffers.count else { return nil }
        for index in sourceBuffers.indices {
            guard let sourceData = sourceBuffers[index].mData,
                  let destinationData = destinationBuffers[index].mData else { return nil }
            let byteCount = Int(sourceBuffers[index].mDataByteSize)
            memcpy(destinationData, sourceData, byteCount)
            destinationBuffers[index].mDataByteSize = sourceBuffers[index].mDataByteSize
        }
        return destination
    }

    private static func gap(for event: CaptureEvent) -> CaptureGap? {
        switch event {
        case let .audio(frame):
            return CaptureGap(
                source: frame.source,
                timestamp: frame.timestamp,
                duration: TimeInterval(frame.samples.count) / AudioFrame.sampleRate,
                reason: "capture-backpressure"
            )
        case let .gap(gap):
            return gap
        case let .sourceLost(timestamp):
            return CaptureGap(source: .selectedSource, timestamp: timestamp, reason: "source-lost")
        case .failed:
            return nil
        }
    }

    private func finishCapture() async {
        stopMicrophone()
        flushIngressDrops()
        await flushPendingOutputBeforeFinish()
        stream = nil
        state = .idle
        continuation?.finish()
        continuation = nil
        pendingOutputGaps.removeAll(keepingCapacity: true)
        outputProxy.onAudio = nil
        outputProxy.onStop = nil
    }

    private func stopAfterTermination() async {
        guard state != .idle else { return }
        let wasRunning = state == .running
        state = .stopping
        if wasRunning {
            try? await stream?.stopCapture()
        }
        stopMicrophone()
        await drainNormalization()
        flushIngressDrops()
        await finishCapture()
    }
}
