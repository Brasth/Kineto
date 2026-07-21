import CoreGraphics
import SwiftUI
import KinetoCore
import UniformTypeIdentifiers

struct CompanionSettingsView: View {
    @Bindable var model: AppModel

    @State private var importsModel = false
    var body: some View {
        Form {
            Section("Floating companion") {
                Toggle("Show companion during active capture", isOn: $model.petModeEnabled)

                Text("Decorative only; it may appear in screen shares and screenshots.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Theme chooses accent used for the main window and (in future) floating captions. The companion is optional and decorative.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                Picker(
                    "Theme",
                    selection: Binding(
                        get: { model.petAppearance },
                        set: { appearance in
                            guard let theme = FloatingCaptionPetCatalog.builtInThemes.first(
                                where: { $0.appearance == appearance }
                            ) else { return }
                            model.selectPetTheme(theme)
                        }
                    )
                ) {
                    ForEach(FloatingCaptionPetCatalog.builtInThemes) { theme in
                        Text(theme.title).tag(theme.appearance)
                    }
                }

                // Selectable theme swatches (tappable, independent of companion toggle)
                HStack(spacing: 12) {
                    ForEach(FloatingCaptionPetCatalog.builtInThemes) { t in
                        Button {
                            model.selectPetTheme(t)
                        } label: {
                            Circle()
                                .fill(Color(cgColor: t.defaultAccent.cgColor))
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Circle()
                                        .stroke(model.petAppearance == t.appearance ? Color.primary : Color.clear, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(t.title)
                    }
                }
                .padding(.bottom, 4)

                if model.petModeEnabled {
                    Picker("Companion size", selection: $model.petSize) {
                        ForEach(FloatingCaptionPetSize.allCases, id: \.self) { size in
                            Text(size.title).tag(size)
                        }
                    }
                    Picker("Companion motion", selection: $model.petMotion) {
                        ForEach(FloatingCaptionPetMotion.allCases, id: \.self) { motion in
                            Text(motion.title).tag(motion)
                        }
                    }
                }
            }
            Section("Transcription") {
                Picker("Engine", selection: $model.asrEnginePreference) {
                    ForEach(ASREnginePreference.allCases) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
                .pickerStyle(.segmented)
                Text(model.asrEnginePreference.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Spoken language", selection: $model.recognitionLanguagePreference) {
                    ForEach(model.recognitionLanguageOptions) { language in
                        Text(model.recognitionLanguageDisplayName(language)).tag(language)
                    }
                }
                .pickerStyle(.menu)
                Text(model.recognitionLanguageExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let state = model.recognitionLanguageAssetState(
                    model.recognitionLanguagePreference
                ) {
                    Label(
                        "\(model.recognitionLanguageDisplayName(model.recognitionLanguagePreference)) · \(state.label)",
                        systemImage: "character.book.closed"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                if model.asrEnginePreference == .appleSpeech,
                   model.appleSpeechStatus.canDownloadAsset(for: model.recognitionLanguagePreference) {
                    Button("Download selected Apple speech language…") {
                        Task { await model.installAppleSpeechAssets() }
                    }
                    .disabled(model.isBusy)
                }

                if model.asrEnginePreference == .whisper || !model.canUseAppleSpeechForRecognitionLanguage {
                    HStack {
                        Image(systemName: model.modelReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(model.modelReady ? .mint : .orange)
                        VStack(alignment: .leading) {
                            Text("Whisper fallback model")
                            Text(model.modelStatus).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Import verified model…") { importsModel = true }
                            .disabled(model.isBusy)
                    }
                }
            }

            Section("Summary") {
                Picker("Format", selection: $model.summaryTemplate) {
                    ForEach(SummaryTemplate.allCases) { template in
                        Text(template.displayName).tag(template)
                    }
                }
                .pickerStyle(.menu)
                Text(model.summaryTemplate.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 420, alignment: .topLeading)
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .fileImporter(
            isPresented: $importsModel,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                Task { await model.importModel(from: url) }
            }
        }
    }
}
