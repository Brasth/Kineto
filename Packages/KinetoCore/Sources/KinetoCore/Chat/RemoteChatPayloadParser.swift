import Foundation

/// Parses a remote model completion into a grounded chat payload.
/// Accepts a raw JSON object or a fenced ```json block. Never logs the text.
public enum RemoteChatPayloadParser {
    public struct DecodedCitation: Decodable, Sendable {
        public let segmentID: String
        public let quote: String
    }

    public struct DecodedPayload: Decodable, Sendable {
        public let answer: String
        public let citations: [DecodedCitation]
    }

    public static func parse(_ raw: String) throws -> MeetingChatGeneration {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = extractJSONObject(from: trimmed).data(using: .utf8) else {
            throw ChatGenerationError.invalidPayload
        }
        let decoded: DecodedPayload
        do {
            decoded = try JSONDecoder().decode(DecodedPayload.self, from: data)
        } catch {
            throw ChatGenerationError.invalidPayload
        }
        let citations = decoded.citations.compactMap { citation -> EvidenceReference? in
            guard let segmentID = UUID(uuidString: citation.segmentID) else { return nil }
            return EvidenceReference(segmentID: segmentID, supportingText: citation.quote)
        }
        return MeetingChatGeneration(answer: decoded.answer, citations: citations)
    }

    public static func extractJSONObject(from raw: String) -> String {
        let stripped = stripFence(raw)
        if let start = stripped.firstIndex(of: "{"),
           let end = stripped.lastIndex(of: "}"),
           start < end {
            return String(stripped[start...end])
        }
        return stripped
    }

    private static func stripFence(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            if let firstNewline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstNewline)...])
            }
            if text.hasSuffix("```") {
                text.removeLast(3)
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
