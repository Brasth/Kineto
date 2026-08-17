import Foundation

/// Builds a notes-first recap. User paragraphs stay verbatim and in order.
public actor MeetingRecapService {
    public static let transcriptCharacterBudget = 8_000

    private let validator: EvidenceValidator
    private let generator: any MeetingChatGenerating

    public init(
        generator: any MeetingChatGenerating,
        validator: EvidenceValidator = EvidenceValidator()
    ) {
        self.validator = validator
        self.generator = generator
    }

    public func enhance(
        snapshot: MeetingSnapshot,
        language: SpokenLanguage
    ) async -> MeetingRecapRecord? {
        guard snapshot.meeting.state == .stopped else { return nil }

        let paragraphs = snapshot.scratchpad.paragraphs
        let userBlocks = paragraphs.map { RecapBlock(kind: .user, text: $0, evidence: []) }
        let fills = await recapFills(from: snapshot, paragraphCount: paragraphs.count, language: language)
        let blocks = Self.interleave(userBlocks: userBlocks, fills: fills)
        guard !blocks.isEmpty else { return nil }

        return MeetingRecapRecord(
            meetingID: snapshot.meeting.id,
            language: language,
            scratchpadRevision: snapshot.scratchpad.revision,
            blocks: blocks,
            provider: generator.provider
        )
    }

    static func interleave(userBlocks: [RecapBlock], fills: [MeetingRecapFill]) -> [RecapBlock] {
        let slotCount = userBlocks.count + 1
        var slots = Array(repeating: [RecapBlock](), count: slotCount)
        for fill in fills {
            let slot = min(max(fill.afterParagraph, 0), userBlocks.count)
            slots[slot].append(RecapBlock(kind: .filled, text: fill.text, evidence: fill.citations))
        }
        var blocks: [RecapBlock] = []
        blocks.append(contentsOf: slots[0])
        for (index, user) in userBlocks.enumerated() {
            blocks.append(user)
            blocks.append(contentsOf: slots[index + 1])
        }
        return blocks
    }

    private func recapFills(
        from snapshot: MeetingSnapshot,
        paragraphCount: Int,
        language: SpokenLanguage
    ) async -> [MeetingRecapFill] {
        let finalSegments = snapshot.segments.filter(\.isFinal)
        guard !finalSegments.isEmpty else { return [] }

        switch generator.capability(for: language) {
        case .available:
            break
        case .unavailable, .unsupportedLocale, .providerDisconnected, .userDeniedEgress:
            return []
        }

        do {
            let generated = try await generator.generate(
                MeetingChatRequest(
                    prompt: Self.prompt(
                        notes: snapshot.scratchpad.body,
                        segments: finalSegments,
                        language: language
                    ),
                    language: language
                )
            )
            return groundedFills(
                from: generated,
                meetingID: snapshot.meeting.id,
                segments: finalSegments,
                paragraphCount: paragraphCount
            )
        } catch {
            return []
        }
    }

    func groundedFills(
        from generated: MeetingChatGeneration,
        meetingID: UUID,
        segments: [Segment],
        paragraphCount: Int
    ) -> [MeetingRecapFill] {
        let parsed = MeetingRecapPayloadParser.parseFills(from: generated.answer)
        if !parsed.isEmpty {
            return parsed.compactMap { fill in
                groundedFill(fill, fallbackCitations: generated.citations, meetingID: meetingID, segments: segments)
            }
        }
        return fallbackTrailingFill(
            answer: generated.answer,
            citations: generated.citations,
            meetingID: meetingID,
            segments: segments,
            paragraphCount: paragraphCount
        )
    }

    private func groundedFill(
        _ fill: MeetingRecapFill,
        fallbackCitations: [EvidenceReference],
        meetingID: UUID,
        segments: [Segment]
    ) -> MeetingRecapFill? {
        let text = fill.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let preferred = fill.citations.isEmpty
            ? fallbackCitations.filter { text.range(of: $0.supportingText) != nil }
            : fill.citations
        let source = preferred.isEmpty ? fallbackCitations : preferred
        guard let validated = try? validator.validateChatCitations(
            source,
            meetingID: meetingID,
            retrievedSegments: segments
        ), !validated.isEmpty else {
            return nil
        }
        return MeetingRecapFill(afterParagraph: fill.afterParagraph, text: text, citations: validated)
    }

    private func fallbackTrailingFill(
        answer: String,
        citations: [EvidenceReference],
        meetingID: UUID,
        segments: [Segment],
        paragraphCount: Int
    ) -> [MeetingRecapFill] {
        let validated = (try? validator.validateChatCitations(
            citations,
            meetingID: meetingID,
            retrievedSegments: segments
        )) ?? []
        guard !validated.isEmpty else { return [] }
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        let display = trimmed.isEmpty || trimmed.hasPrefix("{")
            ? validated.map(\.supportingText).joined(separator: " ")
            : trimmed
        guard !display.isEmpty else { return [] }
        return [MeetingRecapFill(afterParagraph: paragraphCount, text: display, citations: validated)]
    }

    static func prompt(
        notes: String,
        segments: [Segment],
        language: SpokenLanguage
    ) -> String {
        let transcript = transcriptPrompt(from: segments)
        let paragraphs = MeetingScratchpad(body: notes, updatedAt: Date(timeIntervalSince1970: 0)).paragraphs
        let languageHint = language.isVietnamese
            ? "Write fill text in Vietnamese."
            : "Write fill text in English."

        if paragraphs.isEmpty {
            return """
            Draft concise meeting notes from the transcript excerpts only.
            Do not invent owners, dates, or commitments that are not written below.
            \(languageHint)
            Put every note in fills with afterParagraph 0, in chronological order.
            Every fill citation must use a supplied segment UUID and an exact contiguous quote.

            Reply with JSON only:
            {"fills":[{"afterParagraph":0,"text":"...","citations":[{"segmentID":"<uuid>","quote":"<exact excerpt span>"}]}]}

            Transcript excerpts:
            \(transcript)
            """
        }

        let numbered = paragraphs.enumerated().map { index, text in
            "[\(index + 1)] \(text)"
        }.joined(separator: "\n")

        return """
        The operator's handwritten notes are the source of truth. Do not repeat or rewrite them.
        Insert only omitted transcript facts as fills between those notes.
        afterParagraph 0 means before note [1]. afterParagraph N means immediately after note [N].
        \(languageHint)
        Every fill citation must use a supplied segment UUID and an exact contiguous quote.

        Reply with JSON only:
        {"fills":[{"afterParagraph":1,"text":"...","citations":[{"segmentID":"<uuid>","quote":"<exact excerpt span>"}]}]}

        Operator notes:
        \(numbered)

        Transcript excerpts:
        \(transcript)
        """
    }

    static func transcriptPrompt(from segments: [Segment]) -> String {
        var used = 0
        var lines: [String] = []
        for segment in segments where segment.isFinal {
            let speaker = segment.source == .you ? "You" : "Selected Source"
            let line = "[\(segment.id.uuidString)] \(speaker): \(segment.text)"
            if used + line.count > transcriptCharacterBudget { break }
            lines.append(line)
            used += line.count
        }
        return lines.joined(separator: "\n")
    }
}
