import Foundation
import Testing
@testable import KinetoCore

@Test func asrEnginePreferenceDisplayCopyIsStable() {
    #expect(ASREnginePreference.appleSpeech.displayName.contains("Apple"))
    #expect(ASREnginePreference.whisper.displayName.contains("Whisper"))
    #expect(!ASREnginePreference.appleSpeech.detail.isEmpty)
    #expect(VolatileTranscript.id(for: .you) == "volatile-you")
    #expect(VolatileTranscript.id(for: .selectedSource) == "volatile-selectedSource")
}

@Test func recognitionLanguagePreferenceMigratesLegacyValuesAndKeepsLocaleSelection() {
    #expect(RecognitionLanguagePreference(rawValue: "bilingual") == .automatic)
    #expect(RecognitionLanguagePreference(rawValue: "english") == .english)
    #expect(RecognitionLanguagePreference(rawValue: "vietnamese") == .vietnamese)

    let japanese = RecognitionLanguagePreference.apple(localeIdentifier: "ja-JP")
    #expect(japanese.localeIdentifier == "ja-JP")
    #expect(!japanese.isAutomatic)
    #expect(RecognitionLanguagePreference(rawValue: japanese.rawValue) == japanese)
}

@Test func appleSpeechStatusRoutesOnlySelectedInstalledRuntimeLocales() {
    let downloadable = AppleSpeechStatus(
        isFrameworkAvailable: true,
        locales: [
            AppleSpeechLocale(identifier: "en-US", displayName: "English (United States)", assetState: .available),
            AppleSpeechLocale(identifier: "vi-VN", displayName: "Vietnamese (Vietnam)", assetState: .unsupported),
            AppleSpeechLocale(identifier: "ja-JP", displayName: "Japanese (Japan)", assetState: .installed)
        ],
        notice: "Download required"
    )

    #expect(downloadable.downloadableLocaleCount == 1)
    #expect(!downloadable.canStart(using: .english))
    #expect(downloadable.canDownloadAsset(for: .english))
    #expect(!downloadable.canStart(using: .vietnamese))
    #expect(!downloadable.canDownloadAsset(for: .vietnamese))
    #expect(downloadable.canStart(using: .apple(localeIdentifier: "ja-JP")))
    #expect(!downloadable.canStart(using: .automatic))
    #expect(downloadable.readinessMessage(for: .vietnamese).contains("cannot be installed"))
}

@Test func appleSpeechStatusUsesInstalledLocaleIdentifierForApplePipeline() {
    let status = AppleSpeechStatus(
        isFrameworkAvailable: true,
        locales: [
            AppleSpeechLocale(identifier: "en-US", displayName: "English (United States)", assetState: .installed),
            AppleSpeechLocale(identifier: "fr-FR", displayName: "French (France)", assetState: .available)
        ],
        notice: "Ready"
    )

    #expect(status.canStart(using: .english))
    #expect(status.installedLocaleIdentifier(for: .english) == "en-US")
    #expect(status.canDownloadAsset(for: .apple(localeIdentifier: "fr-FR")))
    #expect(status.readinessMessage(for: .apple(localeIdentifier: "fr-FR")).contains("can be downloaded"))
}
