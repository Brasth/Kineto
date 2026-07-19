import Foundation
import Testing
@testable import KinetoCore

@Test func speakerLabelDefaultsFollowCaptureSource() {
    #expect(SpeakerLabel.default(for: .you) == .you)
    #expect(SpeakerLabel.default(for: .selectedSource) == .selectedSource)
    #expect(SpeakerLabel.you.displayName == "You")
    #expect(SpeakerLabel.selectedSource.displayName == "Selected Source")
}

@Test func segmentSpeakerLabelDefaultsAndDecodesLegacyPayloads() throws {
    let meetingID = UUID()
    let youSegment = Segment(
        meetingID: meetingID,
        source: .you,
        startTime: 0,
        endTime: 1,
        language: .english,
        text: "hello",
        isFinal: true
    )
    #expect(youSegment.speakerLabel == .you)

    let selectedSegment = Segment(
        meetingID: meetingID,
        source: .selectedSource,
        startTime: 0,
        endTime: 1,
        language: .english,
        text: "remote",
        isFinal: true
    )
    #expect(selectedSegment.speakerLabel == .selectedSource)

    let legacyMissingLabel = """
    {
      "id": "\(UUID().uuidString)",
      "meetingID": "\(meetingID.uuidString)",
      "source": "selectedSource",
      "startTime": 0,
      "endTime": 1,
      "language": "en",
      "text": "legacy",
      "isFinal": true
    }
    """.data(using: .utf8)!
    let decodedMissing = try JSONDecoder().decode(Segment.self, from: legacyMissingLabel)
    #expect(decodedMissing.speakerLabel == .selectedSource)

    let legacyPersonA = """
    {
      "id": "\(UUID().uuidString)",
      "meetingID": "\(meetingID.uuidString)",
      "source": "selectedSource",
      "speakerLabel": "personA",
      "startTime": 0,
      "endTime": 1,
      "language": "en",
      "text": "legacy-a",
      "isFinal": true
    }
    """.data(using: .utf8)!
    let decodedPersonA = try JSONDecoder().decode(Segment.self, from: legacyPersonA)
    #expect(decodedPersonA.speakerLabel == .selectedSource)

    let legacyPersonB = """
    {
      "id": "\(UUID().uuidString)",
      "meetingID": "\(meetingID.uuidString)",
      "source": "selectedSource",
      "speakerLabel": "personB",
      "startTime": 0,
      "endTime": 1,
      "language": "en",
      "text": "legacy-b",
      "isFinal": true
    }
    """.data(using: .utf8)!
    let decodedPersonB = try JSONDecoder().decode(Segment.self, from: legacyPersonB)
    #expect(decodedPersonB.speakerLabel == .selectedSource)
}

@Test func spokenLanguagePreservesRegionalTagsAndGatesTranslationByLanguage() throws {
    let regional = SpokenLanguage(localeIdentifier: "pt_BR")
    #expect(regional.rawValue == "pt-BR")
    #expect(regional.languageCode == "pt")
    #expect(regional.translationTarget == nil)

    let americanEnglish = SpokenLanguage(localeIdentifier: "en-US")
    #expect(americanEnglish.isEnglish)
    #expect(americanEnglish.translationTarget == .vietnamese)

    let encoded = try JSONEncoder().encode(regional)
    #expect(try JSONDecoder().decode(SpokenLanguage.self, from: encoded) == regional)
}
