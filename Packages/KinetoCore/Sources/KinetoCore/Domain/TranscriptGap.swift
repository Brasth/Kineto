import Foundation

public struct TranscriptGap: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let meetingID: UUID
    public let source: AudioSource
    public let timestamp: TimeInterval
    public let duration: TimeInterval
    public let reason: String

    public init(
        id: UUID = UUID(),
        meetingID: UUID,
        source: AudioSource,
        timestamp: TimeInterval,
        duration: TimeInterval = 0,
        reason: String
    ) {
        self.id = id
        self.meetingID = meetingID
        self.source = source
        self.timestamp = timestamp
        self.duration = duration
        self.reason = reason
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case meetingID
        case source
        case timestamp
        case duration
        case reason
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        meetingID = try container.decode(UUID.self, forKey: .meetingID)
        source = try container.decode(AudioSource.self, forKey: .source)
        timestamp = try container.decode(TimeInterval.self, forKey: .timestamp)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        reason = try container.decode(String.self, forKey: .reason)
    }
}
