import KinetoCore
@preconcurrency import Translation
import SwiftUI
import UniformTypeIdentifiers

enum ReviewPresentationPolicy {
    enum Workspace: Hashable {
        case transcript
        case summary
        case ask
    }

    static let sidebarMaximumWidth: CGFloat = 290
    static let regularReviewPaneMinimumWidth: CGFloat = 360
    static let reviewChromeAllowance: CGFloat = 72
    static let compactPresentationThreshold: CGFloat =
        sidebarMaximumWidth
        + (regularReviewPaneMinimumWidth * 2)
        + reviewChromeAllowance

    static func isCompact(outerWidth: CGFloat) -> Bool {
        outerWidth < compactPresentationThreshold
    }

    static func workspaceOptions(isCompact: Bool) -> [Workspace] {
        isCompact ? [.transcript, .summary, .ask] : [.summary, .ask]
    }

    static func displayedWorkspace(for selection: Workspace, isCompact: Bool) -> Workspace {
        guard !isCompact, selection == .transcript else { return selection }
        return .summary
    }
}

struct HomeView: View {
    @Bindable var model: AppModel
    @State private var importsModel = false
    @State private var confirmsDelete = false
    @State private var evidenceSelection: EvidenceSelection?
    @State private var showsAppleSpeechDownloadPrompt = false
    @State private var englishToVietnamese = TranslationSession.Configuration(
        source: Locale.Language(identifier: "en"),
        target: Locale.Language(identifier: "vi")
    )
    @State private var vietnameseToEnglish = TranslationSession.Configuration(
        source: Locale.Language(identifier: "vi"),
        target: Locale.Language(identifier: "en")
    )
    @State private var chatQuestion = ""
    @FocusState private var chatQuestionFocused: Bool
    @State private var submittedChatQuestion: String?
    @ScaledMetric(relativeTo: .body) private var chatEditorHeight = 64
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var usesCompactPresentation = false
    @State private var reviewWorkspace: ReviewPresentationPolicy.Workspace = .summary
    private static let chatQuestionLimit = 1_500

    var body: some View {
        GeometryReader { proxy in
        NavigationSplitView(columnVisibility: sidebarVisibilityBinding) {
            List(selection: Binding(
                get: { model.screen },
                set: { screen in if let screen { model.show(screen) } }
            )) {
                Section {
                    HStack(spacing: 10) {
                        Image("KinetoLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .accessibilityHidden(true)
                        Text("Kineto")
                            .font(.headline)
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Label("Meetings", systemImage: "waveform")
                        .tag(AppModel.Screen.home)
                    Label("Privacy & Storage", systemImage: "lock")
                        .tag(AppModel.Screen.privacy)
                }
                Section("Local status") {
                    Label(model.modelStatus, systemImage: model.modelReady ? "checkmark.seal" : "arrow.down.circle")
                        .font(.caption)
                        .foregroundStyle(model.modelReady ? Color.secondary : Color.orange)
                }
            }
            .navigationSplitViewColumnWidth(
                min: 210,
                ideal: 245,
                max: ReviewPresentationPolicy.sidebarMaximumWidth
            )
        } detail: {
            Group {
                switch model.screen {
                case .home:
                    home
                case .preflight:
                    preflight
                case .live:
                    live
                case .processing:
                    processing
                case .summary:
                    summary
                case .privacy:
                    privacy
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
        }
        .onAppear {
            synchronizePresentation(for: proxy.size.width, restoresSidebar: true)
        }
        .onChange(of: proxy.size.width) { _, width in
            synchronizePresentation(for: width, restoresSidebar: false)
        }
        .onChange(of: model.screen) {
            synchronizePresentation(for: proxy.size.width, restoresSidebar: true)
        }
        .task {
            await model.refreshCapabilities()
            showsAppleSpeechDownloadPrompt = model.shouldPromptForAppleSpeechDownload
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
        .alert("Kineto", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { dismissErrorAlert() } }
        )) {
            Button("OK", role: .cancel) { dismissErrorAlert() }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .alert("Download Apple Speech?", isPresented: $showsAppleSpeechDownloadPrompt) {
            Button("Download Apple Speech") {
                Task { await model.installAppleSpeechAssets() }
            }
            Button("Use Whisper Instead") {
                model.asrEnginePreference = .whisper
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Kineto needs an installed English or Vietnamese Apple Speech language pack for low-latency live captions. The download is managed by macOS, stays on this Mac, and does not start recording.")
        }
        .confirmationDialog(
            "Delete this meeting?",
            isPresented: $confirmsDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Meeting", role: .destructive) {
                Task { await model.deleteCurrentMeeting() }
            }
        } message: {
            Text("Kineto destroys the meeting key before removing its encrypted package. This cannot be undone.")
        }
        .sheet(item: $evidenceSelection) { selection in
            EvidenceSheet(selection: selection)
        }
        }
    }

    private var sidebarVisibilityBinding: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { sidebarVisibility },
            set: { sidebarVisibility = canPresentSidebar ? $0 : .detailOnly }
        )
    }

    private var regularReviewWorkspaceBinding: Binding<ReviewPresentationPolicy.Workspace> {
        Binding(
            get: {
                ReviewPresentationPolicy.displayedWorkspace(
                    for: reviewWorkspace,
                    isCompact: false
                )
            },
            set: { reviewWorkspace = $0 }
        )
    }

    private var canPresentSidebar: Bool {
        guard !usesCompactPresentation else { return false }
        switch model.screen {
        case .home, .summary, .privacy:
            return true
        case .preflight, .live, .processing:
            return false
        }
    }

    private func synchronizePresentation(for width: CGFloat, restoresSidebar: Bool) {
        let wasCompact = usesCompactPresentation
        let isCompact = ReviewPresentationPolicy.isCompact(outerWidth: width)
        usesCompactPresentation = isCompact

        switch model.screen {
        case .preflight, .live, .processing:
            sidebarVisibility = .detailOnly
        case .home, .summary, .privacy:
            if isCompact {
                sidebarVisibility = .detailOnly
            } else if restoresSidebar || wasCompact {
                sidebarVisibility = .all
            }
        }
    }

    private var home: some View {
        ScrollView {
            VStack(spacing: 28) {
                ZStack {
                    Circle().fill(.mint.opacity(0.12)).frame(width: 112, height: 112)
                    Image(systemName: "waveform.badge.mic")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(.mint)
                        .accessibilityHidden(true)
                }
                VStack(spacing: 10) {
                    Text("Ready for a local meeting")
                        .font(.largeTitle.weight(.semibold))
                    Text("Transcribe English and Vietnamese, translate both ways, and build an evidence-linked summary on this Mac.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 620)
                }
                Button("New Meeting", systemImage: "plus") { Task { await model.newMeeting() } }
                    .buttonStyle(.borderedProminent)
                    .tint(.mint)
                    .controlSize(.large)
                    .keyboardShortcut("n", modifiers: .command)
                HStack(spacing: 18) {
                    Label("No meeting-content cloud", systemImage: "network.slash")
                    Label("Raw audio off", systemImage: "speaker.slash")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if !model.savedMeetings.isEmpty {
                    Divider().frame(maxWidth: 620)
                    LazyVStack(alignment: .leading, spacing: 8) {
                        Text("Meeting library")
                            .font(.headline)
                        ForEach(model.savedMeetings, id: \.meeting.id) { saved in
                            Button {
                                Task { await model.openMeeting(saved) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(saved.meeting.title)
                                        Text(saved.meeting.createdAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(saved.segments.count) segments")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "chevron.right")
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(10)
                            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .frame(maxWidth: 620)
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(model.productName)
    }

    private var preflight: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                contentHeader("New meeting", subtitle: "Confirm the exact capture boundary before anything starts.")
                GroupBox("Capture source") {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(model.selectedTarget?.name ?? "No source selected")
                                .font(.headline)
                            Text("Open the meeting app first, then choose its application or a display. Kineto excludes itself from capture.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Choose…") { model.chooseSource() }
                    }
                    .padding(8)
                }
                GroupBox("Live speech engine") {
                    VStack(alignment: .leading, spacing: 12) {
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
                        if model.asrEnginePreference == .appleSpeech,
                           !model.canUseAppleSpeechForRecognitionLanguage {
                            Button("Use Whisper instead") {
                                model.asrEnginePreference = .whisper
                            }
                        }
                        if model.asrEnginePreference == .whisper || !model.canUseAppleSpeechForRecognitionLanguage {
                            Divider()
                            settingRow(
                                title: "Whisper fallback model",
                                detail: model.modelStatus,
                                status: model.modelReady
                            ) {
                                Button("Import verified model…") { importsModel = true }
                                    .disabled(model.isBusy)
                            }
                        }
                    }
                    .padding(8)
                }
                GroupBox("Local processing") {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle("Include my microphone as “You”", isOn: $model.includeMicrophone)
                        Toggle("Translate final English ↔ Vietnamese segments", isOn: $model.translationEnabled)
                        if model.translationEnabled {
                            Label(
                                model.translationReady ? "Translation assets ready" : "Preparing local translation assets…",
                                systemImage: model.translationReady ? "checkmark.circle.fill" : "arrow.down.circle"
                            )
                            .font(.caption)
                            .foregroundStyle(model.translationReady ? Color.mint : Color.secondary)
                        }
                        Toggle("Generate a post-meeting summary", isOn: $model.summaryEnabled)
                        if model.summaryEnabled {
                            Picker("Summary language", selection: $model.summaryLanguage) {
                                Text("English").tag(SpokenLanguage.english)
                                Text("Vietnamese").tag(SpokenLanguage.vietnamese)
                            }
                            .pickerStyle(.segmented)
                            Picker("Summary format", selection: $model.summaryTemplate) {
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
                    .padding(8)
                }
                Toggle(isOn: $model.consentGranted) {
                    Text("I have informed meeting participants and understand the selected capture boundary. Live captions float above other apps while capture is active and may be visible in screen shares or screenshots. Raw audio retention is off.")
                        .font(.callout)
                }
                .toggleStyle(.checkbox)
                HStack {
                    Button("Cancel") { model.show(.home) }
                    Spacer()
                    Button("Start Meeting", systemImage: "record.circle") {
                        Task { await model.startMeeting() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.mint)
                    .controlSize(.large)
                    .disabled(
                        model.selectedTarget == nil || !model.canStartWithCurrentASR ||
                        !model.consentGranted || model.isBusy ||
                        (model.translationEnabled && !model.translationReady)
                    )
                }
            }
            .frame(maxWidth: 820)
            .padding(36)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Preflight")
        .translationTask(englishToVietnamese) { session in
            await model.prepareTranslation(session, from: .english, to: .vietnamese)
        }
        .translationTask(vietnameseToEnglish) { session in
            await model.prepareTranslation(session, from: .vietnamese, to: .english)
        }
    }

    private var live: some View {
        let signalGatePresentation = model.signalGatePresentation
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Circle()
                    .fill(model.isPaused ? Color.orange : Color.red)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(model.isPaused ? "Paused" : "Recording")
                    .font(.subheadline.weight(.semibold))
                Divider()
                    .frame(height: 16)
                Text("Source · \(model.selectedTarget?.name ?? "Selected source")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(model.selectedTarget?.name ?? "Selected source")
                    .accessibilityLabel("Capture source \(model.selectedTarget?.name ?? "Selected source")")
                Spacer(minLength: 12)
                if let lag = model.lastTranscriptLagSeconds, lag > 3 {
                    Label(
                        String(format: "%.1f s behind", lag),
                        systemImage: "exclamationmark.circle"
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Transcript lag \(String(format: "%.1f", lag)) seconds")
                }
                Text(model.activeASREngine == .appleSpeech ? "Apple Speech" : "Whisper")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Speech engine \(model.activeASREngine == .appleSpeech ? "Apple Speech" : "Whisper")")
                Label("Local", systemImage: "checkmark.shield")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Processing stays local")
            }
            .padding(.horizontal, 20)
            .frame(height: 40)
            .background(.background)
            Divider()
            if liveTimelineItems.isEmpty {
                ContentUnavailableView(
                    "Listening locally",
                    systemImage: "waveform",
                    description: Text("Transcript text will appear here as people speak.")
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(liveTimelineItems) { item in
                            switch item {
                            case let .segment(segment):
                                TranscriptRow(
                                    segment: segment,
                                    translation: model.translations.first {
                                        $0.sourceSegmentID == segment.id
                                    }
                                )
                                .listRowInsets(EdgeInsets(top: 3, leading: 20, bottom: 3, trailing: 20))
                                .id(item.id)
                            case let .volatile(volatile):
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 7) {
                                        Text(volatile.source == .you ? "You" : "Selected Source")
                                            .font(.caption.weight(.semibold))
                                        Text("Live")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                    }
                                    .accessibilityElement(children: .combine)
                                    Text(volatile.text)
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .italic()
                                        .textSelection(.enabled)
                                }
                                .padding(.vertical, 3)
                                .listRowInsets(EdgeInsets(top: 3, leading: 20, bottom: 3, trailing: 20))
                                .id(item.id)
                            case let .gap(gap):
                                HStack(alignment: .firstTextBaseline, spacing: 7) {
                                    Image(systemName: "waveform.slash")
                                        .foregroundStyle(.orange)
                                        .accessibilityHidden(true)
                                    Text("Recording gap")
                                        .font(.caption.weight(.semibold))
                                    Text(Self.gapDescription(gap.reason))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("Recording gap. \(Self.gapDescription(gap.reason))")
                                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                                .id(item.id)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .onChange(of: liveScrollToken) { _, _ in
                        scrollLiveTranscriptToBottom(using: proxy)
                    }
                    .onAppear {
                        scrollLiveTranscriptToBottom(using: proxy)
                    }
                }
            }
            Divider()
            HStack(spacing: 12) {
                Button(model.isPaused ? "Resume" : "Pause", systemImage: model.isPaused ? "play.fill" : "pause.fill") {
                    Task { await model.pauseOrResume() }
                }
                .disabled(!signalGatePresentation.isActionAvailable(.pauseOrResume))
                .keyboardShortcut(.space, modifiers: [])
                if model.canEnterFloatingMode && model.capturePresentationMode == .mainWindow {
                    Button("Use Floating Captions", systemImage: "rectangle.on.rectangle") {
                        model.enterFloatingMode()
                    }
                }
                Spacer()
                Button("Stop", systemImage: "stop.fill") {
                    Task { await model.stopMeeting() }
                }
                .disabled(!signalGatePresentation.isActionAvailable(.stop))
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
                .keyboardShortcut(".", modifiers: .command)
                Menu {
                    Button("Delete Meeting…", systemImage: "trash", role: .destructive) {
                        confirmsDelete = true
                    }
                } label: {
                    Label("More actions", systemImage: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("More meeting actions")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.background)
        }
        .navigationTitle("Live meeting")
    }

    private enum LiveTimelineItem: Identifiable {
        case segment(Segment)
        case volatile(VolatileTranscript)
        case gap(TranscriptGap)

        var id: String {
            switch self {
            case let .segment(segment):
                "segment-\(segment.id.uuidString)"
            case let .volatile(volatile):
                volatile.id
            case let .gap(gap):
                "gap-\(gap.id.uuidString)"
            }
        }

        var sortTime: TimeInterval {
            switch self {
            case let .segment(segment):
                segment.startTime
            case let .volatile(volatile):
                volatile.startTime
            case let .gap(gap):
                gap.timestamp
            }
        }
    }

    private var liveTimelineItems: [LiveTimelineItem] {
        let segments = model.segments.map(LiveTimelineItem.segment)
        let volatiles = model.volatileTranscripts.values
            .filter { !$0.text.isEmpty }
            .map(LiveTimelineItem.volatile)
        let gaps = model.gaps.map(LiveTimelineItem.gap)
        return (segments + volatiles + gaps).sorted {
            if $0.sortTime == $1.sortTime {
                return $0.id < $1.id
            }
            return $0.sortTime < $1.sortTime
        }
    }

    private static func gapDescription(_ reason: String) -> String {
        switch reason {
        case "audio-frame-discarded":
            "An audio frame could not be processed"
        case "source-lost":
            "The capture source was lost"
        case "speech-restarting":
            "Speech recognition is restarting"
        case "speech-start-failed":
            "Speech recognition is reconnecting"
        default:
            "A recorded interval was unavailable"
        }
    }

    /// Bumps whenever the live transcript should pin to the newest row.
    private var liveScrollToken: String {
        let lastItem = liveTimelineItems.last?.id ?? "none"
        let translationCount = model.translations.count
        let volatileState = model.volatileTranscripts.values
            .sorted { $0.id < $1.id }
            .map { "\($0.id):\($0.endTime):\($0.text)" }
            .joined(separator: "|")
        let lastTranslation = model.translations.last.map {
            "\($0.id.uuidString)"
        } ?? "none"
        return "\(model.segments.count)|\(model.gaps.count)|\(translationCount)|\(volatileState)|\(lastItem)|\(lastTranslation)"
    }

    private func scrollLiveTranscriptToBottom(using proxy: ScrollViewProxy) {
        guard let lastID = liveTimelineItems.last?.id else { return }
        // Scroll immediately and once more after layout commits the new row.
        proxy.scrollTo(lastID, anchor: .bottom)
        DispatchQueue.main.async {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.12)) {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }

    private var processing: some View {
        VStack(spacing: 24) {
            if model.canRetryFinalization {
                Image(systemName: "exclamationmark.lock.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.orange)
                Text("Encrypted finalization needs attention")
                    .font(.title2.weight(.semibold))
                Text("Capture is stopped. Retry sealing the saved transcript; Kineto will not resume audio capture.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                Button("Retry Finalization", systemImage: "arrow.clockwise") {
                    Task { await model.retryFinalization() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy)
            } else {
                ProgressView().controlSize(.large)
                Text(model.processingStatus)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
                VStack(alignment: .leading, spacing: 12) {
                    Label("Draining and sealing the source transcript", systemImage: "hourglass")
                    if model.translationEnabled {
                        Label("Completing remaining EN ↔ VI translations", systemImage: "arrow.triangle.2.circlepath")
                    }
                    if model.summaryEnabled {
                        Label("Building a conversation summary with evidence links", systemImage: "quote.bubble")
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(40)
        .navigationTitle("Processing")
    }

    private var summary: some View {
        SummaryViewportLayout {
            summaryHeader

            if usesCompactPresentation {
                compactSummaryReview
            } else {
                regularSummaryReview
            }

            summaryFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Summary")
    }

    private var summaryHeader: some View {
        Group {
            if usesCompactPresentation {
                VStack(alignment: .leading, spacing: 16) {
                    summaryTitle
                    newMeetingButton
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        summaryTitle
                        Spacer()
                        newMeetingButton
                    }
                    .fixedSize(horizontal: true, vertical: false)

                    VStack(alignment: .leading, spacing: 16) {
                        summaryTitle
                        newMeetingButton
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Meeting complete")
                .font(.largeTitle.weight(.semibold))
            Text("Summary and Ask derive only from the finalized Original Transcript, with linked evidence.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var newMeetingButton: some View {
        Button("New Meeting", systemImage: "plus") {
            Task { await model.newMeeting() }
        }
        .buttonStyle(.borderedProminent)
        .tint(.mint)
        .disabled(model.isGeneratingSummary)
        .fixedSize()
    }

    private var regularSummaryReview: some View {
        HSplitView {
            VStack(spacing: 0) {
                Picker("Review workspace", selection: regularReviewWorkspaceBinding) {
                    ForEach(ReviewPresentationPolicy.workspaceOptions(isCompact: false), id: \.self) {
                        reviewWorkspaceLabel($0).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(12)
                .accessibilityLabel("Meeting review workspace")

                Divider()

                Group {
                    switch reviewWorkspace {
                    case .transcript, .summary:
                        summaryWorkspace
                    case .ask:
                        chatWorkspace
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(
                minWidth: ReviewPresentationPolicy.regularReviewPaneMinimumWidth,
                idealWidth: 440,
                maxWidth: .infinity,
                maxHeight: .infinity
            )

            transcriptWorkspace
                .frame(
                    minWidth: ReviewPresentationPolicy.regularReviewPaneMinimumWidth,
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var compactSummaryReview: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                Picker("Review workspace", selection: $reviewWorkspace) {
                    ForEach(ReviewPresentationPolicy.workspaceOptions(isCompact: true), id: \.self) {
                        reviewWorkspaceLabel($0).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("Meeting review workspace")

                VStack(alignment: .leading, spacing: 4) {
                    Text("Review workspace")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Review workspace", selection: $reviewWorkspace) {
                        ForEach(ReviewPresentationPolicy.workspaceOptions(isCompact: true), id: \.self) {
                            reviewWorkspaceLabel($0).tag($0)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .accessibilityLabel("Meeting review workspace")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)

            Divider()

            Group {
                switch reviewWorkspace {
                case .transcript:
                    transcriptWorkspace
                case .summary:
                    summaryWorkspace
                case .ask:
                    chatWorkspace
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    @ViewBuilder
    private func reviewWorkspaceLabel(_ workspace: ReviewPresentationPolicy.Workspace) -> some View {
        switch workspace {
        case .transcript:
            Text("Original Transcript")
        case .summary:
            Text("Summary")
        case .ask:
            Text("Ask")
        }
    }


    private var transcriptWorkspace: some View {
        List(model.segments) { segment in
            TranscriptRow(
                segment: segment,
                translation: model.translations.first { $0.sourceSegmentID == segment.id }
            )
        }
    }

    private var summaryFooter: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                summaryDeleteButton
                summaryExportButton
                Spacer()
                summaryStatus
            }

            VStack(alignment: .leading, spacing: 10) {
                summaryStatus
                ViewThatFits(in: .horizontal) {
                    HStack {
                        summaryDeleteButton
                        summaryExportButton
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        summaryDeleteButton
                        summaryExportButton
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryDeleteButton: some View {
        Button("Delete…", role: .destructive) { confirmsDelete = true }
            .disabled(model.isGeneratingSummary)
            .fixedSize()
    }

    private var summaryExportButton: some View {
        Button("Export Plaintext…", systemImage: "square.and.arrow.up") {
            Task { await model.exportCurrentMeeting() }
        }
        .keyboardShortcut("e", modifiers: .command)
        .disabled(model.isGeneratingSummary)
        .fixedSize()
    }

    private var summaryStatus: some View {
        Text(model.isGeneratingSummary ? "Generating summary…" : "Encrypted locally · raw audio off")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var summaryWorkspace: some View {
        List {
            Section("Summary") {
                Picker("Format", selection: $model.summaryTemplate) {
                    ForEach(SummaryTemplate.allCases, id: \.self) { template in
                        Text(template.displayName).tag(template)
                    }
                }

                if model.isGeneratingSummary {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Generating a local, evidence-linked summary…")
                    }
                    .foregroundStyle(.secondary)
                } else if let summary = model.summary, !summary.items.isEmpty {
                    Text("Saved as \(model.template(for: summary).displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    let template = model.template(for: summary)
                    ForEach(template.sectionOrder, id: \.rawValue) { kind in
                        let sectionItems = summary.items.filter { $0.kind == kind }
                        if !sectionItems.isEmpty {
                            Text(template.sectionTitle(for: kind))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.mint)

                            ForEach(sectionItems) { item in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(item.text)
                                    HStack {
                                        ForEach(Array(item.evidence.enumerated()), id: \.offset) { _, evidence in
                                            Button("Evidence") {
                                                if let segment = model.segments.first(where: { $0.id == evidence.segmentID }) {
                                                    evidenceSelection = EvidenceSelection(
                                                        segment: segment,
                                                        supportingText: evidence.supportingText
                                                    )
                                                }
                                            }
                                            .buttonStyle(.link)
                                            .font(.caption)
                                        }
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                        }
                    }
                } else {
                    Text("Summary unavailable. The finalized transcript remains intact.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chatWorkspace: some View {
        VStack(spacing: 0) {
            Group {
                if model.chatTurns.isEmpty {
                    VStack(spacing: 20) {
                        Spacer(minLength: 16)

                        Image(systemName: "sparkles")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(.mint)
                            .accessibilityHidden(true)

                        VStack(spacing: 8) {
                            Text("Ask Kineto")
                                .font(.title2.weight(.semibold))

                            Text("Ask about this meeting using only its finalized transcript. Answers stay on this Mac and link back to evidence.")
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: 440)

                        chatQuestionSuggestions

                        Spacer(minLength: 16)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section("Conversation") {
                            ForEach(Array(model.chatTurns.reversed()), id: \.id) { turn in
                                chatTurn(turn)
                                    .padding(.vertical, 6)
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                Divider()

                meetingChatComposer
                    .padding(12)
            }
            .background(.bar)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chatQuestionSuggestions: some View {
        VStack(spacing: 10) {
            Text("Try a prompt")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    chatSuggestionButton("What decisions were made?")
                    chatSuggestionButton("What should happen next?")
                    chatSuggestionButton("What remains unresolved?")
                }

                VStack(spacing: 8) {
                    chatSuggestionButton("What decisions were made?")
                    chatSuggestionButton("What should happen next?")
                    chatSuggestionButton("What remains unresolved?")
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func chatSuggestionButton(_ question: String) -> some View {
        Button(question) {
            useChatSuggestion(question)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .accessibilityHint("Adds this prompt to the Ask Kineto composer.")
    }

    private func chatTurn(_ turn: ChatTurnRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                Label("You", systemImage: "person.crop.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(turn.question)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 10) {
                if turn.outcome == .grounded {
                    Label("Kineto · Grounded answer", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.mint)

                    Text(turn.answer)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !turn.citations.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(Array(turn.citations.enumerated()), id: \.offset) { index, citation in
                                Button("Evidence \(index + 1)", systemImage: "doc.text.magnifyingglass") {
                                    if let selection = model.citationSelection(for: citation) {
                                        evidenceSelection = EvidenceSelection(
                                            segment: selection.0,
                                            supportingText: selection.1
                                        )
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .accessibilityHint("Opens the supporting finalized transcript excerpt.")
                            }
                        }
                    }
                } else {
                    Label("Kineto · No grounded answer", systemImage: "questionmark.circle")
                        .font(.caption.weight(.semibold))

                    Text(model.chatNoAnswerDetail(turn))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !model.chatNoAnswerExcerpts(turn).isEmpty {
                        Text("Related transcript excerpts — not an answer")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    if !turn.citations.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(Array(turn.citations.enumerated()), id: \.offset) { index, citation in
                                Button("Evidence \(index + 1)", systemImage: "doc.text.magnifyingglass") {
                                    if let selection = model.citationSelection(for: citation) {
                                        evidenceSelection = EvidenceSelection(
                                            segment: selection.0,
                                            supportingText: selection.1
                                        )
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .accessibilityHint("Opens a related finalized transcript excerpt.")
                            }
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .accessibilityElement(children: .contain)
    }

    private var meetingChatComposer: some View {
        let chatDisabled = !model.canAskCurrentMeeting
            || model.isGeneratingSummary
            || model.isAnsweringChat
        let questionIsEmpty = chatQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("Ask Kineto", systemImage: "bubble.left.and.text.bubble.right")
                    .font(.headline)

                Spacer(minLength: 8)

                Label("On this Mac · Finalized transcript only", systemImage: "lock.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            ZStack(alignment: .topLeading) {
                TextEditor(text: boundedChatQuestion)
                    .font(.body)
                    .focused($chatQuestionFocused)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .frame(height: chatEditorHeight)
                    .background(.background, in: RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.separator)
                    }
                    .disabled(chatDisabled)
                    .accessibilityLabel("Ask this meeting")
                    .accessibilityHint(
                        "Type a question about this meeting’s finalized transcript. Return adds a line. Command-Return sends."
                    )
                    .accessibilityValue(chatQuestionAccessibilityValue)
                    .onKeyPress(.return, phases: .down) { press in
                        guard press.modifiers.contains(.command) else { return .ignored }
                        submitChatQuestion()
                        return .handled
                    }

                if chatQuestion.isEmpty {
                    Text("Ask a question about this meeting")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Return adds a line · ⌘↩ sends")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Text("\(chatQuestion.count)/\(Self.chatQuestionLimit)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(
                        chatQuestion.count == Self.chatQuestionLimit ? .orange : .secondary
                    )
                    .accessibilityLabel(chatQuestionAccessibilityValue)

                Button(model.isAnsweringChat ? "Sending" : "Send", systemImage: "paperplane.fill") {
                    submitChatQuestion()
                }
                .buttonStyle(.borderedProminent)
                .tint(.mint)
                .disabled(chatDisabled || questionIsEmpty)
                .accessibilityLabel("Send question")
                .accessibilityHint("Searches this meeting’s finalized transcript.")
                .accessibilityValue(chatAvailabilityDescription)
            }

            if chatQuestion.count == Self.chatQuestionLimit {
                Text("Limit reached")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if model.isAnsweringChat {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Searching the finalized transcript…")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if model.isGeneratingSummary {
                Text("Preparing the summary. Questions are available when it is complete.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !model.canAskCurrentMeeting {
                Text("Questions become available when the finalized transcript is ready.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: model.isAnsweringChat) { _, isAnswering in
            if isAnswering {
                chatQuestionFocused = false
            } else if model.errorMessage == nil {
                submittedChatQuestion = nil
            }
        }
    }

    private var boundedChatQuestion: Binding<String> {
        Binding(
            get: { chatQuestion },
            set: { chatQuestion = String($0.prefix(Self.chatQuestionLimit)) }
        )
    }

    private var chatQuestionAccessibilityValue: String {
        let count = chatQuestion.count
        let limitReached = count == Self.chatQuestionLimit ? ", limit reached" : ""
        return "\(count) of \(Self.chatQuestionLimit) characters\(limitReached)"
    }

    private var chatAvailabilityDescription: String {
        if model.isAnsweringChat {
            return "Searching the finalized transcript"
        }
        if model.isGeneratingSummary {
            return "Preparing the summary"
        }
        if !model.canAskCurrentMeeting {
            return "Finalized transcript unavailable"
        }
        return ""
    }

    private func useChatSuggestion(_ question: String) {
        chatQuestion = question
        reviewWorkspace = .ask
        if model.canAskCurrentMeeting, !model.isGeneratingSummary, !model.isAnsweringChat {
            chatQuestionFocused = true
        }
    }

    private func submitChatQuestion() {
        let question = chatQuestion
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              model.canAskCurrentMeeting,
              !model.isGeneratingSummary,
              !model.isAnsweringChat else {
            return
        }

        model.askCurrentMeeting(question: question)
        guard model.isAnsweringChat else { return }

        submittedChatQuestion = question
        chatQuestion = ""
        chatQuestionFocused = false
    }

    private func dismissErrorAlert() {
        model.errorMessage = nil
        guard let submittedChatQuestion else { return }
        defer { self.submittedChatQuestion = nil }
        guard chatQuestion.isEmpty else { return }
        chatQuestion = submittedChatQuestion
        if model.canAskCurrentMeeting, !model.isGeneratingSummary, !model.isAnsweringChat {
            chatQuestionFocused = true
        }
    }

    private var privacy: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                contentHeader("Privacy & Storage", subtitle: "Local-first boundaries are product behavior, not a slogan.")
                privacyCard(
                    "Meeting content",
                    icon: "lock.shield",
                    text: "Final transcripts, translations, summaries, and evidence links are sealed in authenticated local meeting packages."
                )
                privacyCard(
                    "Raw audio",
                    icon: "speaker.slash",
                    text: "Off by default. This build never writes raw audio. Capture uses bounded memory buffers only."
                )
                privacyCard(
                    "Network",
                    icon: "network.slash",
                    text: "The main app has no network entitlement. Local inference and Apple system language assets process meeting content."
                )
                privacyCard(
                    "Deletion",
                    icon: "key.slash",
                    text: "Deletion destroys the per-meeting Keychain keys before removing encrypted package files."
                )
            }
            .frame(maxWidth: 760)
            .padding(36)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Privacy")
    }

    private func contentHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.largeTitle.weight(.semibold))
            Text(subtitle).foregroundStyle(.secondary)
        }
    }

    private func settingRow<Trailing: View>(
        title: String,
        detail: String,
        status: Bool,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack {
            Image(systemName: status ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(status ? .mint : .orange)
            VStack(alignment: .leading) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            trailing()
        }
    }

    private func privacyCard(_ title: String, icon: String, text: String) -> some View {
        GroupBox {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: icon).font(.title2).foregroundStyle(.mint)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline)
                    Text(text).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(8)
        }
    }
}

private struct TranscriptRow: View {
    let segment: Segment
    let translation: TranslationRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Text(segment.speakerLabel.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Self.color(for: segment.speakerLabel))
                Text(Self.timestamp(segment.startTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(segment.language.rawValue.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(segment.speakerLabel.displayName), \(Self.timestamp(segment.startTime)), \(segment.language.rawValue)"
            )
            Text(segment.text)
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            if let translation {
                Text(translation.text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Self.color(for: segment.speakerLabel).opacity(0.45))
                            .frame(width: 2)
                    }
                    .accessibilityLabel("Translation: \(translation.text)")
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
    }

    private static func color(for label: SpeakerLabel) -> Color {
        switch label {
        case .you:
            .mint
        case .selectedSource:
            .cyan
        }
    }

    private static func timestamp(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct EvidenceSelection: Identifiable {
    let id = UUID()
    let segment: Segment
    let supportingText: String
}

private struct EvidenceSheet: View {
    let selection: EvidenceSelection
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Original evidence").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
            }
            Text(
                "\(selection.segment.speakerLabel.displayName) · " +
                selection.segment.language.rawValue.uppercased()
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(.mint)
            GroupBox("Cited support span") {
                Text(selection.supportingText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(6)
            }
            Text("Full finalized source segment")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(selection.segment.text)
                .font(.body)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 320)
    }
}
