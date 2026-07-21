import Foundation
import KinetoCore

struct FloatingCaptionLine: Identifiable, Equatable, Sendable {
    let id: String
    let sourceLabel: String
    let text: String
    let translation: String?
    let isVolatile: Bool

    init(
        id: String,
        sourceLabel: String,
        text: String,
        translation: String? = nil,
        isVolatile: Bool
    ) {
        precondition(sourceLabel == "Selected Source" || sourceLabel == "You")
        self.id = id
        self.sourceLabel = sourceLabel
        self.text = text
        self.translation = translation
        self.isVolatile = isVolatile
    }
}

enum FloatingCaptionPetState: Equatable, Sendable {
    case hidden
    case settled
}

enum FloatingCaptionCaptureStatus: Equatable, Sendable {
    case idle
    case capturing

    var title: String {
        switch self {
        case .idle:
            "Capture ready"
        case .capturing:
            "Capturing"
        }
    }

    var symbolName: String {
        switch self {
        case .idle:
            "record.circle"
        case .capturing:
            "record.circle.fill"
        }
    }
}


struct FloatingCaptionHeaderPresentation: Equatable, Sendable {
    let captureStatus: FloatingCaptionCaptureStatus

    init(captureStatus: FloatingCaptionCaptureStatus = .idle) {
        self.captureStatus = captureStatus
    }

    static let `default` = FloatingCaptionHeaderPresentation()
}


private enum FloatingCaptionCandidate {
    case finalized(Segment)
    case volatile(VolatileTranscript)

    var endTime: TimeInterval {
        switch self {
        case let .finalized(segment): segment.endTime
        case let .volatile(transcript): transcript.endTime
        }
    }

    var typeRank: Int {
        switch self {
        case .finalized: 0
        case .volatile: 1
        }
    }

    var stableID: String {
        switch self {
        case let .finalized(segment): segment.id.uuidString
        case let .volatile(transcript): transcript.id
        }
    }

    var isVolatile: Bool {
        if case .volatile = self { return true }
        return false
    }
}

struct FloatingCaptionPresentation: Equatable, Sendable {
    static let maximumLineCount = 4
    let isVisible: Bool
    let lines: [FloatingCaptionLine]
    let activeLineID: String?
    let petState: FloatingCaptionPetState
    let header: FloatingCaptionHeaderPresentation

    init(
        isVisible: Bool,
        lines: [FloatingCaptionLine],
        activeLineID: String? = nil,
        petState: FloatingCaptionPetState = .hidden,
        header: FloatingCaptionHeaderPresentation = .default
    ) {
        self.isVisible = isVisible
        self.lines = Array(lines.prefix(Self.maximumLineCount))
        self.activeLineID = activeLineID
        self.petState = petState
        self.header = header
    }

    static let hidden = FloatingCaptionPresentation(isVisible: false, lines: [])
}

extension FloatingCaptionPresentation {
    static func live(
        segments: [Segment],
        translations: [TranslationRecord],
        volatileTranscripts: [VolatileTranscript],
        petModeEnabled: Bool
    ) -> Self {
        let volatileCandidates = volatileTranscripts
            .filter { !$0.text.isEmpty }
            .map(FloatingCaptionCandidate.volatile)
        let finalCandidates = segments
            .filter(\.isFinal)
            .map(FloatingCaptionCandidate.finalized)
        let candidates = volatileCandidates + finalCandidates

        let selectedCandidates: [FloatingCaptionCandidate]
        let activeCandidate: FloatingCaptionCandidate?
        if let activeVolatile = volatileCandidates.sorted(by: isMoreRecent).first {
            activeCandidate = activeVolatile
            let inactive = candidates
                .filter { !isSameCandidate($0, activeVolatile) }
                .sorted(by: isMoreRecent)
                .prefix(maximumLineCount - 1)
                .sorted(by: isLessRecent)
            selectedCandidates = inactive + [activeVolatile]
        } else {
            activeCandidate = nil
            selectedCandidates = finalCandidates
                .sorted(by: isMoreRecent)
                .prefix(maximumLineCount)
                .sorted(by: isLessRecent)
        }
        let petState: FloatingCaptionPetState = petModeEnabled ? .settled : .hidden

        return Self(
            isVisible: true,
            lines: selectedCandidates.map { line(for: $0, translations: translations) },
            activeLineID: activeCandidate?.stableID,
            petState: petState,
            header: FloatingCaptionHeaderPresentation(captureStatus: .capturing)
        )
    }

    private static func isMoreRecent(
        _ lhs: FloatingCaptionCandidate,
        _ rhs: FloatingCaptionCandidate
    ) -> Bool {
        if lhs.endTime != rhs.endTime { return lhs.endTime > rhs.endTime }
        if lhs.typeRank != rhs.typeRank { return lhs.typeRank > rhs.typeRank }
        return lhs.stableID > rhs.stableID
    }

    private static func isLessRecent(
        _ lhs: FloatingCaptionCandidate,
        _ rhs: FloatingCaptionCandidate
    ) -> Bool {
        if lhs.endTime != rhs.endTime { return lhs.endTime < rhs.endTime }
        if lhs.typeRank != rhs.typeRank { return lhs.typeRank < rhs.typeRank }
        return lhs.stableID < rhs.stableID
    }

    private static func isSameCandidate(
        _ lhs: FloatingCaptionCandidate,
        _ rhs: FloatingCaptionCandidate
    ) -> Bool {
        lhs.typeRank == rhs.typeRank && lhs.stableID == rhs.stableID && lhs.endTime == rhs.endTime
    }

    private static func line(
        for candidate: FloatingCaptionCandidate,
        translations: [TranslationRecord]
    ) -> FloatingCaptionLine {
        switch candidate {
        case let .finalized(segment):
            FloatingCaptionLine(
                id: segment.id.uuidString,
                sourceLabel: label(for: segment.source),
                text: segment.text,
                translation: translations.first(where: {
                    $0.sourceSegmentID == segment.id
                })?.text,
                isVolatile: false
            )
        case let .volatile(transcript):
            FloatingCaptionLine(
                id: transcript.id,
                sourceLabel: label(for: transcript.source),
                text: transcript.text,
                isVolatile: true
            )
        }
    }

    private static func label(for source: AudioSource) -> String {
        source == .selectedSource ? "Selected Source" : "You"
    }
}
