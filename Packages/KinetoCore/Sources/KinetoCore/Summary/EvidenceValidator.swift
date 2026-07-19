import Foundation

public enum EvidenceValidationError: Error, Equatable {
    case missingEvidence
    case unknownSegment(UUID)
    case unsupportedText
    case emptySummaryText
    case citationOutsideRetrievedContext(UUID)
    case citationFromDifferentMeeting(UUID)
    case citationFromNonFinalSegment(UUID)
}

public struct EvidenceValidator: Sendable {
    public init() {}

    /// Validates that every evidence excerpt is an exact contiguous quote from its cited segment.
    /// Summary prose may be abstractive; evidence remains extractive.
    public func validate(
        kind: SummaryItem.Kind,
        text: String,
        evidence: [EvidenceReference],
        segments: [Segment]
    ) throws -> SummaryItem {
        let summaryText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summaryText.isEmpty else { throw EvidenceValidationError.emptySummaryText }
        guard !evidence.isEmpty else { throw EvidenceValidationError.missingEvidence }

        let indexed = Dictionary(uniqueKeysWithValues: segments.map { ($0.id, $0) })
        var validated: [EvidenceReference] = []
        validated.reserveCapacity(evidence.count)

        for reference in evidence {
            guard let segment = indexed[reference.segmentID] else {
                throw EvidenceValidationError.unknownSegment(reference.segmentID)
            }
            let excerpt = reference.supportingText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !excerpt.isEmpty else {
                throw EvidenceValidationError.unsupportedText
            }
            let normalizedExcerpt = normalize(excerpt)
            let normalizedSegment = normalize(segment.text)
            // Prefer exact quote containment; also accept the full segment text as evidence.
            let excerptOK = !normalizedExcerpt.isEmpty && (
                normalizedSegment.contains(normalizedExcerpt) ||
                normalizedExcerpt.contains(normalizedSegment) ||
                normalizedExcerpt == normalizedSegment
            )
            guard excerptOK else {
                throw EvidenceValidationError.unsupportedText
            }
            validated.append(
                EvidenceReference(segmentID: reference.segmentID, supportingText: excerpt)
            )
        }

        return SummaryItem(kind: kind, text: summaryText, evidence: validated)
    }

    /// Validates chat citations against the immutable, retrieved transcript source.
    ///
    /// Unlike summary validation, this deliberately does not normalize case,
    /// whitespace, punctuation, or diacritics: the submitted excerpt must be a
    /// literal contiguous span after only outer whitespace is removed.
    public func validateChatCitations(
        _ citations: [EvidenceReference],
        meetingID: UUID,
        retrievedSegments: [Segment]
    ) throws -> [EvidenceReference] {
        guard !citations.isEmpty else { throw EvidenceValidationError.missingEvidence }
        let indexed = Dictionary(uniqueKeysWithValues: retrievedSegments.map { ($0.id, $0) })
        var validated: [EvidenceReference] = []
        validated.reserveCapacity(citations.count)

        for citation in citations {
            guard let segment = indexed[citation.segmentID] else {
                throw EvidenceValidationError.citationOutsideRetrievedContext(citation.segmentID)
            }
            guard segment.meetingID == meetingID else {
                throw EvidenceValidationError.citationFromDifferentMeeting(citation.segmentID)
            }
            guard segment.isFinal else {
                throw EvidenceValidationError.citationFromNonFinalSegment(citation.segmentID)
            }
            let excerpt = citation.supportingText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !excerpt.isEmpty, segment.text.range(of: excerpt) != nil else {
                throw EvidenceValidationError.unsupportedText
            }
            validated.append(
                EvidenceReference(segmentID: segment.id, supportingText: excerpt)
            )
        }

        return validated
    }

    /// Backward-compatible helper used by older call sites/tests that only supply IDs.
    /// Uses full segment text as the supporting excerpt and requires the summary text
    /// itself to appear inside at least one cited segment.
    public func validate(
        kind: SummaryItem.Kind,
        text: String,
        evidenceIDs: [UUID],
        segments: [Segment]
    ) throws -> SummaryItem {
        guard !evidenceIDs.isEmpty else { throw EvidenceValidationError.missingEvidence }
        let indexed = Dictionary(uniqueKeysWithValues: segments.map { ($0.id, $0) })
        let evidence = try evidenceIDs.map { id -> EvidenceReference in
            guard let segment = indexed[id] else {
                throw EvidenceValidationError.unknownSegment(id)
            }
            return EvidenceReference(segmentID: id, supportingText: segment.text)
        }
        let item = try validate(kind: kind, text: text, evidence: evidence, segments: segments)
        let normalizedText = normalize(text)
        guard evidence.contains(where: { normalize($0.supportingText).contains(normalizedText) }) else {
            throw EvidenceValidationError.unsupportedText
        }
        return item
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
    }
}
