import Foundation
@preconcurrency import Translation

public enum TranslationServiceError: Error, Equatable {
    case unsupportedPair
    case languageAssetsNotInstalled
    case sourceNotFinal
}

public actor TranslationService {
    private var sessions: [String: TranslationSession] = [:]
    private let postEditor: TranslationPostEditor
    private let refiner: TranslationRefining?

    public init(
        postEditor: TranslationPostEditor = TranslationPostEditor(),
        refiner: TranslationRefining? = nil
    ) {
        self.postEditor = postEditor
        self.refiner = refiner
    }

    public func availability(
        from source: SpokenLanguage,
        to target: SpokenLanguage
    ) async -> LanguageAvailability.Status {
        guard let pair = Self.pair(source: source, target: target) else { return .unsupported }
        return await LanguageAvailability().status(from: pair.source, to: pair.target)
    }

    public func translate(
        _ segment: Segment,
        to target: SpokenLanguage,
        context: TranslationContext = .empty
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
        let edited = postEditor.edit(
            source: segment.text,
            draft: response.targetText,
            sourceLanguage: segment.language,
            targetLanguage: target,
            context: context
        )
        let refined: String
        if let refiner {
            let request = TranslationRefineRequest(
                sourceText: segment.text,
                draftText: edited,
                sourceLanguage: segment.language,
                targetLanguage: target,
                context: context
            )
            refined = postEditor.restoreProtectedTokens(
                source: segment.text,
                text: await refiner(request) ?? edited
            )
        } else {
            refined = edited
        }
        return TranslationRecord(
            sourceSegmentID: segment.id,
            sourceLanguage: segment.language,
            targetLanguage: target,
            text: refined
        )
    }

    /// Test seam: apply the same post-edit / optional refine path without Apple Translation.
    public func finalizeDraft(
        source: String,
        draft: String,
        sourceLanguage: SpokenLanguage,
        targetLanguage: SpokenLanguage,
        context: TranslationContext
    ) async -> String {
        let edited = postEditor.edit(
            source: source,
            draft: draft,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            context: context
        )
        guard let refiner else { return edited }
        let request = TranslationRefineRequest(
            sourceText: source,
            draftText: edited,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            context: context
        )
        return postEditor.restoreProtectedTokens(
            source: source,
            text: await refiner(request) ?? edited
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
