import XCTest
@testable import Kineto

final class ReviewPresentationPolicyTests: XCTestCase {
    func testCompactThresholdClassifiesWidthsAtTheBoundary() {
        let threshold = ReviewPresentationPolicy.compactPresentationThreshold
        let expectations = [
            (width: threshold - 0.5, isCompact: true),
            (width: threshold, isCompact: false),
        ]

        for expectation in expectations {
            XCTAssertEqual(
                ReviewPresentationPolicy.isCompact(outerWidth: expectation.width),
                expectation.isCompact,
                "Unexpected presentation mode at width \(expectation.width)"
            )
        }
    }

    func testWorkspaceOptionsMatchPresentationMode() {
        let expectations: [(isCompact: Bool, options: [ReviewPresentationPolicy.Workspace])] = [
            (isCompact: false, options: [.summary, .ask]),
            (isCompact: true, options: [.transcript, .summary, .ask]),
        ]

        for expectation in expectations {
            XCTAssertEqual(
                ReviewPresentationPolicy.workspaceOptions(isCompact: expectation.isCompact),
                expectation.options,
                "Unexpected workspace options for compact=\(expectation.isCompact)"
            )
        }
    }

    func testDisplayedWorkspaceKeepsCanonicalTranscriptCompactOnly() {
        let expectations: [
            (isCompact: Bool, selection: ReviewPresentationPolicy.Workspace, displayed: ReviewPresentationPolicy.Workspace)
        ] = [
            (isCompact: false, selection: .transcript, displayed: .summary),
            (isCompact: true, selection: .transcript, displayed: .transcript),
            (isCompact: false, selection: .ask, displayed: .ask),
            (isCompact: true, selection: .ask, displayed: .ask),
        ]

        for expectation in expectations {
            XCTAssertEqual(
                ReviewPresentationPolicy.displayedWorkspace(
                    for: expectation.selection,
                    isCompact: expectation.isCompact
                ),
                expectation.displayed,
                "Unexpected workspace display for compact=\(expectation.isCompact)"
            )
        }
    }
}

extension ReviewPresentationPolicyTests {
    @MainActor
    func testSidebarNavigationRemainsAvailableOnContentScreensAtCompactWidths() {
        let reachable: [AppModel.Screen] = [.home, .summary, .privacy, .settings]
        let blocked: [AppModel.Screen] = [.preflight, .live, .processing]

        for screen in reachable {
            XCTAssertTrue(
                ReviewPresentationPolicy.allowsSidebarNavigation(for: screen),
                "Sidebar navigation should remain available for \(screen)."
            )
        }
        for screen in blocked {
            XCTAssertFalse(
                ReviewPresentationPolicy.allowsSidebarNavigation(for: screen),
                "Sidebar navigation must remain hidden during \(screen)."
            )
        }
    }
}
