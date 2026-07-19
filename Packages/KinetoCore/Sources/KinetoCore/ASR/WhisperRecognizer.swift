import CWhisper
import Foundation

private final class RecognitionCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.withLock { cancelled = true }
    }

    func isCancelled() -> Bool {
        lock.withLock { cancelled }
    }
}

private final class WhisperContext: @unchecked Sendable {
    let pointer: OpaquePointer

    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        whisper_free(pointer)
    }
}

public actor WhisperRecognizer: SpeechRecognizing {
    private let context: WhisperContext
    private static let minimumActiveFrameRMS = 0.003
    private static let analysisFrameSampleCount = 320
    private static let minimumActiveSampleCount = 1_600

    public init(modelURL: URL) throws {
        guard FileManager.default.isReadableFile(atPath: modelURL.path) else {
            throw SpeechRecognitionError.modelUnavailable
        }
        var parameters = whisper_context_default_params()
        parameters.use_gpu = true
        guard let context = whisper_init_from_file_with_params(modelURL.path, parameters) else {
            throw SpeechRecognitionError.modelUnavailable
        }
        self.context = WhisperContext(pointer: context)
    }

    public func transcribe(
        samples: [Float],
        sampleRate: Double,
        meetingID: UUID,
        source: AudioSource,
        startTime: TimeInterval
    ) async throws -> [Segment] {
        guard sampleRate == 16_000, !samples.isEmpty else {
            throw SpeechRecognitionError.invalidAudioFormat
        }
        guard Self.hasSustainedAudio(samples) else { return [] }

        let cancellation = RecognitionCancellation()
        return try await withTaskCancellationHandler {
            var parameters = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
            parameters.n_threads = Int32(max(1, min(4, ProcessInfo.processInfo.activeProcessorCount - 2)))
            parameters.translate = false
            parameters.no_context = true
            parameters.no_timestamps = false
            parameters.single_segment = false
            parameters.suppress_nst = true
            parameters.print_special = false
            parameters.print_progress = false
            parameters.print_realtime = false
            parameters.print_timestamps = false
            parameters.language = nil
            parameters.detect_language = false
            parameters.abort_callback_user_data = Unmanaged.passUnretained(cancellation).toOpaque()
            parameters.abort_callback = { pointer in
                guard let pointer else { return false }
                return Unmanaged<RecognitionCancellation>
                    .fromOpaque(pointer)
                    .takeUnretainedValue()
                    .isCancelled()
            }

            let status = samples.withUnsafeBufferPointer { buffer in
                whisper_full(context.pointer, parameters, buffer.baseAddress, Int32(buffer.count))
            }
            if cancellation.isCancelled() || Task.isCancelled {
                throw SpeechRecognitionError.cancelled
            }
            guard status == 0 else {
                throw SpeechRecognitionError.inferenceFailed(status)
            }

            let language = Self.language(from: whisper_full_lang_id(context.pointer))
            let count = Int(whisper_full_n_segments(context.pointer))
            var draft: [(startTime: TimeInterval, endTime: TimeInterval, language: SpokenLanguage, text: String)] = []
            draft.reserveCapacity(count)
            for index in 0..<count {
                let noSpeechProbability = whisper_full_get_segment_no_speech_prob(
                    context.pointer,
                    Int32(index)
                )
                guard noSpeechProbability < parameters.no_speech_thold else { continue }
                guard let rawText = whisper_full_get_segment_text(context.pointer, Int32(index)) else {
                    continue
                }
                let text = String(cString: rawText).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let segmentStart = startTime + TimeInterval(whisper_full_get_segment_t0(context.pointer, Int32(index))) / 100
                let segmentEnd = startTime + TimeInterval(whisper_full_get_segment_t1(context.pointer, Int32(index))) / 100
                draft.append((segmentStart, max(segmentEnd, segmentStart), language, text))
            }

            return draft.map { item in
                Segment(
                    meetingID: meetingID,
                    source: source,
                    speakerLabel: .default(for: source),
                    startTime: item.startTime,
                    endTime: item.endTime,
                    language: item.language,
                    text: item.text,
                    isFinal: true
                )
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    static func hasSustainedAudio(_ samples: [Float]) -> Bool {
        var activeSampleCount = 0
        var frameStart = 0
        while frameStart < samples.count {
            let frameEnd = min(frameStart + analysisFrameSampleCount, samples.count)
            var squareSum = 0.0
            for index in frameStart..<frameEnd {
                let sample = Double(samples[index])
                squareSum += sample * sample
            }
            let frameSampleCount = frameEnd - frameStart
            let rms = sqrt(squareSum / Double(frameSampleCount))
            if rms >= minimumActiveFrameRMS {
                activeSampleCount += frameSampleCount
                if activeSampleCount >= minimumActiveSampleCount {
                    return true
                }
            }
            frameStart = frameEnd
        }
        return false
    }

    private static func language(from identifier: Int32) -> SpokenLanguage {
        guard let pointer = whisper_lang_str(identifier) else { return .unknown }
        switch String(cString: pointer) {
        case "en":
            return .english
        case "vi":
            return .vietnamese
        case "zh":
            return .chinese
        default:
            return .unknown
        }
    }
}
