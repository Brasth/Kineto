import Testing
@testable import KinetoCore

@Test func transcriptTextRejectsPunctuationOnlyResults() {
    #expect(!TranscriptText.isMeaningful(""))
    #expect(!TranscriptText.isMeaningful("  … — !?  "))
    #expect(TranscriptText.isMeaningful("Hello"))
    #expect(TranscriptText.isMeaningful("Xin chào"))
    #expect(TranscriptText.isMeaningful("你好"))
}
