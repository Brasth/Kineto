import Foundation
@preconcurrency import Translation

public enum TranslationServiceError: Error, Equatable {
    case unsupportedPair
    case languageAssetsNotInstalled
    case sourceNotFinal
}

public actor TranslationService {
    private var sessions: [String: TranslationSession] = [:]

    public init() {}

    public func availability(
        from source: SpokenLanguage,
        to target: SpokenLanguage
    ) async -> LanguageAvailability.Status {
        guard let pair = Self.pair(source: source, target: target) else { return .unsupported }
        return await LanguageAvailability().status(from: pair.source, to: pair.target)
    }

    public func translate(
        _ segment: Segment,
        to target: SpokenLanguage
    ) async throws -> TranslationRecord {
        guard segment.isFinal else { throw TranslationServiceError.sourceNotFinal }
        guard let pair = Self.pair(source: segment.language, target: target) else {
            throw TranslationServiceError.unsupportedPair
        }
        let key = "\(segment.language.rawValue)-\(target.rawValue)"
        let session: TranslationSession
        if let cached = sessions[key] {
            session = cached
        } else {
            let status = await LanguageAvailability().status(from: pair.source, to: pair.target)
            guard status == .installed else {
                throw TranslationServiceError.languageAssetsNotInstalled
            }
            let created = TranslationSession(installedSource: pair.source, target: pair.target)
            sessions[key] = created
            session = created
        }
        let response = try await session.translate(segment.text)
        return TranslationRecord(
            sourceSegmentID: segment.id,
            sourceLanguage: segment.language,
            targetLanguage: target,
            text: response.targetText
        )
    }

    public func cancel() {
        for session in sessions.values {
            session.cancel()
        }
        sessions.removeAll()
    }

    private static func pair(
        source: SpokenLanguage,
        target: SpokenLanguage
    ) -> (source: Locale.Language, target: Locale.Language)? {
        if source.isEnglish && target.isVietnamese {
            return (Locale.Language(identifier: "en"), Locale.Language(identifier: "vi"))
        }
        if source.isVietnamese && target.isEnglish {
            return (Locale.Language(identifier: "vi"), Locale.Language(identifier: "en"))
        }
        return nil
    }
}
