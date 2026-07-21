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

                if model.petModeEnabled {
                    Picker(
                        "Pet theme",
                        selection: Binding<FloatingCaptionPetAppearance>(
                            get: { model.petAppearance },
                            set: { appearance in
                                guard let theme = FloatingCaptionPetCatalog.builtInThemes.first(
                                    where: { $0.appearance == appearance }
                                ) else {
                                    return
                                }
                                model.selectPetTheme(theme)
                            }
                        )
                    ) {
                        ForEach(FloatingCaptionPetCatalog.builtInThemes) { theme in
                            Text(theme.title).tag(theme.appearance)
                        }
                    }
                    Picker("Size", selection: $model.petSize) {
                        ForEach(FloatingCaptionPetSize.allCases, id: \.self) { size in
                            Text(size.title).tag(size)
                        }
                    }
                    Picker("Motion", selection: $model.petMotion) {
                        ForEach(FloatingCaptionPetMotion.allCases, id: \.self) { motion in
                            Text(motion.title).tag(motion)
                        }
                    }
                    ColorPicker(
                        "Leaf accent",
                        selection: Binding<Color>(
                            get: { Color(cgColor: model.petAccent.cgColor) },
                            set: { color in
                                guard let cgColor = color.cgColor,
                                      let accent = FloatingCaptionPetAccent(cgColor: cgColor)
                                else {
                                    return
                                }
                                model.petAccent = accent
                            }
                        ),
                        supportsOpacity: false
                    )
                    Text("Accent color affects companion pixels only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        .frame(width: 390)
        .padding(20)
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
