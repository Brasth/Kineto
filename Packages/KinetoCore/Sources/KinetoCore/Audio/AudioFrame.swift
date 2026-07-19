import AVFoundation
import Foundation

public struct AudioFrame: Sendable {
    public static let sampleRate: Double = 16_000

    public let source: AudioSource
    public let timestamp: TimeInterval
    public let samples: [Float]

    public init(source: AudioSource, timestamp: TimeInterval, samples: [Float]) {
        self.source = source
        self.timestamp = timestamp
        self.samples = samples
    }
}

public enum AudioNormalizationError: Error {
    case unsupportedFormat
    case allocationFailed
    case conversionFailed
}

private final class ConverterInput: @unchecked Sendable {
    private let lock = NSLock()
    private let buffer: AVAudioPCMBuffer
    private var consumed = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        lock.withLock {
            guard !consumed else {
                status.pointee = .endOfStream
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
    }
}

public actor AudioNormalizer {
    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: AudioFrame.sampleRate,
        channels: 1,
        interleaved: false
    )!

    public init() {}

    public func normalize(
        _ input: AVAudioPCMBuffer,
        source: AudioSource,
        timestamp: TimeInterval
    ) throws -> AudioFrame {
        guard let converter = AVAudioConverter(from: input.format, to: outputFormat) else {
            throw AudioNormalizationError.unsupportedFormat
        }
        let ratio = outputFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * ratio)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw AudioNormalizationError.allocationFailed
        }

        let converterInput = ConverterInput(buffer: input)
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            converterInput.next(status: inputStatus)
        }
        guard conversionError == nil, status != .error, let channel = output.floatChannelData?[0] else {
            throw AudioNormalizationError.conversionFailed
        }
        return AudioFrame(
            source: source,
            timestamp: timestamp,
            samples: Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
        )
    }
}
