import Foundation

/// User-selectable generator for stopped-meeting chat and optional summary.
/// Remote cases send only retrieved excerpts after explicit consent.
public enum ChatProviderID: String, Codable, CaseIterable, Sendable, Identifiable {
    case appleOnDevice
    case grok
    case openai
    case gemini

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .appleOnDevice: "On this Mac"
        case .grok: "Grok"
        case .openai: "OpenAI"
        case .gemini: "Gemini"
        }
    }

    public var detail: String {
        switch self {
        case .appleOnDevice:
            "Apple Intelligence on this Mac. Offline. Weaker on long meetings."
        case .grok:
            "xAI Grok via your own API key. Retrieved excerpts leave this Mac."
        case .openai:
            "OpenAI GPT via your own API key. Retrieved excerpts leave this Mac."
        case .gemini:
            "Google Gemini via your own API key. Retrieved excerpts leave this Mac."
        }
    }

    public var sendsMeetingExcerptsOffDevice: Bool {
        self != .appleOnDevice
    }

    public var keychainAccount: String {
        "chat-provider.\(rawValue)"
    }

    public var consoleURL: URL {
        switch self {
        case .appleOnDevice:
            URL(string: "https://www.apple.com/apple-intelligence/")!
        case .grok:
            URL(string: "https://console.x.ai/")!
        case .openai:
            URL(string: "https://platform.openai.com/api-keys")!
        case .gemini:
            URL(string: "https://aistudio.google.com/apikey")!
        }
    }

    public var defaultModel: String {
        switch self {
        case .appleOnDevice: "system-language-model"
        case .grok: "grok-4.6"
        case .openai: "gpt-5"
        case .gemini: "gemini-2.5-flash"
        }
    }

    public var systemImage: String {
        switch self {
        case .appleOnDevice: "lock.fill"
        case .grok: "sparkles"
        case .openai: "circle.hexagongrid"
        case .gemini: "diamond.fill"
        }
    }
}

/// Runtime connection state for a provider. Never includes the secret.
public struct ChatProviderAccount: Sendable, Equatable {
    public let provider: ChatProviderID
    public let isConnected: Bool
    public let displayHint: String

    public init(provider: ChatProviderID, isConnected: Bool, displayHint: String) {
        self.provider = provider
        self.isConnected = isConnected
        self.displayHint = displayHint
    }
}
