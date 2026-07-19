import Foundation
import Testing
@testable import KinetoCore

@Test func evidenceValidatorRequiresExtractiveSupport() throws {
    let meetingID = UUID()
    let source = Segment(
        meetingID: meetingID,
        source: .selectedSource,
        startTime: 0,
        endTime: 3,
        language: .english,
        text: "We will ship the local prototype on Friday.",
        isFinal: true
    )
    let validator = EvidenceValidator()
    let accepted = try validator.validate(
        kind: .action,
        text: "Ship the local prototype on Friday.",
        evidence: [
            EvidenceReference(
                segmentID: source.id,
                supportingText: "ship the local prototype on Friday"
            )
        ],
        segments: [source]
    )
    #expect(accepted.evidence.first?.segmentID == source.id)

    do {
        _ = try validator.validate(
            kind: .action,
            text: "Alice will ship on Monday",
            evidence: [
                EvidenceReference(
                    segmentID: source.id,
                    supportingText: "Alice will ship on Monday"
                )
            ],
            segments: [source]
        )
        Issue.record("Unsupported owner and date were accepted")
    } catch let error as EvidenceValidationError {
        #expect(error == .unsupportedText)
    }
}
