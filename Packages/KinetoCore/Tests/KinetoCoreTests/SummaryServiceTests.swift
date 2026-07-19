import CryptoKit
import Foundation
import Testing
@testable import KinetoCore

private actor SummaryTestKeyStore: MeetingKeyStore {
    private var values: [String: SymmetricKey] = [:]
    private var generations: [UUID: UUID] = [:]

    func createKey(for meetingID: UUID, purpose: MeetingKeyPurpose) throws -> SymmetricKey {
        let value = SymmetricKey(size: .bits256)
        values["\(meetingID).\(purpose.rawValue)"] = value
        return value
    }

    func key(for meetingID: UUID, purpose: MeetingKeyPurpose) throws -> SymmetricKey {
        guard let value = values["\(meetingID).\(purpose.rawValue)"] else {
            throw MeetingKeyStoreError.missing
        }
        return value
    }

    func deleteKey(for meetingID: UUID, purpose: MeetingKeyPurpose) {
        values["\(meetingID).\(purpose.rawValue)"] = nil
    }

    func deleteKeys(for meetingID: UUID) {
        values["\(meetingID).\(MeetingKeyPurpose.text.rawValue)"] = nil
        values["\(meetingID).\(MeetingKeyPurpose.audio.rawValue)"] = nil
        generations[meetingID] = nil
    }

    func setGeneration(_ generation: UUID, for meetingID: UUID) {
        generations[meetingID] = generation
    }

    func generation(for meetingID: UUID) throws -> UUID {
        guard let generation = generations[meetingID] else {
            throw MeetingKeyStoreError.missing
        }
        return generation
    }

    func deleteGeneration(for meetingID: UUID) {
        generations[meetingID] = nil
    }
}

@Test func summaryServiceProducesEvidenceLinkedItems() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }

    let store = MeetingPackageStore(rootURL: root, keys: SummaryTestKeyStore())
    let meeting = Meeting(title: "Summary fallback")
    try await store.create(meeting)
    try await store.updateState(MeetingState.recording, for: meeting.id)

    let long = Segment(
        meetingID: meeting.id,
        source: .selectedSource,
        startTime: 0,
        endTime: 4,
        language: .english,
        text: "Compassion and love are the most important things these two people learned.",
        isFinal: true
    )
    let short = Segment(
        meetingID: meeting.id,
        source: .selectedSource,
        startTime: 4,
        endTime: 6,
        language: .english,
        text: "They climbed up.",
        isFinal: true
    )
    try await store.append(long)
    try await store.append(short)
    try await store.updateState(MeetingState.stopped, for: meeting.id)

    let snapshot = try await store.snapshot(for: meeting.id)
    let service = SummaryService()
    let template = SummaryTemplate.actionPlan
    let summary = try await service.generate(
        from: snapshot,
        language: .english,
        template: template
    )

    #expect(!summary.items.isEmpty)
    #expect(summary.items.contains(where: { $0.kind == SummaryItem.Kind.overview }))
    #expect(summary.templateID == template.rawValue)
    #expect(summary.templateVersion == template.version)
    #expect(summary.items.allSatisfy { template.sectionOrder.contains($0.kind) })
    #expect(summary.items.allSatisfy { !$0.evidence.isEmpty })
    #expect(summary.items.allSatisfy { item in
        item.evidence.allSatisfy { evidence in
            snapshot.segments.contains(where: { $0.id == evidence.segmentID })
        }
    })
}
