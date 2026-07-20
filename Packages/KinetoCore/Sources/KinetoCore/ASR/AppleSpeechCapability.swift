import Foundation
import Speech

public enum AppleSpeechCapabilityError: Error, Equatable {
    case unavailable
    case localeUnsupported
    case reservationUnavailable
    case installFailed
}

/// Probes SpeechTranscriber locales and optional asset install (L3 Apple path).
public actor AppleSpeechCapability {
    private var reservedLocale: Locale?

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
        var locales: [AppleSpeechLocale] = []
        locales.reserveCapacity(supported.count)
        for locale in supported {
            let transcriber = makeTranscriber(for: locale)
            let inventoryStatus = await AssetInventory.status(forModules: [transcriber])
            locales.append(
                AppleSpeechLocale(
                    identifier: locale.identifier,
                    displayName: Locale.current.localizedString(forIdentifier: locale.identifier)
                        ?? locale.identifier,
                    assetState: Self.localeAssetState(for: inventoryStatus)
                )
            )
        }
        locales.sort {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }

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

        try await reserveSelectedLocale(locale)
        let transcriber = makeTranscriber(for: locale)
        if let request = try await AssetInventory.assetInstallationRequest(
            supporting: [transcriber]
        ) {
            try await request.downloadAndInstall()
        }
        return await status()
    }

    public func makeTranscriber(localeIdentifier: String) async throws -> SpeechTranscriber {
        guard SpeechTranscriber.isAvailable else { throw AppleSpeechCapabilityError.unavailable }
        guard let locale = await equivalent(to: localeIdentifier) else {
            throw AppleSpeechCapabilityError.localeUnsupported
        }
        try await reserveSelectedLocale(locale)
        let transcriber = makeTranscriber(for: locale)
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
            throw AppleSpeechCapabilityError.localeUnsupported
        }
        return transcriber
    }



    private func equivalent(to identifier: String) async -> Locale? {
        let locale = Locale(identifier: identifier)
        if let match = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            return match
        }
        let supported = await SpeechTranscriber.supportedLocales
        return supported.first { matches($0, identifier) }
    }

    private func makeTranscriber(for locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: [.audioTimeRange]
        )
    }

    private static func localeAssetState(
        for status: AssetInventory.Status
    ) -> LocaleAssetState {
        switch status {
        case .installed:
            .installed
        case .supported, .downloading:
            .available
        case .unsupported:
            .unsupported
        @unknown default:
            .unsupported
        }
    }

    /// Retains only the currently selected locale so changing languages cannot
    /// exhaust Speech's finite reservation quota.
    private func reserveSelectedLocale(_ locale: Locale) async throws {
        if let reservedLocale, Self.sameLocale(reservedLocale, locale) {
            return
        }

        let previousLocale = reservedLocale
        if let previousLocale {
            _ = await AssetInventory.release(reservedLocale: previousLocale)
            reservedLocale = nil
        }

        let existingReservations = await AssetInventory.reservedLocales
        if let existing = existingReservations.first(where: { Self.sameLocale($0, locale) }) {
            reservedLocale = existing
            return
        }

        do {
            guard try await AssetInventory.reserve(locale: locale) else {
                throw AppleSpeechCapabilityError.reservationUnavailable
            }
            reservedLocale = locale
        } catch {
            if let previousLocale,
               (try? await AssetInventory.reserve(locale: previousLocale)) == true {
                reservedLocale = previousLocale
            }
            throw error
        }
    }

    private static func sameLocale(_ lhs: Locale, _ rhs: Locale) -> Bool {
        lhs.identifier(.bcp47)
            .caseInsensitiveCompare(rhs.identifier(.bcp47)) == .orderedSame
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
