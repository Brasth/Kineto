import XCTest
@testable import Kineto

final class SignalGatePresentationTests: XCTestCase {
    func testEachPhaseHasExpectedVisibilityAndActions() {
        let pauseResumeStopAndShowDetails: Set<SignalGateAction> = [
            .pauseOrResume,
            .stop,
            .showMeetingDetails,
        ]
        let showDetailsOnly: Set<SignalGateAction> = [.showMeetingDetails]
        let expectations: [(SignalGatePhase, Bool, Set<SignalGateAction>)] = [
            (.hidden, false, []),
            (.capturing, true, pauseResumeStopAndShowDetails),
            (.paused, true, pauseResumeStopAndShowDetails),
            (.draining, true, showDetailsOnly),
            (.processing, true, showDetailsOnly),
        ]

        for (phase, expectedVisibility, expectedActions) in expectations {
            let presentation = SignalGatePresentation(phase: phase)

            XCTAssertEqual(presentation.phase, phase)
            XCTAssertEqual(presentation.isVisible, expectedVisibility, "Unexpected visibility for \(phase)")
            XCTAssertEqual(presentation.availableActions, expectedActions, "Unexpected actions for \(phase)")

            for action in [SignalGateAction.pauseOrResume, .stop, .showMeetingDetails] {
                XCTAssertEqual(
                    presentation.isActionAvailable(action),
                    expectedActions.contains(action),
                    "Unexpected availability for \(action) in \(phase)"
                )
            }
        }
    }
}
