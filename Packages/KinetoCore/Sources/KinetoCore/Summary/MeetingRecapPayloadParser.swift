import Foundation

public struct MeetingRecapFill: Sendable, Equatable {
    public let afterParagraph: Int
    public let text: String
    public let citations: [EvidenceReference]

    public init(afterParagraph: Int, text: String, citations: [EvidenceReference]) {
        self.afterParagraph = afterParagraph
        self.text = text
        self.citations = citations
    }
}

public enum MeetingRecapPayloadParser {
    private struct DecodedCitation: Decodable {
        let segmentID: String
        let quote: String
    }

    private struct DecodedFill: Decodable {
        let afterParagraph: Int?
        let after_paragraph: Int?
        let text: String
        let citations: [DecodedCitation]?

        var resolvedAfterParagraph: Int {
            afterParagraph ?? after_paragraph ?? 0
        }
    }

    private struct DecodedFills: Decodable {
        let fills: [DecodedFill]
    }

    public static func parseFills(from answer: String) -> [MeetingRecapFill] {
        let candidates = [
            RemoteChatPayloadParser.extractJSONObject(from: answer),
            answer
        ]
        for candidate in candidates {
            if let fills = decodeFills(from: candidate), !fills.isEmpty {
                return fills
            }
        }
        return parseMarkers(from: answer)
    }

    private static func decodeFills(from raw: String) -> [MeetingRecapFill]? {
        guard let data = raw.data(using: .utf8) else { return nil }
        if let payload = try? JSONDecoder().decode(DecodedFills.self, from: data) {
            return payload.fills.compactMap(makeFill)
        }
        return nil
    }

    private static func makeFill(_ decoded: DecodedFill) -> MeetingRecapFill? {
        let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let citations = (decoded.citations ?? []).compactMap { citation -> EvidenceReference? in
            guard let id = UUID(uuidString: citation.segmentID) else { return nil }
            let quote = citation.quote.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !quote.isEmpty else { return nil }
            return EvidenceReference(segmentID: id, supportingText: quote)
        }
        return MeetingRecapFill(
            afterParagraph: max(0, decoded.resolvedAfterParagraph),
            text: text,
            citations: citations
        )
    }

    private static func parseMarkers(from answer: String) -> [MeetingRecapFill] {
        let pattern = #"<<FILL after=(\d+)>>\s*(.+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = answer as NSString
        return regex.matches(in: answer, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard match.numberOfRanges == 3,
                  let after = Int(ns.substring(with: match.range(at: 1))) else {
                return nil
            }
            let text = ns.substring(with: match.range(at: 2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return MeetingRecapFill(afterParagraph: after, text: text, citations: [])
        }
    }
}
