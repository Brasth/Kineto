@testable import KinetoCore
import Testing

@Test func whisperRecognizerRejectsSilenceAndBriefNoise() {
    #expect(!WhisperRecognizer.hasSustainedAudio(Array(repeating: 0, count: 8 * 16_000)))

    var briefNoise = Array(repeating: Float.zero, count: 8 * 16_000)
    for index in 0..<(4 * 320) {
        briefNoise[index] = 0.02
    }
    #expect(!WhisperRecognizer.hasSustainedAudio(briefNoise))
}

@Test func whisperRecognizerAdmitsSustainedAudio() {
    var samples = Array(repeating: Float.zero, count: 8 * 16_000)
    for index in 0..<(5 * 320) {
        samples[index] = index.isMultiple(of: 2) ? 0.02 : -0.02
    }

    #expect(WhisperRecognizer.hasSustainedAudio(samples))
}
