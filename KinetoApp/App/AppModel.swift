import AppKit
@preconcurrency import AVFoundation
import Foundation
import KinetoCore
import Observation
@preconcurrency import ScreenCaptureKit
@preconcurrency import Translation

private final class ContentPickerObserver: NSObject, SCContentSharingPickerObserver, @unchecked Sendable {
    var onSelection: (@MainActor @Sendable (SCContentFilter) -> Void)?
    var onFailure: (@MainActor @Sendable (String) -> Void)?

    func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter,
        for stream: SCStream?
    ) {
        Task { @MainActor in onSelection?(filter) }
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {}

    func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        Task { @MainActor in onFailure?("The system source picker could not start.") }
    }
}

enum CapturePresentationMode: Sendable, Equatable {
    case mainWindow
    case floating
}

@MainActor

@Observable
final class AppModel {
    enum Screen: String, CaseIterable, Sendable {
        case home
        case preflight
        case live
        case processing
        case summary
        case privacy
        case settings
    }
    private static let petSettingsKey = "kineto.petSettings"
    private var isRestoringPetSettings = false

    private struct PetSettingsSnapshot: Codable {
        static let currentVersion = 1

        let version: Int
        let enabled: Bool?
        let appearance: String?
        let size: String?
        let motion: String?
        let accent: String?

        private enum CodingKeys: String, CodingKey {
            case version
            case enabled
            case appearance
            case size
            case motion
            case accent
        }

        init(
            version: Int = Self.currentVersion,
            enabled: Bool,
            appearance: FloatingCaptionPetAppearance,
            size: FloatingCaptionPetSize,
            motion: FloatingCaptionPetMotion,
            accent: FloatingCaptionPetAccent
        ) {
            self.version = version
            self.enabled = enabled
            self.appearance = appearance.rawValue
            self.size = size.rawValue
            self.motion = motion.rawValue
            self.accent = accent.storageValue
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decode(Int.self, forKey: .version)
            enabled = try? container.decode(Bool.self, forKey: .enabled)
            appearance = try? container.decode(String.self, forKey: .appearance)
            size = try? container.decode(String.self, forKey: .size)
            motion = try? container.decode(String.self, forKey: .motion)
            accent = try? container.decode(String.self, forKey: .accent)
        }
    }

    private(set) var screen: Screen = .home
    private(set) var selectedTarget: CaptureTarget?
    private(set) var modelStatus = "Checking local model…"
    private(set) var modelReady = false
    private(set) var isBusy = false
    private(set) var isPaused = false
    private(set) var capturePresentationMode: CapturePresentationMode = .mainWindow
    private var signalGatePhase: SignalGatePhase = .hidden {
        didSet {
            guard signalGatePhase == .capturing else {
                capturePresentationMode = .mainWindow
                return
            }
        }
    }
    private var isCaptureCommandInFlight = false
    private(set) var segments: [Segment] = []
    private(set) var translations: [TranslationRecord] = []
    private(set) var gaps: [TranscriptGap] = []
    private(set) var summary: SummaryRecord?
    private(set) var chatTurns: [ChatTurnRecord] = []
    private(set) var isAnsweringChat = false
    private(set) var translationReady = false
    private(set) var canRetryFinalization = false
    private(set) var processingStatus = "Finalizing locally"
    private(set) var isGeneratingSummary = false
    private(set) var lastTranscriptLagSeconds: Double?
    private(set) var lastRecognitionTiming: RecognitionTiming?
    private(set) var savedMeetings: [MeetingSnapshot] = []
    private(set) var recoveryNotice: String?
    private(set) var volatileTranscripts: [String: VolatileTranscript] = [:]
    private(set) var appleSpeechStatus = AppleSpeechStatus(isFrameworkAvailable: false, locales: [], notice: "Checking Apple Speech…")
    /// Decorative floating-caption companion preference; disabled by default.
    var petModeEnabled = false {
        didSet {
            guard !isRestoringPetSettings else { return }
            persistPetSettings()
        }
    }
    var petAppearance: FloatingCaptionPetAppearance = .signal {
        didSet {
            guard !isRestoringPetSettings else { return }
            persistPetSettings()
        }
    }
    var petSize: FloatingCaptionPetSize = .standard {
        didSet {
            guard !isRestoringPetSettings else { return }
            persistPetSettings()
        }
    }
    var petMotion: FloatingCaptionPetMotion = .subtle {
        didSet {
            guard !isRestoringPetSettings else { return }
            persistPetSettings()
        }
    }
    var petAccent = FloatingCaptionPetVisualPreferences.default.accent {
        didSet {
            guard !isRestoringPetSettings else { return }
            persistPetSettings()
        }
    }
    /// Which engine is actually running this meeting (after fallback).
    private(set) var activeASREngine: ASREnginePreference = .appleSpeech
    private(set) var asrEngineNotice: String?
    var includeMicrophone = true
    var translationEnabled = true
    var summaryEnabled = true
    var summaryLanguage: SpokenLanguage = .english
    var summaryTemplate: SummaryTemplate = .executiveBrief {
        didSet {
            UserDefaults.standard.set(summaryTemplate.rawValue, forKey: "kineto.summaryTemplate")
        }
    }
    var consentGranted = false
    var errorMessage: String?
    /// User preference; Apple is default. Whisper remains selectable fallback.
    var asrEnginePreference: ASREnginePreference = .appleSpeech {
        didSet {
            UserDefaults.standard.set(asrEnginePreference.rawValue, forKey: "kineto.asrEnginePreference")
            updateASREngineNotice()
        }
    }
    /// User preference for transcription language; distinct from translation and summary output.
    var recognitionLanguagePreference: RecognitionLanguagePreference = .english {
        didSet {
            UserDefaults.standard.set(
                recognitionLanguagePreference.rawValue,
                forKey: "kineto.recognitionLanguagePreference"
            )
            updateASREngineNotice()
        }
    }


    let productName = KinetoCore.productName

    private let capture = MeetingCapture()
    private let translationService = TranslationService()
    private let summaryService = SummaryService()
    private let chatService = MeetingChatService()
    private let meetingStore: MeetingPackageStore
    private let modelStore: ModelStore
    private let modelRoot: URL
    private let pickerObserver = ContentPickerObserver()
    private var activeMeeting: Meeting?
    private var coordinator: TranscriptCoordinator?
    private var applePipeline: AppleSpeechMeetingPipeline?
    private var transcriptTask: Task<Void, Never>?
    private var translationTasks: [UUID: Task<Void, Never>] = [:]
    private var chatTask: Task<Void, Never>?
    private var chatRequestID: UUID?
    private var preparedTranslationPairs: Set<String> = []
    private var recognizer: WhisperRecognizer?
    /// Optional second context so mic and selected-source do not serialize (L1).
    private var secondaryRecognizer: WhisperRecognizer?
    private var recognizerLoadTask: Task<WhisperRecognizer, Error>?
    private var recognizerModelURL: URL?
    private let appleSpeechCapability = AppleSpeechCapability()

    init() {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appending(path: "Kineto", directoryHint: .isDirectory)
        let meetings = applicationSupport.appending(path: "Meetings", directoryHint: .isDirectory)
        modelRoot = applicationSupport.appending(path: "Models", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: meetings, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: modelRoot, withIntermediateDirectories: true)
        meetingStore = MeetingPackageStore(rootURL: meetings)
        modelStore = ModelStore(rootURL: modelRoot)

        pickerObserver.onSelection = { [weak self] filter in
            self?.select(filter: filter)
        }
        pickerObserver.onFailure = { [weak self] message in
            self?.errorMessage = message
        }
        if let raw = UserDefaults.standard.string(forKey: "kineto.asrEnginePreference"),
           let preference = ASREnginePreference(rawValue: raw)
        {
            asrEnginePreference = preference
        }
        if let raw = UserDefaults.standard.string(forKey: "kineto.recognitionLanguagePreference"),
           let preference = RecognitionLanguagePreference(rawValue: raw)
        {
            recognitionLanguagePreference = preference
        }
        if let raw = UserDefaults.standard.string(forKey: "kineto.summaryTemplate"),
           let template = SummaryTemplate(rawValue: raw)
        {
            summaryTemplate = template
        }
        restorePetSettings()
        configureContentSharingPicker()
    }

    func selectPetTheme(_ theme: FloatingCaptionPetTheme) {
        isRestoringPetSettings = true
        petAppearance = theme.appearance
        petAccent = theme.defaultAccent
        isRestoringPetSettings = false
        persistPetSettings()
    }

    private func restorePetSettings() {
        let defaults = UserDefaults.standard
        let defaultPreferences = FloatingCaptionPetVisualPreferences.default
        let legacyEnabled = defaults.object(forKey: "kineto.petModeEnabled") as? Bool ?? false
        let legacyAppearance = defaults.string(forKey: "kineto.petAppearance")
            .flatMap(FloatingCaptionPetAppearance.init(rawValue:))
            ?? defaultPreferences.appearance
        let legacySize = defaults.string(forKey: "kineto.petSize")
            .flatMap(FloatingCaptionPetSize.init(rawValue:))
            ?? defaultPreferences.size
        let legacyMotion = defaults.string(forKey: "kineto.petMotion")
            .flatMap(FloatingCaptionPetMotion.init(rawValue:))
            ?? defaultPreferences.motion
        let legacyAccent = defaults.string(forKey: "kineto.petAccent")
            .flatMap(FloatingCaptionPetAccent.init(storageValue:))
            ?? defaultPreferences.accent
        let rawSnapshotData = defaults.data(forKey: Self.petSettingsKey)
        let snapshot = rawSnapshotData
            .flatMap { try? JSONDecoder().decode(PetSettingsSnapshot.self, from: $0) }

        isRestoringPetSettings = true
        defer { isRestoringPetSettings = false }
        if let snapshot, snapshot.version == PetSettingsSnapshot.currentVersion {
            petModeEnabled = snapshot.enabled ?? legacyEnabled
            petAppearance = snapshot.appearance
                .flatMap(FloatingCaptionPetAppearance.init(rawValue:))
                ?? legacyAppearance
            petSize = snapshot.size
                .flatMap(FloatingCaptionPetSize.init(rawValue:))
                ?? legacySize
            petMotion = snapshot.motion
                .flatMap(FloatingCaptionPetMotion.init(rawValue:))
                ?? legacyMotion
            petAccent = snapshot.accent
                .flatMap(FloatingCaptionPetAccent.init(storageValue:))
                ?? legacyAccent
        } else {
            petModeEnabled = legacyEnabled
            petAppearance = legacyAppearance
            petSize = legacySize
            petMotion = legacyMotion
            petAccent = legacyAccent
        }
        if rawSnapshotData == nil || snapshot.map({ $0.version <= PetSettingsSnapshot.currentVersion }) == true {
            persistPetSettings()
        }
    }

    private func persistPetSettings() {
        let snapshot = PetSettingsSnapshot(
            enabled: petModeEnabled,
            appearance: petAppearance,
            size: petSize,
            motion: petMotion,
            accent: petAccent
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: Self.petSettingsKey)
    }


    private func configureContentSharingPicker() {
        let picker = SCContentSharingPicker.shared
        var configuration = SCContentSharingPickerConfiguration()
        // Window mode is required for browser tabs/meeting windows; app/display cover the rest.
        configuration.allowedPickerModes = [.singleWindow, .singleApplication, .singleDisplay]
        configuration.allowsChangingSelectedContent = false
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            configuration.excludedBundleIDs = [bundleIdentifier]
        }
        picker.defaultConfiguration = configuration
        picker.maximumStreamCount = 1
        // Avoid double-registering if init is retried in tests/previews.
        picker.remove(pickerObserver)
        picker.add(pickerObserver)
        picker.isActive = true
    }

    func refreshCapabilities() async {
        await refreshMeetings()
        appleSpeechStatus = await appleSpeechCapability.status()
        recognitionLanguagePreference = appleSpeechStatus.normalizedPreference(
            recognitionLanguagePreference
        )
        updateASREngineNotice()

        do {
            let active = try await modelStore.activeModel(for: .whisperLargeV3TurboQ5)
            prepareRecognizer(at: active, readyStatus: "Whisper model ready · local")
            return
        } catch {}

        let developmentModel = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "Models/ggml-large-v3-turbo-q5_0.bin")
        do {
            try await modelStore.verify(developmentModel, against: .whisperLargeV3TurboQ5)
            prepareRecognizer(at: developmentModel, readyStatus: "Whisper model ready · development")
        } catch {
            recognizer = nil
            secondaryRecognizer = nil
            recognizerLoadTask?.cancel()
            recognizerLoadTask = nil
            recognizerModelURL = nil
            modelReady = false
            modelStatus = "Whisper fallback model not loaded"
            updateASREngineNotice()
        }
    }

    func installAppleSpeechAssets() async {
        guard let localeIdentifier = recognitionLanguagePreference.localeIdentifier else {
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            appleSpeechStatus = try await appleSpeechCapability.installAsset(
                localeIdentifier: localeIdentifier
            )
            updateASREngineNotice()
        } catch {
            errorMessage = "The selected Apple speech language pack could not be installed. You can switch to Whisper."
            appleSpeechStatus = await appleSpeechCapability.status()
            updateASREngineNotice()
        }
    }

    func importModel(from source: URL) async {
        isBusy = true
        defer { isBusy = false }
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        let staged = modelRoot.appending(path: ".incoming-\(UUID().uuidString).part")
        do {
            if FileManager.default.fileExists(atPath: staged.path) {
                try FileManager.default.removeItem(at: staged)
            }
            try FileManager.default.copyItem(at: source, to: staged)
            let active = try await modelStore.activate(staged, descriptor: .whisperLargeV3TurboQ5)
            prepareRecognizer(at: active, readyStatus: "Whisper model ready · local")
        } catch {
            try? FileManager.default.removeItem(at: staged)
            errorMessage = "The selected model failed size or integrity verification."
        }
    }

    func refreshMeetings() async {
        do {
            try await meetingStore.recoverInterruptedDeletions()
            let ids = try await meetingStore.meetingIDs()
            var snapshots: [MeetingSnapshot] = []
            snapshots.reserveCapacity(ids.count)
            for id in ids {
                if let snapshot = try? await meetingStore.snapshot(for: id) {
                    snapshots.append(snapshot)
                }
            }
            savedMeetings = snapshots.sorted {
                $0.meeting.createdAt > $1.meeting.createdAt
            }
        } catch {
            errorMessage = "Saved meetings could not be listed."
        }
    }

    func askCurrentMeeting(question: String) {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty,
              let meeting = activeMeeting,
              meeting.state == .stopped,
              !isGeneratingSummary,
              !isAnsweringChat else {
            return
        }

        let meetingID = meeting.id
        let language = summaryLanguage
        let requestID = UUID()
        isAnsweringChat = true
        chatRequestID = requestID
        chatTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.chatRequestID == requestID {
                    self.isAnsweringChat = false
                    self.chatTask = nil
                    self.chatRequestID = nil
                }
            }

            do {
                let snapshot = try await self.meetingStore.snapshot(for: meetingID)
                guard snapshot.meeting.state == .stopped else {
                    self.errorMessage = "Questions are available only after the meeting is stopped."
                    return
                }
                let turn = await self.chatService.answer(
                    question: trimmedQuestion,
                    from: snapshot,
                    language: language
                )
                guard !Task.isCancelled else { return }
                try await self.meetingStore.append(turn)
                guard !Task.isCancelled, self.activeMeeting?.id == meetingID else { return }
                self.chatTurns.append(turn)
                await self.refreshMeetings()
            } catch is CancellationError {
                return
            } catch {
                self.errorMessage = "The local answer could not be saved to the encrypted meeting."
            }
        }
    }

    private func cancelChat() async {
        let task = chatTask
        chatTask = nil
        chatRequestID = nil
        task?.cancel()
        await task?.value
        isAnsweringChat = false
    }

    func citationSelection(for citation: EvidenceReference) -> (Segment, String)? {
        guard let segment = segments.first(where: { $0.id == citation.segmentID }) else {
            return nil
        }
        return (segment, citation.supportingText)
    }

    func chatNoAnswerExcerpts(_ turn: ChatTurnRecord) -> [EvidenceReference] {
        turn.outcome == .noAnswer ? turn.citations : []
    }

    func chatNoAnswerDetail(_ turn: ChatTurnRecord) -> String {
        switch turn.noAnswerReason {
        case .modelUnavailable:
            "Apple Intelligence is unavailable on this Mac."
        case .unsupportedLocale:
            "The selected answer language is unavailable on this Mac."
        case .noRelevantEvidence:
            "Kineto could not find enough support in the finalized transcript."
        case .invalidGeneratedEvidence, .generationFailed:
            "Kineto could not validate a grounded answer from the finalized transcript."
        case nil:
            "Kineto could not find a grounded answer in the finalized transcript."
        }
    }

    func isChatAvailable(for meeting: Meeting?) -> Bool {
        guard let meeting else { return false }
        return meeting.state == .stopped && !segments.isEmpty
    }
    var canAskCurrentMeeting: Bool {
        isChatAvailable(for: activeMeeting)
    }

    var signalGatePresentation: SignalGatePresentation {
        SignalGatePresentation(
            phase: signalGatePhase,
            isCaptureCommandInFlight: isCaptureCommandInFlight
        )
    }

    var canEnterFloatingMode: Bool {
        capturePresentationMode == .mainWindow
            && screen == .live
            && signalGatePhase == .capturing
            && activeMeeting != nil
    }

    func enterFloatingMode() {
        guard canEnterFloatingMode else { return }
        capturePresentationMode = .floating
    }

    var floatingCaptionPetVisualPreferences: FloatingCaptionPetVisualPreferences {
        FloatingCaptionPetVisualPreferences(
            appearance: petAppearance,
            size: petSize,
            motion: petMotion,
            accent: petAccent
        )
    }

    var floatingCaptionOverlayPresentation: FloatingCaptionOverlayPresentation {
        let gatePresentation = signalGatePresentation
        guard gatePresentation.phase == .capturing,
              capturePresentationMode == .floating else {
            return .hidden
        }

        return FloatingCaptionOverlayPresentation(
            caption: .live(
                segments: segments,
                translations: translations,
                volatileTranscripts: Array(volatileTranscripts.values),
                petModeEnabled: petModeEnabled
            ),
            petVisualPreferences: floatingCaptionPetVisualPreferences,
            signalGatePresentation: gatePresentation,
            theme: petAppearance
        )
    }

    @discardableResult
    func performSignalGateAction(_ action: SignalGateAction) async -> Bool {
        guard signalGatePresentation.isActionAvailable(action) else { return false }

        switch action {
        case .pauseOrResume:
            guard !isCaptureCommandInFlight else { return false }
            await pauseOrResume()
        case .stop:
            guard !isCaptureCommandInFlight else { return false }
            await stopMeeting()
        case .showMeetingDetails:
            capturePresentationMode = .mainWindow
        }

        return true
    }

    func openMeeting(_ saved: MeetingSnapshot) async {
        signalGatePhase = .hidden
        await cancelChat()
        do {
            if saved.meeting.state == .recording || saved.meeting.state == .paused {
                let timestamp = saved.segments.map(\.endTime).max() ?? 0
                let interruption = TranscriptGap(
                    meetingID: saved.meeting.id,
                    source: .selectedSource,
                    timestamp: timestamp,
                    reason: "interrupted-relaunch"
                )
                try await meetingStore.append(interruption)
                try await meetingStore.updateState(.stopped, for: saved.meeting.id)
                recoveryNotice = "Recovered after an interrupted capture. The transcript may end early."
            } else {
                recoveryNotice = nil
            }
            let snapshot = try await meetingStore.snapshot(for: saved.meeting.id)
            activeMeeting = snapshot.meeting
            let active = snapshot.meeting.activeSources
            segments = snapshot.segments.filter { active.contains($0.source.active) }
            translations = snapshot.translations
            gaps = snapshot.gaps.filter { active.contains($0.source.active) }
            chatTurns = snapshot.chatTurns
            screen = .summary
            await refreshMeetings()
        } catch {
            errorMessage = "The encrypted meeting could not be reopened."
        }
    }

    func show(_ screen: Screen) {
        guard self.screen != .live && self.screen != .processing else { return }
        self.screen = screen
        errorMessage = nil
    }


    func newMeeting() async {
        await cancelChat()
        resetMeetingView()
        screen = .preflight
    }

    func chooseSource() {
        errorMessage = nil
        configureContentSharingPicker()
        NSApp.activate(ignoringOtherApps: true)
        SCContentSharingPicker.shared.present()
    }

    func prepareTranslation(
        _ session: TranslationSession,
        from source: SpokenLanguage,
        to target: SpokenLanguage
    ) async {
        guard translationEnabled else { return }
        let pair = "\(source.rawValue)-\(target.rawValue)"
        do {
            try await session.prepareTranslation()
            preparedTranslationPairs.insert(pair)
            translationReady = preparedTranslationPairs.count == 2
        } catch is CancellationError {
            return
        } catch {
            preparedTranslationPairs.remove(pair)
            translationReady = false
            errorMessage = "Translation language assets could not be prepared."
        }
    }

    func startMeeting() async {
        capturePresentationMode = .mainWindow
        signalGatePhase = .hidden
        guard let selectedTarget, consentGranted else {
            errorMessage = "Select a source and confirm consent first."
            return
        }
        guard !translationEnabled || translationReady else {
            errorMessage = "Wait for both local translation language pairs to finish preparing, or turn translation off."
            return
        }

        let prefersApple = asrEnginePreference == .appleSpeech
        let appleLocaleID = appleSpeechStatus.installedLocaleIdentifier(
            for: recognitionLanguagePreference
        )
        let whisperReady = recognizer != nil
        let useApple = prefersApple && appleLocaleID != nil

        if prefersApple, !useApple, whisperReady {
            asrEngineNotice = "\(appleSpeechStatus.readinessMessage(for: recognitionLanguagePreference)) This meeting uses Whisper fallback (higher lag)."
        } else if prefersApple, !useApple, !whisperReady {
            errorMessage = "\(appleSpeechStatus.readinessMessage(for: recognitionLanguagePreference)) Import Whisper to continue."
            return
        } else if !prefersApple, !whisperReady {
            errorMessage = "Whisper is selected but no verified model is loaded."
            return
        } else {
            updateASREngineNotice()
        }

        isBusy = true
        errorMessage = nil
        volatileTranscripts = [:]
        var createdMeeting: Meeting?
        do {
            if includeMicrophone {
                let authorized = await Self.requestMicrophoneAccess()
                if !authorized {
                    includeMicrophone = false
                    errorMessage = "Microphone access was denied. Continuing with selected-source audio only."
                }
            }

            let activeSources: ActiveSources = includeMicrophone ? .all : [.selectedSource]

            let meeting = Meeting(
                title: "Meeting \(Date().formatted(date: .abbreviated, time: .shortened))",
                retainsAudio: false,
                activeSources: activeSources
            )

            // CRITICAL: Create the encrypted package + key BEFORE capture or any ASR append.
            // This provisions the initial AES-GCM generation and allows later append/snapshot.
            try await meetingStore.create(meeting)
            try await meetingStore.updateState(.recording, for: meeting.id)
            createdMeeting = meeting

            let captureEvents = try await capture.start(
                target: selectedTarget,
                includeMicrophone: activeSources.contains(.you)
            )
            let transcriptEvents: AsyncStream<TranscriptEvent>

            if useApple, let localeID = appleLocaleID {
                let pipeline = AppleSpeechMeetingPipeline(
                    meetingID: meeting.id,
                    localeIdentifier: localeID,
                    language: SpokenLanguage(localeIdentifier: localeID),
                    capability: appleSpeechCapability,
                    store: meetingStore
                )
                transcriptEvents = try await pipeline.start(events: captureEvents)
                applePipeline = pipeline
                coordinator = nil
            } else {
                activeASREngine = .whisper
                guard let primary = recognizer else {
                    throw SpeechRecognitionError.modelUnavailable
                }
                let youRecognizer: WhisperRecognizer
                if activeSources.contains(.you) {
                    if let secondaryRecognizer {
                        youRecognizer = secondaryRecognizer
                    } else if let modelURL = recognizerModelURL {
                        let secondary = try WhisperRecognizer(modelURL: modelURL)
                        secondaryRecognizer = secondary
                        youRecognizer = secondary
                    } else {
                        youRecognizer = primary
                    }
                } else {
                    youRecognizer = primary   // will not be used for .you since no frames will arrive
                }
                let whisperCoordinator = TranscriptCoordinator(
                    meetingID: meeting.id,
                    recognizers: SourceRecognizerMap(
                        selectedSource: primary,
                        you: youRecognizer
                    ),
                    store: meetingStore
                )
                transcriptEvents = try await whisperCoordinator.start(events: captureEvents)
                coordinator = whisperCoordinator
                applePipeline = nil
            }

            activeMeeting = meeting
            transcriptTask = Task { [weak self] in
                guard let self else { return }
                for await event in transcriptEvents {
                    await self.consume(event)
                }
                await self.captureStreamEndedUnexpectedly()
            }
            screen = .live
            signalGatePhase = .capturing
            enterFloatingMode()
        } catch {
            if let createdMeeting {
                try? await capture.stop()
                try? await meetingStore.delete(meetingID: createdMeeting.id)
            }
            await applePipeline?.cancel()
            applePipeline = nil
            coordinator = nil
            capturePresentationMode = .mainWindow
            signalGatePhase = .hidden
            errorMessage = "The meeting could not start. Review permissions, speech engine readiness, and the selected source."
        }
        isBusy = false
    }

    func pauseOrResume() async {
        capturePresentationMode = .mainWindow
        guard !isCaptureCommandInFlight else { return }
        isCaptureCommandInFlight = true
        defer { isCaptureCommandInFlight = false }
        guard let meeting = activeMeeting else { return }
        let micForResume = meeting.activeSources.contains(.you)

        do {
            if isPaused {
                try await capture.resume(includeMicrophone: micForResume)
                do {
                    try await meetingStore.updateState(.recording, for: meeting.id)
                    isPaused = false
                    signalGatePhase = .capturing
                } catch {
                    do {
                        try await capture.pause()
                        isPaused = true
                        signalGatePhase = .paused
                    } catch {
                        isPaused = false
                        signalGatePhase = .capturing
                    }
                    throw error
                }
            } else {
                signalGatePhase = .paused
                do {
                    try await capture.pause()
                } catch {
                    signalGatePhase = .capturing
                    throw error
                }
                do {
                    try await meetingStore.updateState(.paused, for: meeting.id)
                    isPaused = true
                    signalGatePhase = .paused
                } catch {
                    do {
                        try await capture.resume(includeMicrophone: micForResume)
                        isPaused = false
                        signalGatePhase = .capturing
                    } catch {
                        isPaused = true
                        signalGatePhase = .paused
                    }
                    throw error
                }
            }
        } catch {
            errorMessage = "Capture state could not be changed safely. The control now reflects the actual capture state."
        }
    }

    func stopMeeting() async {
        capturePresentationMode = .mainWindow
        guard !isCaptureCommandInFlight else { return }
        isCaptureCommandInFlight = true
        defer { isCaptureCommandInFlight = false }
        guard let meeting = activeMeeting else { return }
        screen = .processing
        isBusy = true
        canRetryFinalization = false
        processingStatus = "Draining and sealing the source transcript…"
        var captureStopped = false
        do {
            // Source loss may already have finished capture; still drain transcript work.
            do {
                signalGatePhase = .draining
                try await capture.stop()
            } catch MeetingCaptureError.notRunning {
                // Capture already idle after source loss or prior stop.
            }
            captureStopped = true
            await transcriptTask?.value
            transcriptTask = nil
            try await finalizeStoredMeeting(meeting)
        } catch {
            if captureStopped {
                signalGatePhase = .hidden
                errorMessage = "Capture stopped, but encrypted finalization failed. Retry without resuming capture."
                canRetryFinalization = true
                screen = .processing
            } else {
                signalGatePhase = isPaused ? .paused : .capturing
                errorMessage = "Capture state could not be changed safely. The control now reflects the actual capture state."
                screen = .live
            }
        }
        isBusy = false
    }

    private func captureStreamEndedUnexpectedly() async {
        // User-initiated stop owns finalization once screen leaves .live.
        guard screen == .live, let meeting = activeMeeting else { return }
        capturePresentationMode = .mainWindow
        signalGatePhase = .draining
        screen = .processing
        isBusy = true
        recoveryNotice = "Capture source was lost. Kineto preserved the finalized transcript up to the interruption."
        processingStatus = "Sealing the preserved transcript…"
        do {
            // This method runs inside transcriptTask after its stream ended.
            // Awaiting transcriptTask here would await the current task forever.
            transcriptTask = nil
            try await finalizeStoredMeeting(meeting)
        } catch {
            signalGatePhase = .hidden
            errorMessage = "Capture ended, but encrypted finalization failed. Retry without resuming capture."
            canRetryFinalization = true
            screen = .processing
        }
        isBusy = false
    }

    private func awaitInFlightTranslations() async {
        let tasks = Array(translationTasks.values)
        for task in tasks {
            await task.value
        }
    }

    private func cancelTranslations() async {
        let tasks = Array(translationTasks.values)
        tasks.forEach { $0.cancel() }
        await translationService.cancel()
        translationTasks.removeAll(keepingCapacity: false)
    }
    private func scheduleTranslation(for segment: Segment) {
        guard translationEnabled else { return }
        guard let target = segment.language.translationTarget else { return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let translation = try await self.translationService.translate(segment, to: target)
                guard !Task.isCancelled else { return }
                if !self.translations.contains(where: {
                    $0.sourceSegmentID == translation.sourceSegmentID &&
                    $0.targetLanguage == translation.targetLanguage
                }) {
                    self.translations.append(translation)
                }
                try await self.meetingStore.append(translation, meetingID: segment.meetingID)
            } catch {
                guard !Task.isCancelled else { return }
                self.errorMessage = "A translation was deferred; the original transcript is safe."
            }
            self.translationTasks[segment.id] = nil
        }
        translationTasks[segment.id] = task
    }

    private func ensureTranslationsForSource(_ source: AudioSource) async {
        guard translationEnabled else { return }
        guard let active = activeMeeting?.activeSources, active.contains(source.active) else { return }
        // Use in-memory finalized segments for this source during live.
        // This catches the case where a final was (or will shortly be) emitted around a gap.
        let alreadyTranslated = Set(
            translations.map { "\($0.sourceSegmentID.uuidString):\($0.targetLanguage.rawValue)" }
        )
        let candidates = segments.filter { seg in
            guard seg.source == source, seg.isFinal else { return false }
            guard let target = seg.language.translationTarget else { return false }
            let key = "\(seg.id.uuidString):\(target.rawValue)"
            return !alreadyTranslated.contains(key)
        }
        for seg in candidates {
            // scheduleTranslation dedupes on the task map and inside the task body.
            scheduleTranslation(for: seg)
        }
    }

    private func reconcileMissingTranslations(for meetingID: UUID) async {
        guard translationEnabled else { return }
        processingStatus = "Reconciling unfinished translations…"
        await awaitInFlightTranslations()

        let snapshot: MeetingSnapshot
        do {
            snapshot = try await meetingStore.snapshot(for: meetingID)
        } catch {
            errorMessage = "Translation reconciliation could not read the sealed meeting package."
            return
        }
        translations = snapshot.translations

        let existing = Set(
            snapshot.translations.map { "\($0.sourceSegmentID.uuidString):\($0.targetLanguage.rawValue)" }
        )
        let pending = snapshot.segments.compactMap { segment -> (Segment, SpokenLanguage)? in
            guard let target = segment.language.translationTarget else { return nil }
            let key = "\(segment.id.uuidString):\(target.rawValue)"
            guard !existing.contains(key) else { return nil }
            return (segment, target)
        }

        guard !pending.isEmpty else { return }
        processingStatus = "Translating \(pending.count) remaining segments…"
        await withTaskGroup(of: Void.self) { group in
            for (segment, target) in pending {
                group.addTask { [weak self] in
                    guard let self else { return }
                    do {
                        let translation = try await self.translationService.translate(segment, to: target)
                        try await self.meetingStore.append(translation, meetingID: meetingID)
                        await MainActor.run {
                            if !self.translations.contains(where: {
                                $0.sourceSegmentID == translation.sourceSegmentID &&
                                $0.targetLanguage == translation.targetLanguage
                            }) {
                                self.translations.append(translation)
                            }
                        }
                    } catch {
                        await MainActor.run {
                            self.errorMessage = "Some translations remain incomplete; the original transcript is safe."
                        }
                    }
                }
            }
        }
    }

    func retryFinalization() async {
        guard canRetryFinalization, let meeting = activeMeeting else { return }
        capturePresentationMode = .mainWindow
        isBusy = true
        errorMessage = nil
        do {
            try await finalizeStoredMeeting(meeting)
        } catch {
            errorMessage = "Encrypted finalization still failed. The stopped capture will not be resumed."
            screen = .processing
        }
        isBusy = false
    }

    private func finalizeStoredMeeting(_ meeting: Meeting) async throws {
        capturePresentationMode = .mainWindow
        processingStatus = "Sealing the source transcript…"
        signalGatePhase = .processing
        defer { signalGatePhase = .hidden }
        var snapshot = try await meetingStore.snapshot(for: meeting.id)
        if snapshot.meeting.state != .stopped {
            try await meetingStore.updateState(.stopped, for: meeting.id)
            snapshot = try await meetingStore.snapshot(for: meeting.id)
        }
        canRetryFinalization = false
        activeMeeting = snapshot.meeting
        segments = snapshot.segments
        gaps = snapshot.gaps
        translations = snapshot.translations

        chatTurns = snapshot.chatTurns
        await reconcileMissingTranslations(for: meeting.id)
        snapshot = try await meetingStore.snapshot(for: meeting.id)
        translations = snapshot.translations

        // Let the user into the meeting view as soon as transcript/translations are ready.
        summary = snapshot.summary
        isGeneratingSummary = summaryEnabled && snapshot.summary == nil
        processingStatus = "Finalizing locally"
        await refreshMeetings()
        screen = .summary

        guard summaryEnabled, snapshot.summary == nil else {
            isGeneratingSummary = false
            return
        }

        await generateSummary(from: snapshot)
    }

    func regenerateSummary() async {
        guard let activeMeeting else { return }
        capturePresentationMode = .mainWindow
        signalGatePhase = .processing
        defer { signalGatePhase = .hidden }
        isGeneratingSummary = true
        do {
            let snapshot = try await meetingStore.snapshot(for: activeMeeting.id)
            await generateSummary(from: snapshot)
        } catch {
            errorMessage = "Summary could not reload the encrypted meeting package."
            isGeneratingSummary = false
        }
    }

    func template(for summary: SummaryRecord) -> SummaryTemplate {
        SummaryTemplate(rawValue: summary.templateID) ?? .executiveBrief
    }

    private func generateSummary(from snapshot: MeetingSnapshot) async {
        processingStatus = "Creating \(summaryTemplate.displayName.lowercased())…"
        defer {
            isGeneratingSummary = false
            processingStatus = "Finalizing locally"
        }
        do {
            let generated = try await summaryService.generate(
                from: snapshot,
                language: summaryLanguage,
                template: summaryTemplate
            )
            try await meetingStore.save(generated)
            summary = generated
            await refreshMeetings()
        } catch let error as SummaryServiceError {
            switch error {
            case .modelUnavailable:
                errorMessage = "Transcript saved. Apple Intelligence summary model is unavailable on this Mac."
            case .languageUnsupported:
                errorMessage = "Transcript saved. Summary language is unsupported by Apple Intelligence on this Mac."
            case .transcriptEmpty:
                errorMessage = "Transcript saved. Summary needs at least one finalized transcript segment."
            case .invalidGeneratedEvidence:
                errorMessage = "Transcript saved. Summary could not be validated against transcript evidence."
            case .meetingNotStopped:
                errorMessage = "Transcript saved. Summary requires a stopped meeting."
            }
        } catch {
            errorMessage = "Transcript saved. Summary generation failed: \(error.localizedDescription)"
        }
    }


    func exportCurrentMeeting() async {
        guard let meeting = activeMeeting else { return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Kineto-\(meeting.id.uuidString.prefix(8)).json"
        panel.title = "Export a plaintext meeting copy"
        panel.message = "The exported file is outside Kineto’s encrypted storage and deletion boundary."
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try await meetingStore.export(meetingID: meeting.id, to: destination)
        } catch {
            errorMessage = "The plaintext export could not be completed."
        }
    }

    func deleteCurrentMeeting() async {
        guard let meeting = activeMeeting else { return }
        capturePresentationMode = .mainWindow
        do {
            await cancelChat()
            if screen == .live || screen == .processing {
                // Prevent source-loss/stop finalization from racing package deletion.
                screen = .home
                signalGatePhase = .hidden
                await cancelTranslations()
                await coordinator?.cancel()
                await applePipeline?.cancel()
                coordinator = nil
                applePipeline = nil
                transcriptTask?.cancel()
                await transcriptTask?.value
                transcriptTask = nil
            }
            try await meetingStore.delete(meetingID: meeting.id)
            resetMeetingView()
            screen = .home
            await refreshMeetings()
        } catch {
            errorMessage = "The meeting could not be deleted."
        }
    }

    private func consume(_ event: TranscriptEvent) async {
        // Defensive: only accept events for sources that were active for this meeting.
        if let active = activeMeeting?.activeSources {
            switch event {
            case let .finalized(s): if !active.contains(s.source.active) { return }
            case let .volatile(v): if !active.contains(v.source.active) { return }
            case let .gap(g): if !active.contains(g.source.active) { return }
            default: break
            }
        }

        switch event {
        case let .finalized(segment):
            segments.append(segment)
            volatileTranscripts[VolatileTranscript.id(for: segment.source)] = nil
            // Approximate display lag from meeting start + segment end (meeting-relative timeline).
            if let createdAt = activeMeeting?.createdAt {
                lastTranscriptLagSeconds = max(0, Date().timeIntervalSince(createdAt) - segment.endTime)
            }
            scheduleTranslation(for: segment)
        case let .volatile(volatile):
            if volatile.text.isEmpty {
                volatileTranscripts[volatile.id] = nil
            } else {
                volatileTranscripts[volatile.id] = volatile
            }
        case let .timing(timing):
            lastRecognitionTiming = timing
        case let .gap(gap):
            gaps.append(gap)
            // A gap closes the preceding live region for the source.
            // Ensure any finalized segments (including ones just promoted or emitted around the gap)
            // get their translation scheduled even if the event order had the final slightly after the gap.
            await ensureTranslationsForSource(gap.source)
        case .failed:
            // Only reached when *both* the final segment *and* the compensating TranscriptGap
            // failed to append to the encrypted package. The interval has no ledger entry.
            errorMessage = "Failed to persist a transcript segment due to storage error. The interval is not recorded in this meeting."
        }
    }

    private func select(filter: SCContentFilter) {
        let name: String
        if let application = filter.includedApplications.first {
            name = "Application · \(application.applicationName)"
        } else if let window = filter.includedWindows.first, let title = window.title, !title.isEmpty {
            name = "Window · \(title)"
        } else if let display = filter.includedDisplays.first {
            name = "Display · \(display.displayID)"
        } else {
            name = "Selected source"
        }
        selectedTarget = CaptureTarget(name: name, filter: filter)
    }

    private func resetMeetingView() {
        capturePresentationMode = .mainWindow
        activeMeeting = nil
        coordinator = nil
        applePipeline = nil
        transcriptTask?.cancel()
        transcriptTask = nil
        translationTasks.values.forEach { $0.cancel() }
        translationTasks.removeAll(keepingCapacity: false)
        segments = []
        translations = []
        gaps = []
        volatileTranscripts = [:]
        summary = nil
        chatTask?.cancel()
        chatTask = nil
        chatRequestID = nil
        chatTurns = []
        isAnsweringChat = false
        recoveryNotice = nil
        isPaused = false
        signalGatePhase = .hidden
        canRetryFinalization = false
        consentGranted = false
        errorMessage = nil
        processingStatus = "Finalizing locally"
        isGeneratingSummary = false
        lastTranscriptLagSeconds = nil
        lastRecognitionTiming = nil
        updateASREngineNotice()
    }



    var recognitionLanguageOptions: [RecognitionLanguagePreference] {
        var options: [RecognitionLanguagePreference] = [.automatic]
            + appleSpeechStatus.locales.map {
            .apple(localeIdentifier: $0.identifier)
        }
        if !options.contains(recognitionLanguagePreference) {
            options.insert(recognitionLanguagePreference, at: 1)
        }
        return options
    }

    func recognitionLanguageDisplayName(
        _ preference: RecognitionLanguagePreference
    ) -> String {
        guard !preference.isAutomatic else { return "Automatic (Whisper)" }
        return appleSpeechStatus.locale(for: preference)?.displayName
            ?? preference.localeIdentifier
            ?? "Unknown language"
    }

    func recognitionLanguageAssetState(
        _ preference: RecognitionLanguagePreference
    ) -> LocaleAssetState? {
        appleSpeechStatus.assetState(for: preference)
    }

    var recognitionLanguageExplanation: String {
        if recognitionLanguagePreference.isAutomatic {
            return "Whisper detects the spoken language locally. Translation and summaries remain English/Vietnamese-only."
        }
        return "Apple Speech transcribes one selected installed language. Translation and summaries remain English/Vietnamese-only."
    }
    
    private func updateASREngineNotice() {
        switch asrEnginePreference {
        case .appleSpeech:
            let readiness = appleSpeechStatus.readinessMessage(for: recognitionLanguagePreference)
            if canUseAppleSpeechForRecognitionLanguage {
                asrEngineNotice = readiness
            } else if modelReady {
                asrEngineNotice = "\(readiness) Whisper is available as fallback."
            } else {
                asrEngineNotice = "\(readiness) Import Whisper to continue."
            }
        case .whisper:
            if modelReady {
                asrEngineNotice = "Whisper selected. It automatically detects supported local languages, with higher lag than Apple Speech."
            } else {
                asrEngineNotice = "Whisper is selected but no verified model is loaded."
            }
        }
    }

    var canUseAppleSpeechForRecognitionLanguage: Bool {
        appleSpeechStatus.canStart(using: recognitionLanguagePreference)
    }

    var canStartWithCurrentASR: Bool {
        switch asrEnginePreference {
        case .appleSpeech:
            canUseAppleSpeechForRecognitionLanguage || modelReady
        case .whisper:
            modelReady
        }
    }

    var shouldPromptForAppleSpeechDownload: Bool {
        asrEnginePreference == .appleSpeech &&
        appleSpeechStatus.canDownloadAsset(for: recognitionLanguagePreference)
    }

    private func prepareRecognizer(at url: URL, readyStatus: String) {
        if recognizerModelURL == url, recognizer != nil {
            return
        }
        recognizerLoadTask?.cancel()
        recognizer = nil
        secondaryRecognizer = nil
        recognizerModelURL = url
        modelReady = false
        modelStatus = "Loading Whisper model into memory…"

        let task = Task.detached(priority: .userInitiated) {
            try WhisperRecognizer(modelURL: url)
        }
        recognizerLoadTask = task
        Task { [weak self] in
            do {
                let loaded = try await task.value
                guard let self, self.recognizerModelURL == url else { return }
                self.recognizer = loaded
                self.recognizerLoadTask = nil
                self.modelReady = true
                self.modelStatus = readyStatus
                self.updateASREngineNotice()
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.recognizerModelURL == url else { return }
                self.recognizer = nil
                self.recognizerLoadTask = nil
                self.modelReady = false
                self.modelStatus = "Whisper model could not be loaded"
                self.updateASREngineNotice()
            }
        }
    }

    private static func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }
}

