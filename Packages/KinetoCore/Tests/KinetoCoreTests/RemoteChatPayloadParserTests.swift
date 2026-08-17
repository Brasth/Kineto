import Foundation
import Testing
@testable import KinetoCore

@Test func remoteParserAcceptsBareJSONObject() throws {
    let segmentID = UUID(uuidString: "00000000-0000-0000-0000-000000000021")!
    let raw = """
        {"answer":"Launch is Friday.","citations":[{"segmentID":"\(segmentID.uuidString)","quote":"launch date is Friday"}]}
        """
    let parsed = try RemoteChatPayloadParser.parse(raw)
    #expect(parsed.answer == "Launch is Friday.")
    #expect(parsed.citations == [
        EvidenceReference(segmentID: segmentID, supportingText: "launch date is Friday")
    ])
}

@Test func remoteParserAcceptsFencedJSONAndIgnoresInvalidSegmentIDs() throws {
    let segmentID = UUID(uuidString: "00000000-0000-0000-0000-000000000022")!
    let raw = """
        Here you go:
        ```json
        {"answer":"Ship Friday.","citations":[{"segmentID":"not-a-uuid","quote":"no"},{"segmentID":"\(segmentID.uuidString)","quote":"Friday"}]}
        ```
        """
    let parsed = try RemoteChatPayloadParser.parse(raw)
    #expect(parsed.answer == "Ship Friday.")
    #expect(parsed.citations == [
        EvidenceReference(segmentID: segmentID, supportingText: "Friday")
    ])
}

@Test func remoteParserRejectsNonJSON() {
    #expect(throws: ChatGenerationError.invalidPayload) {
        try RemoteChatPayloadParser.parse("the launch is Friday")
    }
}
