import AppKit
import CoreGraphics
import ImageIO
import KinetoCore
import SwiftUI
import UniformTypeIdentifiers

struct CompanionSettingsView: View {
    @Bindable var model: AppModel

    @State private var importsModel = false
    @State private var gallerySearch = ""
    @State private var displayedPets: [PetDexCatalogItem] = []
    @State private var gallerySearchTask: Task<Void, Never>?
    var body: some View {
        Form {
            Section("Floating companion") {
                Toggle("Show companion during active capture", isOn: $model.petModeEnabled)
                    .disabled(model.selectedPet == nil)

                if let pet = model.selectedPet {
                    HStack(spacing: 12) {
                        PetDexInstalledPreview(pet: pet)
                            .frame(width: 56, height: 56)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Selected companion")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(pet.item.displayName)
                                .font(.headline)
                            Text("Created by \(pet.item.creator ?? "Unknown creator").")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Label(
                        "Choose and download a PetDex companion first.",
                        systemImage: "arrow.down.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Text("Decorative only; it may appear in screen shares and screenshots.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Companion size", selection: $model.petSize) {
                    ForEach(FloatingCaptionPetSize.allCases, id: \.self) { size in
                        Text(size.rawValue.capitalized).tag(size)
                    }
                }
                .disabled(model.selectedPet == nil)

                Picker("Companion motion", selection: $model.petMotion) {
                    ForEach(FloatingCaptionPetMotion.allCases, id: \.self) { motion in
                        Text(motion.rawValue.capitalized).tag(motion)
                    }
                }
                .disabled(model.selectedPet == nil)
            }

            Section("PetDex gallery") {
                galleryStatus

                if !model.petCatalog.isEmpty {
                    TextField("Search PetDex", text: $gallerySearch)
                        .textFieldStyle(.roundedBorder)

                    galleryResults
                }

                Text("PetDex companions are community-submitted assets owned by their creators. Catalog metadata and sprites are handled by an isolated service that never receives meeting content.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .task {
            await model.preparePetCatalog()
        }
        .onAppear {
            updateDisplayedPets(debouncing: false)
        }
        .onChange(of: model.petCatalog) { _, _ in
            updateDisplayedPets(debouncing: false)
        }
        .onChange(of: gallerySearch) { _, _ in
            updateDisplayedPets(debouncing: true)
        }
        .onDisappear {
            gallerySearchTask?.cancel()
        }
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

    @ViewBuilder
    private var galleryResults: some View {
        if displayedPets.isEmpty {
            Text("No matching companions.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 96, alignment: .center)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(displayedPets) { pet in
                        petRow(pet)
                        Divider()
                    }
                }
            }
            .frame(height: 320)
            .accessibilityLabel("PetDex gallery results")
        }
    }

    private func updateDisplayedPets(debouncing: Bool) {
        gallerySearchTask?.cancel()

        let pets = model.petCatalog
        let query = gallerySearch
        gallerySearchTask = Task {
            if debouncing {
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            guard !Task.isCancelled else { return }

            let results = await Task.detached(priority: .userInitiated) {
                PetDexCatalogSearch.matching(pets, query: query)
            }.value
            guard !Task.isCancelled else { return }
            displayedPets = results
        }
    }

    @ViewBuilder
    private var galleryStatus: some View {
        switch model.petCatalogStatus {
        case .idle:
            Button {
                Task { await model.refreshPetCatalog() }
            } label: {
                Label("Load PetDex gallery", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)

        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading PetDex gallery…")
            }

        case let .ready(isStale):
            HStack {
                if isStale {
                    Label("Saved catalog", systemImage: "internaldrive")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Catalog up to date", systemImage: "checkmark.seal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh") {
                    Task { await model.refreshPetCatalog() }
                }
                .disabled(model.installingPetSlug != nil)
            }

        case let .failed(message, hasCachedCatalog):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                if hasCachedCatalog {
                    Text("Saved catalog remains available below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let slug = model.retryPetSlug {
                    Button("Retry download") {
                        Task { await model.selectPet(slug: slug) }
                    }
                    .disabled(model.installingPetSlug != nil)
                } else {
                    Button("Retry") {
                        Task { await model.refreshPetCatalog() }
                    }
                    .disabled(model.installingPetSlug != nil)
                }
            }
        }
    }

    @ViewBuilder
    private func petRow(_ pet: PetDexCatalogItem) -> some View {
        let isSelected = model.selectedPet?.item.slug == pet.slug
        let isInstalling = model.installingPetSlug == pet.slug

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(pet.displayName)
                        .font(.headline)
                    Text("\(pet.kind) · \(pet.creator ?? "Unknown creator")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Label("In use", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.teal)
                }
            }

            HStack {
                Link("View on PetDex", destination: URL(string: "https://petdex.dev/pets/\(pet.slug)")!)
                    .font(.caption)

                Spacer()

                if isInstalling {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Installing…")
                    }
                    .font(.caption)
                } else if !isSelected {
                    Button("Download & Use") {
                        Task { await model.selectPet(slug: pet.slug) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                    .disabled(model.petCatalogStatus == .loading || model.installingPetSlug != nil)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct PetDexInstalledPreview: View {
    let pet: PetDexInstalledPet
    @State private var idleFrame: NSImage?

    var body: some View {
        Group {
            if let idleFrame {
                Image(nsImage: idleFrame)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .accessibilityLabel("\(pet.item.displayName) preview")
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Companion preview unavailable")
            }
        }
        .padding(6)
        .background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .task(id: pet.id) {
            idleFrame = nil
            let selectedPet = pet
            let frames = try? await Task.detached(priority: .userInitiated) {
                PetDexSpriteFrames(
                    images: try PetDexSpriteFrameLoader.idleFrames(for: selectedPet)
                )
            }.value
            guard !Task.isCancelled, selectedPet.id == pet.id else { return }
            idleFrame = frames?.images.first
        }
    }
}
