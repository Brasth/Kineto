import Foundation

public struct ActiveSources: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let selectedSource = ActiveSources(rawValue: 1 << 0)
    public static let you = ActiveSources(rawValue: 1 << 1)

    public static let all: ActiveSources = [.selectedSource, .you]
}

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
    public let activeSources: ActiveSources

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        title: String,
        state: MeetingState = .ready,
        retainsAudio: Bool = false,
        activeSources: ActiveSources = .all
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.state = state
        self.retainsAudio = retainsAudio
        self.activeSources = activeSources
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, title, state, retainsAudio, activeSources
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        title = try container.decode(String.self, forKey: .title)
        state = try container.decode(MeetingState.self, forKey: .state)
        retainsAudio = try container.decode(Bool.self, forKey: .retainsAudio)
        activeSources = try container.decodeIfPresent(ActiveSources.self, forKey: .activeSources) ?? .all
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(title, forKey: .title)
        try container.encode(state, forKey: .state)
        try container.encode(retainsAudio, forKey: .retainsAudio)
        try container.encode(activeSources, forKey: .activeSources)
    }
}
