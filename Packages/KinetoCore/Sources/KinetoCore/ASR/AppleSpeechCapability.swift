import Foundation
import Speech

public enum AppleSpeechCapabilityError: Error, Equatable {
    case unavailable
    case localeUnsupported
    case installFailed
}

/// Probes SpeechTranscriber locales and optional asset install (L3 Apple path).
public actor AppleSpeechCapability {
    public init() {}

    public func status() async -> AppleSpeechStatus {
        guard SpeechTranscriber.isAvailable else {
            return AppleSpeechStatus(
                isFrameworkAvailable: false,
                locales: [],
                notice: "Apple Speech is unavailable on this Mac. Use Whisper."
            )
        }

        let supported = await SpeechTranscriber.supportedLocales
        let installed = await SpeechTranscriber.installedLocales
        let locales = supported.map { locale in
            AppleSpeechLocale(
                identifier: locale.identifier,
                displayName: Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier,
                assetState: installed.contains(where: { matches($0, locale.identifier) }) ? .installed : .available
            )
        }
        .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }

        let notice: String
        if locales.isEmpty {
            notice = "Apple Speech has no transcription languages available on this Mac. Use Whisper."
        } else {
            notice = "Apple Speech supports \(locales.count) language\(locales.count == 1 ? "" : "s") on this Mac. \(locales.filter { $0.assetState == .installed }.count) installed; select one language for live captions."
        }

        return AppleSpeechStatus(
            isFrameworkAvailable: true,
            locales: locales,
            notice: notice
        )
    }

    /// Downloads one selected, runtime-supported Apple Speech asset.
    public func installAsset(localeIdentifier: String) async throws -> AppleSpeechStatus {
        guard SpeechTranscriber.isAvailable else { throw AppleSpeechCapabilityError.unavailable }
        guard let locale = await equivalent(to: localeIdentifier) else {
            throw AppleSpeechCapabilityError.localeUnsupported
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: [.audioTimeRange]
        )
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        return await status()
    }

    public func makeTranscriber(localeIdentifier: String) async throws -> SpeechTranscriber {
        guard SpeechTranscriber.isAvailable else { throw AppleSpeechCapabilityError.unavailable }
        guard let locale = await equivalent(to: localeIdentifier) else {
            throw AppleSpeechCapabilityError.localeUnsupported
        }
        let installed = await SpeechTranscriber.installedLocales
        let id = locale.identifier(.bcp47)
        guard installed.contains(where: { $0.identifier(.bcp47) == id || $0.identifier == locale.identifier }) else {
            throw AppleSpeechCapabilityError.localeUnsupported
        }
        return SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: [.audioTimeRange]
        )
    }



    private func equivalent(to identifier: String) async -> Locale? {
        let locale = Locale(identifier: identifier)
        if let match = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            return match
        }
        let supported = await SpeechTranscriber.supportedLocales
        return supported.first { matches($0, identifier) }
    }


    private func matches(_ locale: Locale, _ candidate: String) -> Bool {
        let id = locale.identifier
        let bcp = locale.identifier(.bcp47)
        let language = locale.language.languageCode?.identifier
        return id.caseInsensitiveCompare(candidate) == .orderedSame
            || bcp.caseInsensitiveCompare(candidate) == .orderedSame
            || (language?.caseInsensitiveCompare(candidate) == .orderedSame)
            || id.lowercased().hasPrefix(candidate.lowercased() + "_")
            || id.lowercased().hasPrefix(candidate.lowercased() + "-")
            || bcp.lowercased().hasPrefix(candidate.lowercased())
    }
}
