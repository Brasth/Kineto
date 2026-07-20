import XCTest
import AppKit
import KinetoCore
@testable import Kineto

final class FloatingCaptionPresentationTests: XCTestCase {
    func testPresentationKeepsFirstFourLinesInInputOrder() {
        let lines = [
            FloatingCaptionLine(
                id: "selected-1",
                sourceLabel: "Selected Source",
                text: "First selected-source caption.",
                isVolatile: true
            ),
            FloatingCaptionLine(
                id: "you-1",
                sourceLabel: "You",
                text: "Second caption from you.",
                translation: "Deuxième légende de vous.",
                isVolatile: false
            ),
            FloatingCaptionLine(
                id: "selected-2",
                sourceLabel: "Selected Source",
                text: "Third selected-source caption.",
                isVolatile: false
            ),
            FloatingCaptionLine(
                id: "you-2",
                sourceLabel: "You",
                text: "Fourth caption from you.",
                isVolatile: false
            ),
            FloatingCaptionLine(
                id: "selected-3",
                sourceLabel: "Selected Source",
                text: "Fifth caption must not be displayed.",
                isVolatile: false
            ),
        ]

        let presentation = FloatingCaptionPresentation(isVisible: true, lines: lines)

        XCTAssertTrue(presentation.isVisible)
        XCTAssertEqual(presentation.lines, Array(lines.prefix(4)))
        XCTAssertEqual(presentation.lines.map(\.id), ["selected-1", "you-1", "selected-2", "you-2"])
        XCTAssertEqual(presentation.lines.count, 4)
        XCTAssertFalse(presentation.lines.contains(where: { $0.id == "selected-3" }))
    }

    func testPresentationPreservesPetStateAndDefaultsToHidden() {
        let defaultPresentation = FloatingCaptionPresentation(isVisible: true, lines: [])
        let listeningPresentation = FloatingCaptionPresentation(
            isVisible: true,
            lines: [],
            petState: .listening
        )

        XCTAssertEqual(defaultPresentation.petState, .hidden)
        XCTAssertEqual(listeningPresentation.petState, .listening)
    }

    func testPetPanelDragEligibilityMatchesEveryPetState() {
        XCTAssertFalse(FloatingCaptionPetState.hidden.isPanelDragEligible)
        XCTAssertTrue(FloatingCaptionPetState.listening.isPanelDragEligible)
        XCTAssertTrue(FloatingCaptionPetState.settled.isPanelDragEligible)
    }

    @MainActor
    func testDragSessionStartsInactive() {
        let session = FloatingCaptionDragSession()

        XCTAssertNil(session.source)
        XCTAssertFalse(session.isActive)
        XCTAssertFalse(session.shouldSuppressCaption)
    }

    @MainActor
    func testDragSessionCompanionSourceSuppressesCaption() {
        let session = FloatingCaptionDragSession()

        session.begin(.companion)

        guard case .companion? = session.source else {
            return XCTFail("Companion drag should become the active source.")
        }
        XCTAssertTrue(session.isActive)
        XCTAssertTrue(session.shouldSuppressCaption)
    }

    @MainActor
    func testDragSessionHeaderSourceDoesNotSuppressCaption() {
        let session = FloatingCaptionDragSession()

        session.begin(.captionHeader)

        guard case .captionHeader? = session.source else {
            return XCTFail("Caption header drag should become the active source.")
        }
        XCTAssertTrue(session.isActive)
        XCTAssertFalse(session.shouldSuppressCaption)
    }

    @MainActor
    func testDragSessionKeepsItsInitialSourceUntilEnded() {
        let session = FloatingCaptionDragSession()

        session.begin(.captionHeader)
        session.begin(.companion)

        guard case .captionHeader? = session.source else {
            return XCTFail("A second drag source must not replace the active caption header drag.")
        }
        XCTAssertTrue(session.isActive)
        XCTAssertFalse(session.shouldSuppressCaption)
    }

    @MainActor
    func testDragSessionEndRestoresNormalState() {
        let session = FloatingCaptionDragSession()
        session.begin(.companion)

        session.end()

        XCTAssertNil(session.source)
        XCTAssertFalse(session.isActive)
        XCTAssertFalse(session.shouldSuppressCaption)
    }

    @MainActor
    func testDragSessionResetClearsAnActiveCompanionState() {
        let session = FloatingCaptionDragSession()
        session.begin(.companion)

        session.reset()

        XCTAssertNil(session.source)
        XCTAssertFalse(session.isActive)
        XCTAssertFalse(session.shouldSuppressCaption)
    }

    func testHiddenPresentationIsInvisibleAndHasNoLines() {
        let presentation = FloatingCaptionPresentation.hidden

        XCTAssertFalse(presentation.isVisible)
        XCTAssertTrue(presentation.lines.isEmpty)
        XCTAssertEqual(presentation.petState, .hidden)
    }

    func testLiveOverlayProjectsCapturingSignalGateActions() {
        let gatePresentation = SignalGatePresentation(phase: .capturing)
        let presentation = FloatingCaptionOverlayPresentation(
            caption: .live(
                segments: [],
                translations: [],
                volatileTranscripts: [],
                petModeEnabled: false
            ),
            petVisualPreferences: .default,
            signalGatePresentation: gatePresentation
        )

        XCTAssertTrue(presentation.isVisible)
        XCTAssertEqual(presentation.signalGatePresentation, gatePresentation)
        XCTAssertEqual(
            presentation.signalGatePresentation.availableActions,
            [.pauseOrResume, .stop, .showMeetingDetails]
        )
    }
    func testLiveOverlaySuppressesNonCapturingSignalGateActions() {
        let caption = FloatingCaptionPresentation.live(
            segments: [],
            translations: [],
            volatileTranscripts: [],
            petModeEnabled: false
        )

        for phase in [SignalGatePhase.hidden, .paused, .draining, .processing] {
            let presentation = FloatingCaptionOverlayPresentation(
                caption: caption,
                petVisualPreferences: .default,
                signalGatePresentation: SignalGatePresentation(phase: phase)
            )

            XCTAssertTrue(presentation.isVisible, "Expected a live caption input for \(phase)")
            XCTAssertEqual(presentation.signalGatePresentation.phase, .hidden)
            XCTAssertTrue(presentation.signalGatePresentation.availableActions.isEmpty)
            XCTAssertFalse(presentation.signalGatePresentation.isActionAvailable(.pauseOrResume))
            XCTAssertFalse(presentation.signalGatePresentation.isActionAvailable(.stop))
            XCTAssertFalse(presentation.signalGatePresentation.isActionAvailable(.showMeetingDetails))
        }
    }

    func testHiddenOverlaySuppressesGateActionsForEveryPhase() {
        for phase in [SignalGatePhase.hidden, .capturing, .paused, .draining, .processing] {
            let presentation = FloatingCaptionOverlayPresentation(
                caption: .hidden,
                petVisualPreferences: .default,
                signalGatePresentation: SignalGatePresentation(phase: phase)
            )

            XCTAssertFalse(presentation.isVisible, "Unexpected overlay visibility for \(phase)")
            XCTAssertEqual(presentation.signalGatePresentation.phase, .hidden)
            XCTAssertTrue(presentation.signalGatePresentation.availableActions.isEmpty)
            XCTAssertFalse(
                presentation.signalGatePresentation.isActionAvailable(.pauseOrResume),
                "A hidden overlay must not expose Resume for \(phase)"
            )
        }
    }

    func testLivePresentationUsesFourNewestFinalSegmentsChronologicallyAndExactTranslations() {
        let meetingID = UUID()
        let segmentIDs = (1...5).map { _ in UUID() }
        let segments = segmentIDs.enumerated().map { index, id in
            Segment(
                id: id,
                meetingID: meetingID,
                source: index.isMultiple(of: 2) ? .selectedSource : .you,
                startTime: TimeInterval(index),
                endTime: TimeInterval(index + 1),
                language: .english,
                text: "Final \(index + 1)",
                isFinal: true
            )
        }
        let translation = TranslationRecord(
            sourceSegmentID: segmentIDs[4],
            sourceLanguage: .english,
            targetLanguage: .vietnamese,
            text: "Translated final five"
        )
        let unrelatedTranslation = TranslationRecord(
            sourceSegmentID: UUID(),
            sourceLanguage: .english,
            targetLanguage: .vietnamese,
            text: "Must not be associated"
        )

        let presentation = FloatingCaptionPresentation.live(
            segments: segments,
            translations: [unrelatedTranslation, translation],
            volatileTranscripts: [],
            petModeEnabled: false
        )

        XCTAssertTrue(presentation.isVisible)
        XCTAssertEqual(presentation.header.captureStatus, .capturing)
        XCTAssertNil(presentation.activeLineID)
        XCTAssertEqual(
            presentation.lines.map(\.id),
            segmentIDs.dropFirst().map(\.uuidString)
        )
        XCTAssertEqual(presentation.lines.last?.translation, "Translated final five")
        XCTAssertFalse(presentation.lines.dropLast().contains(where: { $0.translation != nil }))
    }

    func testLivePresentationReservesBottomSlotForVolatileEvenWhenFinalIsLater() {
        let meetingID = UUID()
        let earlyFinal = Segment(
            meetingID: meetingID,
            source: .selectedSource,
            startTime: 1,
            endTime: 2,
            language: .english,
            text: "Early final",
            isFinal: true
        )
        let laterFinal = Segment(
            meetingID: meetingID,
            source: .you,
            startTime: 20,
            endTime: 21,
            language: .english,
            text: "Later final",
            isFinal: true
        )
        let activeVolatile = VolatileTranscript(
            id: "active-volatile",
            source: .you,
            text: "Still speaking",
            startTime: 8,
            endTime: 9,
            language: .english
        )

        let presentation = FloatingCaptionPresentation.live(
            segments: [earlyFinal, laterFinal],
            translations: [],
            volatileTranscripts: [activeVolatile],
            petModeEnabled: true
        )

        XCTAssertEqual(
            presentation.lines.map(\.id),
            [earlyFinal.id.uuidString, laterFinal.id.uuidString, activeVolatile.id]
        )
        XCTAssertEqual(presentation.activeLineID, activeVolatile.id)
        XCTAssertEqual(presentation.lines.last?.id, activeVolatile.id)
        XCTAssertEqual(presentation.petState, .settled)
    }

    func testLivePetStateIsIndependentOfVolatileTranscriptPresence() {
        let volatileTranscript = VolatileTranscript(
            id: "volatile-state-independence",
            source: .selectedSource,
            text: "Transcript content must not affect pet state",
            startTime: 1,
            endTime: 2,
            language: .english
        )

        let withoutVolatileTranscript = FloatingCaptionPresentation.live(
            segments: [],
            translations: [],
            volatileTranscripts: [],
            petModeEnabled: true
        )
        let withVolatileTranscript = FloatingCaptionPresentation.live(
            segments: [],
            translations: [],
            volatileTranscripts: [volatileTranscript],
            petModeEnabled: true
        )

        XCTAssertEqual(withoutVolatileTranscript.petState, .settled)
        XCTAssertEqual(withVolatileTranscript.petState, .settled)
        XCTAssertEqual(withoutVolatileTranscript.petState, withVolatileTranscript.petState)
    }

    func testLivePresentationOrdersInactiveCandidatesByTotalKeyAndAppendsActiveVolatile() {
        let meetingID = UUID()
        let excludedOldFinal = Segment(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            meetingID: meetingID,
            source: .selectedSource,
            startTime: 3,
            endTime: 4,
            language: .english,
            text: "Excluded old final",
            isFinal: true
        )
        let finalTieLow = Segment(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            meetingID: meetingID,
            source: .selectedSource,
            startTime: 4,
            endTime: 5,
            language: .english,
            text: "Final tie low",
            isFinal: true
        )
        let finalTieHigh = Segment(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            meetingID: meetingID,
            source: .you,
            startTime: 4,
            endTime: 5,
            language: .english,
            text: "Final tie high",
            isFinal: true
        )
        let inactiveVolatile = VolatileTranscript(
            id: "volatile-tie",
            source: .you,
            text: "Earlier volatile",
            startTime: 4,
            endTime: 5,
            language: .english
        )
        let activeVolatile = VolatileTranscript(
            id: "volatile-active",
            source: .selectedSource,
            text: "Latest volatile",
            startTime: 5,
            endTime: 6,
            language: .english
        )

        let presentation = FloatingCaptionPresentation.live(
            segments: [excludedOldFinal, finalTieLow, finalTieHigh],
            translations: [],
            volatileTranscripts: [inactiveVolatile, activeVolatile],
            petModeEnabled: false
        )

        XCTAssertEqual(
            presentation.lines.map(\.id),
            [
                finalTieLow.id.uuidString,
                finalTieHigh.id.uuidString,
                inactiveVolatile.id,
                activeVolatile.id
            ]
        )
        XCTAssertFalse(presentation.lines.contains(where: { $0.id == excludedOldFinal.id.uuidString }))
        XCTAssertEqual(presentation.activeLineID, activeVolatile.id)
    }

    func testLivePresentationKeepsNonactiveVolatilesInChronologicalHistory() {
        let meetingID = UUID()
        let finalSegments = (1...4).map { index in
            Segment(
                meetingID: meetingID,
                source: .selectedSource,
                startTime: TimeInterval(index),
                endTime: TimeInterval(index + 1),
                language: .english,
                text: "Final \(index)",
                isFinal: true
            )
        }
        let activeVolatile = VolatileTranscript(
            id: "volatile-selected-source",
            source: .selectedSource,
            text: "Selected source is speaking",
            startTime: 11,
            endTime: 12,
            language: .english
        )
        let inactiveVolatile = VolatileTranscript(
            id: "volatile-you",
            source: .you,
            text: "You are speaking",
            startTime: 10,
            endTime: 11,
            language: .english
        )

        let presentation = FloatingCaptionPresentation.live(
            segments: finalSegments,
            translations: [],
            volatileTranscripts: [inactiveVolatile, activeVolatile],
            petModeEnabled: false
        )

        XCTAssertEqual(
            presentation.lines.map(\.id),
            [
                finalSegments[2].id.uuidString,
                finalSegments[3].id.uuidString,
                inactiveVolatile.id,
                activeVolatile.id
            ]
        )
        XCTAssertEqual(presentation.activeLineID, activeVolatile.id)
        XCTAssertTrue(presentation.lines.dropLast().contains(where: { $0.id == inactiveVolatile.id }))
        XCTAssertEqual(presentation.lines.count, FloatingCaptionPresentation.maximumLineCount)
    }

    func testLivePresentationUsesStableIDForSimultaneousVolatileActiveTie() {
        let earlierVolatile = VolatileTranscript(
            id: "volatile-a",
            source: .you,
            text: "Earlier stable ID",
            startTime: 10,
            endTime: 11,
            language: .english
        )
        let laterVolatile = VolatileTranscript(
            id: "volatile-z",
            source: .selectedSource,
            text: "Later stable ID",
            startTime: 10,
            endTime: 11,
            language: .english
        )

        let presentation = FloatingCaptionPresentation.live(
            segments: [],
            translations: [],
            volatileTranscripts: [laterVolatile, earlierVolatile],
            petModeEnabled: false
        )

        XCTAssertEqual(presentation.lines.map(\.id), [earlierVolatile.id, laterVolatile.id])
        XCTAssertEqual(presentation.activeLineID, laterVolatile.id)
        XCTAssertEqual(presentation.lines.last?.id, laterVolatile.id)
    }

    func testPlacementNormalizesPersistsAndClampsForChangedPanelSize() {
        let defaults = UserDefaults(suiteName: "FloatingCaptionPresentationTests")!
        defaults.removeObject(forKey: FloatingCaptionPanelPlacement.defaultsKey)
        let frame = CGRect(x: 10, y: 20, width: 1_000, height: 600)
        let placement = FloatingCaptionPanelPlacement.placement(
            for: CGPoint(x: 710, y: 520),
            visibleFrame: frame,
            panelSize: CGSize(width: 300, height: 100)
        )
        placement.persist(for: 42, defaults: defaults)

        XCTAssertEqual(FloatingCaptionPanelPlacement.restore(for: 42, defaults: defaults), placement)
        XCTAssertEqual(
            placement.origin(visibleFrame: frame, panelSize: CGSize(width: 400, height: 200)),
            CGPoint(x: 610, y: 420)
        )
        defaults.set(["42": ["horizontal": "bad", "vertical": 0]], forKey: FloatingCaptionPanelPlacement.defaultsKey)
        XCTAssertNil(FloatingCaptionPanelPlacement.restore(for: 42, defaults: defaults))
        XCTAssertEqual(
            FloatingCaptionPanelPlacement.fallback(
                visibleFrame: frame,
                panelSize: CGSize(width: 300, height: 100)
            ),
            CGPoint(x: 360, y: 60)
        )
    }

    func testLinkedPlacementKeepsCompanionCenteredAndOnScreen() {
        let visibleFrame = CGRect(x: 10, y: 20, width: 1_000, height: 600)
        let captionSize = CGSize(width: 576, height: 68)
        let companionSize = CGSize(width: 52, height: 52)
        let verticalGap: CGFloat = 8
        let linkedSize = FloatingCaptionPanelPlacement.linkedSize(
            captionSize: captionSize,
            companionSize: companionSize,
            verticalGap: verticalGap
        )
        let captionOrigin = FloatingCaptionPanelPlacement.clamp(
            origin: CGPoint(x: 710, y: 520),
            visibleFrame: visibleFrame,
            panelSize: linkedSize
        )
        let linkedFootprint = CGRect(origin: captionOrigin, size: linkedSize)
        let companionOrigin = FloatingCaptionPanelPlacement.companionOrigin(
            captionFrame: CGRect(origin: captionOrigin, size: captionSize),
            companionSize: companionSize,
            verticalGap: verticalGap
        )

        XCTAssertEqual(linkedSize, CGSize(width: 576, height: 128))
        XCTAssertEqual(captionOrigin, CGPoint(x: 434, y: 492))
        XCTAssertGreaterThanOrEqual(linkedFootprint.minX, visibleFrame.minX)
        XCTAssertGreaterThanOrEqual(linkedFootprint.minY, visibleFrame.minY)
        XCTAssertLessThanOrEqual(linkedFootprint.maxX, visibleFrame.maxX)
        XCTAssertLessThanOrEqual(linkedFootprint.maxY, visibleFrame.maxY)
        XCTAssertEqual(companionOrigin, CGPoint(x: 696, y: 568))
        XCTAssertEqual(
            FloatingCaptionPanelPlacement.captionOrigin(
                companionOrigin: companionOrigin,
                captionSize: captionSize,
                companionSize: companionSize,
                verticalGap: verticalGap
            ),
            captionOrigin
        )
    }

    func testPetLedPlacementDerivesCaptionOriginFromCompanionOrigin() {
        let captionSize = CGSize(width: 300, height: 100)
        let companionSize = CGSize(width: 52, height: 52)
        let companionOrigin = CGPoint(x: 484, y: 168)

        let captionOrigin = FloatingCaptionPanelPlacement.captionOrigin(
            companionOrigin: companionOrigin,
            captionSize: captionSize,
            companionSize: companionSize,
            verticalGap: 8
        )

        XCTAssertEqual(captionOrigin, CGPoint(x: 360, y: 60))
        XCTAssertEqual(
            FloatingCaptionPanelPlacement.companionOrigin(
                captionFrame: CGRect(origin: captionOrigin, size: captionSize),
                companionSize: companionSize,
                verticalGap: 8
            ),
            companionOrigin
        )
    }

    func testPetLedPlacementPreservesFractionalOrigins() {
        let captionSize = CGSize(width: 300, height: 100)
        let companionSize = CGSize(width: 52, height: 52)
        let captionOrigin = CGPoint(x: 360.5, y: 60.25)
        let companionOrigin = FloatingCaptionPanelPlacement.companionOrigin(
            captionFrame: CGRect(origin: captionOrigin, size: captionSize),
            companionSize: companionSize,
            verticalGap: 8
        )

        XCTAssertEqual(companionOrigin, CGPoint(x: 484.5, y: 168.25))
        XCTAssertEqual(
            FloatingCaptionPanelPlacement.captionOrigin(
                companionOrigin: companionOrigin,
                captionSize: captionSize,
                companionSize: companionSize,
                verticalGap: 8
            ),
            captionOrigin
        )
    }

    func testActiveCaptureHeaderIsVisibleWithNoCaptions() {
        let presentation = FloatingCaptionPresentation.live(
            segments: [],
            translations: [],
            volatileTranscripts: [],
            petModeEnabled: false
        )

        XCTAssertTrue(presentation.isVisible)
        XCTAssertTrue(presentation.lines.isEmpty)
        XCTAssertEqual(presentation.header.captureStatus, .capturing)
    }
}
