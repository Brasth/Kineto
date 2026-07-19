import AVFoundation
import Testing
@testable import KinetoCore

@Test func normalizerProducesMono16KFloatSamples() async throws {
    let inputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48_000,
        channels: 2,
        interleaved: false
    )!
    let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 4_800)!
    input.frameLength = 4_800
    for channel in 0..<2 {
        for frame in 0..<Int(input.frameLength) {
            input.floatChannelData![channel][frame] = sin(Float(frame) * 0.01)
        }
    }

    let result = try await AudioNormalizer().normalize(
        input,
        source: .selectedSource,
        timestamp: 3.5
    )
    #expect(result.source == .selectedSource)
    #expect(result.timestamp == 3.5)
    #expect((1_590...1_610).contains(result.samples.count))
}
