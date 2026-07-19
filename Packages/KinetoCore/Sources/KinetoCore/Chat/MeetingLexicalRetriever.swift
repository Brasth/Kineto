import Foundation

struct RetrievedSegment: Sendable, Equatable {
    let segment: Segment
    /// An exact contiguous substring of `segment.text` supplied to the model.
    let promptExcerpt: String
}

/// Request-scoped retrieval context. Transcript gaps are prompt-only and never
/// become citation sources.
struct RetrievedMeetingContext: Sendable, Equatable {
    let segments: [RetrievedSegment]
    let gaps: [TranscriptGap]

    var sourceSegments: [Segment] {
        segments.map(\.segment)
    }

    var prompt: String {
        let entries = segments.map(TimelineEntry.segment) + gaps.map(TimelineEntry.gap)
        return entries
            .sorted(by: TimelineEntry.isChronological)
            .map(\.description)
            .joined(separator: "\n\n")
    }
}

/// Deterministic lexical retrieval for one stopped meeting snapshot.
struct MeetingLexicalRetriever: Sendable {
    struct Configuration: Sendable, Equatable {
        let maximumSegments: Int
        let maximumContextCharacters: Int
        let maximumSegmentExcerptCharacters: Int

        static let `default` = Configuration(
            maximumSegments: 6,
            maximumContextCharacters: 4_000,
            maximumSegmentExcerptCharacters: 800
        )
    }
    private static let ignoredQueryTokens: Set<String> = [
        "a", "an", "and", "are", "did", "do", "does", "for", "from", "how", "i",
        "in", "is", "it", "of", "on", "the", "to", "was", "were", "what", "when",
        "where", "which", "who", "why", "with", "you"
    ]

    private static let normalizationLocale = Locale(identifier: "en_US_POSIX")
    private let configuration: Configuration

    init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    func retrieve(question: String, from snapshot: MeetingSnapshot) -> RetrievedMeetingContext {
        guard snapshot.meeting.state == .stopped else {
            return RetrievedMeetingContext(segments: [], gaps: [])
        }

        return retrieve(
            question: question,
            meetingID: snapshot.meeting.id,
            segments: snapshot.segments,
            gaps: snapshot.gaps
        )
    }

    func retrieve(
        question: String,
        meetingID: UUID,
        segments: [Segment],
        gaps: [TranscriptGap]
    ) -> RetrievedMeetingContext {
        let queryTokens = uniqueTokens(in: question)
        guard !queryTokens.isEmpty else {
            return RetrievedMeetingContext(segments: [], gaps: [])
        }

        let normalizedQuestion = queryTokens.joined(separator: " ")
        let ranked = segments.compactMap { segment -> RankedSegment? in
            guard segment.meetingID == meetingID, segment.isFinal else { return nil }
            let normalizedText = normalize(segment.text)
            guard !normalizedText.isEmpty else { return nil }

            let segmentTokens = tokens(in: normalizedText)
            let distinctTokenMatches = Set(segmentTokens).intersection(queryTokens).count
            guard distinctTokenMatches > 0 else { return nil }

            let totalOccurrences = queryTokens.reduce(into: 0) { count, token in
                count += segmentTokens.count(where: { $0 == token })
            }
            return RankedSegment(
                segment: segment,
                containsPhrase: queryTokens.count > 1 && normalizedText.contains(normalizedQuestion),
                distinctTokenMatches: distinctTokenMatches,
                totalOccurrences: totalOccurrences
            )
        }
        .sorted(by: Self.isHigherRanked)

        var selected: [RetrievedSegment] = []
        selected.reserveCapacity(configuration.maximumSegments)
        var serializedCharacters = 0
        for candidate in ranked.prefix(configuration.maximumSegments) {
            let excerpt = excerpt(from: candidate.segment.text, queryTokens: queryTokens)
            let serializedCount = candidate.segment.id.uuidString.count + excerpt.count
            guard serializedCharacters + serializedCount <= configuration.maximumContextCharacters else { continue }
            selected.append(RetrievedSegment(segment: candidate.segment, promptExcerpt: excerpt))
            serializedCharacters += serializedCount
        }

        selected.sort { Self.isChronological($0.segment, $1.segment) }
        return RetrievedMeetingContext(
            segments: selected,
            gaps: contextualGaps(
                for: selected.map(\.segment),
                meetingID: meetingID,
                gaps: gaps
            )
        )
    }

    private struct RankedSegment {
        let segment: Segment
        let containsPhrase: Bool
        let distinctTokenMatches: Int
        let totalOccurrences: Int
    }

    private static func isHigherRanked(_ lhs: RankedSegment, _ rhs: RankedSegment) -> Bool {
        if lhs.containsPhrase != rhs.containsPhrase { return lhs.containsPhrase }
        if lhs.distinctTokenMatches != rhs.distinctTokenMatches {
            return lhs.distinctTokenMatches > rhs.distinctTokenMatches
        }
        if lhs.totalOccurrences != rhs.totalOccurrences {
            return lhs.totalOccurrences > rhs.totalOccurrences
        }
        return isChronological(lhs.segment, rhs.segment)
    }

    private static func isChronological(_ lhs: Segment, _ rhs: Segment) -> Bool {
        if lhs.startTime != rhs.startTime { return lhs.startTime < rhs.startTime }
        if lhs.endTime != rhs.endTime { return lhs.endTime < rhs.endTime }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func contextualGaps(
        for segments: [Segment],
        meetingID: UUID,
        gaps: [TranscriptGap]
    ) -> [TranscriptGap] {
        guard let first = segments.first, let last = segments.last else { return [] }
        let scoped = gaps
            .filter { $0.meetingID == meetingID }
            .sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        let before = scoped.last(where: { $0.timestamp < first.startTime })
        let inWindow = scoped.filter { $0.timestamp >= first.startTime && $0.timestamp <= last.endTime }
        let after = scoped.first(where: { $0.timestamp > last.endTime })
        var seen = Set<UUID>()
        return ([before].compactMap { $0 } + inWindow + [after].compactMap { $0 })
            .filter { seen.insert($0.id).inserted }
    }

    private func excerpt(from text: String, queryTokens: [String]) -> String {
        guard text.count > configuration.maximumSegmentExcerptCharacters else { return text }
        let firstMatch = queryTokens.lazy.compactMap { token in
            text.range(
                of: token,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: nil,
                locale: Self.normalizationLocale
            )
        }.first
        guard let firstMatch else {
            return String(text.prefix(configuration.maximumSegmentExcerptCharacters))
        }

        let matchedOffset = text.distance(from: text.startIndex, to: firstMatch.lowerBound)
        let maxStart = text.count - configuration.maximumSegmentExcerptCharacters
        let preferredStart = matchedOffset - (configuration.maximumSegmentExcerptCharacters / 2)
        let startOffset = min(max(0, preferredStart), maxStart)
        let start = text.index(text.startIndex, offsetBy: startOffset)
        let end = text.index(start, offsetBy: configuration.maximumSegmentExcerptCharacters)
        return String(text[start..<end])
    }

    private func uniqueTokens(in value: String) -> [String] {
        var seen = Set<String>()
        return tokens(in: normalize(value))
            .filter { !Self.ignoredQueryTokens.contains($0) }
            .filter { seen.insert($0).inserted }
    }

    private func tokens(in value: String) -> [String] {
        value.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    private func normalize(_ value: String) -> String {
        let folded = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Self.normalizationLocale)
            .lowercased(with: Self.normalizationLocale)
        return folded
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private enum TimelineEntry {
    case segment(RetrievedSegment)
    case gap(TranscriptGap)

    var timestamp: TimeInterval {
        switch self {
        case let .segment(segment): segment.segment.startTime
        case let .gap(gap): gap.timestamp
        }
    }

    var identifier: String {
        switch self {
        case let .segment(segment): segment.segment.id.uuidString
        case let .gap(gap): gap.id.uuidString
        }
    }

    var description: String {
        switch self {
        case let .segment(retrieved):
            let segment = retrieved.segment
            return "[Segment \(segment.id.uuidString) | \(format(segment.startTime))-\(format(segment.endTime))]\n\(retrieved.promptExcerpt)"
        case let .gap(gap):
            return "[Transcript gap \(gap.id.uuidString) | \(format(gap.timestamp)) | \(format(gap.duration))s | \(String(gap.reason.prefix(160)))]"
        }
    }

    static func isChronological(_ lhs: TimelineEntry, _ rhs: TimelineEntry) -> Bool {
        if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
        switch (lhs, rhs) {
        case (.gap, .segment): return true
        case (.segment, .gap): return false
        default: return lhs.identifier < rhs.identifier
        }
    }

    private func format(_ time: TimeInterval) -> String {
        let totalSeconds = max(0, Int(time.rounded(.down)))
        return String(format: "%02d:%02d:%02d", totalSeconds / 3_600, (totalSeconds % 3_600) / 60, totalSeconds % 60)
    }
}
