import Foundation

public enum MeetingState: String, Codable, Sendable {
    case ready
    case recording
    case paused
    case stopped
}

public struct Meeting: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public var title: String
    public var state: MeetingState
    public let retainsAudio: Bool

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        title: String,
        state: MeetingState = .ready,
        retainsAudio: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.state = state
        self.retainsAudio = retainsAudio
    }
}
