import Foundation

enum SignalGatePhase: Sendable, Equatable {
    case hidden
    case capturing
    case paused
    case draining
    case processing
}

enum SignalGateAction: Sendable, Equatable, Hashable {
    case pauseOrResume
    case stop
    case showMeetingDetails
}

struct SignalGatePresentation: Sendable, Equatable {
    let phase: SignalGatePhase
    let isVisible: Bool
    let accessibilityValue: String
    let availableActions: Set<SignalGateAction>

    init(phase: SignalGatePhase, isCaptureCommandInFlight: Bool = false) {
        self.phase = phase
        isVisible = phase != .hidden

        switch phase {
        case .hidden:
            accessibilityValue = ""
            availableActions = []
        case .capturing:
            accessibilityValue = "Capturing"
            availableActions = isCaptureCommandInFlight
                ? [.showMeetingDetails]
                : [.pauseOrResume, .stop, .showMeetingDetails]
        case .paused:
            accessibilityValue = "Paused"
            availableActions = isCaptureCommandInFlight
                ? [.showMeetingDetails]
                : [.pauseOrResume, .stop, .showMeetingDetails]
        case .draining:
            accessibilityValue = "Finalizing capture"
            availableActions = [.showMeetingDetails]
        case .processing:
            accessibilityValue = "Processing"
            availableActions = [.showMeetingDetails]
        }
    }

    func isActionAvailable(_ action: SignalGateAction) -> Bool {
        availableActions.contains(action)
    }
}
