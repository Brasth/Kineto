import XCTest
@testable import Kineto

final class SignalGatePrivacyTests: XCTestCase {
    func testVisiblePhasesExposeOnlyGenericOperationalAccessibilityText() {
        let sensitiveSamples = [
            "Zoom — Design Review",
            "Quarterly Planning Meeting",
            "The launch date should remain confidential.",
            "01:23:45"
        ]

        let expectedAccessibilityValues: [(SignalGatePhase, String)] = [
            (.capturing, "Capturing"),
            (.paused, "Paused"),
            (.draining, "Finalizing capture"),
            (.processing, "Processing")
        ]

        for (phase, expectedValue) in expectedAccessibilityValues {
            let presentation = SignalGatePresentation(phase: phase)

            XCTAssertTrue(presentation.isVisible, "\(phase) should be visible")
            XCTAssertEqual(presentation.accessibilityValue, expectedValue)

            for sensitiveSample in sensitiveSamples {
                XCTAssertFalse(
                    presentation.accessibilityValue.localizedCaseInsensitiveContains(sensitiveSample),
                    "\(phase) must not expose sensitive session data"
                )
            }
        }
    }

    func testPausedDrainingAndProcessingDoNotClaimActiveCapture() {
        for phase in [SignalGatePhase.paused, .draining, .processing] {
            let presentation = SignalGatePresentation(phase: phase)

            XCTAssertFalse(
                presentation.accessibilityValue.localizedCaseInsensitiveContains("capturing"),
                "\(phase) must not claim active capture"
            )
        }
    }
    func testHiddenPhaseHasNoAccessibilityValueOrCaptureClaim() {
        let presentation = SignalGatePresentation(phase: .hidden)

        XCTAssertFalse(presentation.isVisible)
        XCTAssertEqual(presentation.accessibilityValue, "")
        XCTAssertFalse(presentation.accessibilityValue.localizedCaseInsensitiveContains("capturing"))
    }

}
