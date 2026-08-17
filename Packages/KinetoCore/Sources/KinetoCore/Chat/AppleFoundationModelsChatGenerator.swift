import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
@Generable
private struct GeneratedChatCitation {
    @Guide(description: "UUID of a supplied transcript segment")
    var segmentID: String

    @Guide(description: "Exact contiguous text copied from that supplied excerpt")
    var quote: String
}

@available(macOS 26.0, *)
@Generable
private struct GeneratedChatPayload {
    @Guide(description: "A concise answer grounded only in the supplied transcript excerpts")
    var answer: String

    @Guide(description: "One or more exact supporting quotes from supplied transcript excerpts")
    var citations: [GeneratedChatCitation]
}

@available(macOS 26.0, *)
public struct AppleFoundationModelsChatGenerator: MeetingChatGenerating {
    public let provider: ChatProviderID = .appleOnDevice
    private let model: SystemLanguageModel

    public init(model: SystemLanguageModel = .default) {
        self.model = model
    }

    public func capability(for language: SpokenLanguage) -> MeetingChatModelCapability {
        guard model.availability == .available else { return .unavailable }
        let locale = Locale(identifier: language.rawValue)
        return model.supportsLocale(locale) ? .available : .unsupportedLocale
    }

    public func generate(_ request: MeetingChatRequest) async throws -> MeetingChatGeneration {
        let session = LanguageModelSession(
            model: model,
            tools: [],
            instructions: MeetingChatInstructions.groundedJSON
        )
        let response = try await session.respond(
            to: request.prompt,
            generating: GeneratedChatPayload.self
        )
        return MeetingChatGeneration(
            answer: response.content.answer,
            citations: response.content.citations.compactMap { citation in
                guard let segmentID = UUID(uuidString: citation.segmentID) else { return nil }
                return EvidenceReference(segmentID: segmentID, supportingText: citation.quote)
            }
        )
    }
}
#endif

public enum MeetingChatGeneratorFactory {
    /// On-device Apple generator when the OS and Apple Intelligence allow it.
    public static func appleOnDeviceIfAvailable() -> any MeetingChatGenerating {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return AppleFoundationModelsChatGenerator()
        }
        #endif
        return UnavailableChatGenerator(provider: .appleOnDevice, result: .unavailable)
    }
}
