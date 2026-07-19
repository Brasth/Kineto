import Foundation

public enum SpeechRecognitionError: Error, Equatable {
    case modelUnavailable
    case invalidAudioFormat
    case inferenceFailed(Int32)
    case cancelled
}

public protocol SpeechRecognizing: Sendable {
    func transcribe(
        samples: [Float],
        sampleRate: Double,
        meetingID: UUID,
        source: AudioSource,
        startTime: TimeInterval
    ) async throws -> [Segment]
}

/// Per-job stage timings for live latency diagnosis (L0).
public struct RecognitionTiming: Sendable, Equatable {
    public var queueWaitMs: Double
    public var inferenceMs: Double
    public var storeMs: Double
    public var audioDurationMs: Double

    public init(
        queueWaitMs: Double = 0,
        inferenceMs: Double = 0,
        storeMs: Double = 0,
        audioDurationMs: Double = 0
    ) {
        self.queueWaitMs = queueWaitMs
        self.inferenceMs = inferenceMs
        self.storeMs = storeMs
        self.audioDurationMs = audioDurationMs
    }

    public var totalPipelineMs: Double {
        queueWaitMs + inferenceMs + storeMs
    }
}

/// Routes each capture track to its own recognizer instance (L1 dual context).
public struct SourceRecognizerMap: Sendable {
    public let selectedSource: any SpeechRecognizing
    public let you: any SpeechRecognizing

    public init(selectedSource: any SpeechRecognizing, you: any SpeechRecognizing) {
        self.selectedSource = selectedSource
        self.you = you
    }

    /// Convenience when only one warmed context exists.
    public init(shared: any SpeechRecognizing) {
        self.selectedSource = shared
        self.you = shared
    }

    public func recognizer(for source: AudioSource) -> any SpeechRecognizing {
        switch source {
        case .selectedSource:
            selectedSource
        case .you:
            you
        }
    }
}
