# Codebase Summary

## Overview

Kineto is a Swift 6 native macOS 26.1+ application with a thin SwiftUI/AppKit shell and a local `KinetoCore` Swift package. The implemented path is selected-source and optional-microphone capture → 16 kHz normalization → installed Apple SpeechAnalyzer streaming (volatile UI captions plus persisted final segments) or local whisper.cpp fallback → finalized source persistence → optional Apple Translation → post-stop Foundation Models summary → encrypted reopen/transcript-export/delete.

The application target is sandboxed and declares microphone plus user-selected file access for model selection, but no network client entitlement. Meetings created by the current UI set `retainsAudio` to `false`; only text-domain records are written.

## Top-Level Map

```text
Kineto/
├── KinetoApp/                 # Application entry point, orchestration, SwiftUI UI, entitlements
├── Packages/KinetoCore/      # Swift package: domain, capture, ASR, derivation, secure storage, tests
├── Binaries/                 # Local CWhisper XCFramework and recorded whisper.cpp commit
├── Models/                   # Development model plus SHA-256 sidecar
├── Config/                   # Shared Debug/Release build and export settings
├── scripts/                  # Model/runtime preparation, artifact checks, release DMG assembly
├── Kineto.xcodeproj/         # macOS app project linking local KinetoCore
├── docs/                     # Evergreen project documentation
└── plans/                    # Approved implementation plan, design assets, and research reports
```

Generated SwiftPM state under `Packages/KinetoCore/.build/` and `.swiftpm/` is not authored source.

## Application Target

| Path | Symbols / responsibility |
|---|---|
| `KinetoApp/App/KinetoApp.swift` | `KinetoApp`; creates one `AppModel`, hosts `HomeView`, defines window sizing/style, and observes `CapturePresentationMode` to reversibly order identified main `WindowGroup` windows out in floating mode or reveal them in main-window mode |
| `KinetoApp/App/AppModel.swift` | `@MainActor @Observable AppModel`; composes all Core actors, ScreenCaptureKit picker, capability checks, meeting lifecycle, live event consumption, derived-record orchestration, transcript export/delete, explicit `CapturePresentationMode`, and the sole `performSignalGateAction(_:)` authority for revalidating guarded overlay/menu actions |
| `KinetoApp/UI/FloatingCaption/` | `FloatingCaptionPanelCoordinator`, `FloatingCaptionDragSession`, `FloatingCaptionCompanionPanel`, `FloatingCaptionView`, `FloatingCaptionPresentation`, `FloatingCaptionPetCatalog`, `FloatingCaptionPetVisualPreferences`; nonactivating active-capture compact transcript subtitle bar plus tight transparent decorative AppKit child companion panel, projected only while `AppModel.capturePresentationMode == .floating`, with one persisted transcript anchor and companion placement derived from it. `FloatingCaptionPetCatalog` is an immutable five-theme catalog of distinct role-based 12×12 sprites; `FloatingCaptionOverlayPresentation` carries the active-capture projection of canonical `SignalGatePresentation`; its compact Pause, Stop & Process, and Show Meeting Details controls emit `SignalGateAction` only to `AppModel.performSignalGateAction(_:)`. Show Meeting Details returns to the existing live meeting window, not a route or second panel. The coordinator-owned transient drag session makes companion pointer drag primary: while it is held, the caption surface and controls are visually suppressed and inaccessible but its panel/frame and linked geometry stay alive, presentation delivery retains only the latest update, and that latest presentation restores immediately on end. Pause, Stop & Process, Show Meeting Details, source loss, processing, and paused Resume return to main-window mode; Use Floating Captions is the explicit active-capture re-entry. The companion is drag-only, decorative, content-free, nonactivating, and normally screen-share visible. |
| `KinetoApp/UI/Settings/CompanionSettingsView.swift` | Global Pet Mode settings: five catalog theme picker, size and motion controls, and an opaque accent picker that retains the previous valid accent when conversion fails |
| `KinetoApp/UI/Home/HomeView.swift` | `HomeView`, `TranscriptRow`, `EvidenceSheet`; navigation and home/preflight/live/processing/summary/privacy screens |
| `KinetoApp/Kineto.entitlements` | App Sandbox, audio input, user-selected read/write; no network client entitlement |

`AppModel.Screen` is the UI state surface: `.home`, `.preflight`, `.live`, `.processing`, `.summary`, and `.privacy`. `AppModel.capturePresentationMode` is the separate window-presentation state: successful Start Meeting selects `.floating`; Pause, Stop & Process, Show Meeting Details, source loss, processing, and every non-capturing state select `.mainWindow`. Resume leaves `.mainWindow`, and only Use Floating Captions from the active live meeting selects `.floating` again. `HomeView` calls model actions; it does not capture, transcribe, translate, summarize, or encrypt directly.

## KinetoCore Source Map

### Domain

| File | Primary symbols |
|---|---|
| `Domain/Meeting.swift` | `MeetingState`, `Meeting`; ready/recording/paused/stopped lifecycle and `retainsAudio` policy |
| `Domain/Segment.swift` | `SpokenLanguage`, `AudioSource`, `Segment`; timestamped transcript source record with `isFinal` |
| `Domain/TranscriptGap.swift` | `TranscriptGap`; durable record of an unavailable interval |
| `Domain/DerivedRecords.swift` | `TranslationRecord`, `EvidenceReference`, `SummaryItem`, `SummaryRecord`; records derived from source segments |

**Record authority:** finalized `Segment` values and `TranscriptGap` values form the source ledger. `TranslationRecord` references an existing `Segment.id`; `SummaryItem.evidence` references source segment UUIDs and supporting text. Translations and summaries are derived collections and never replace or mutate finalized `Segment.text`.

### Capture and Audio

| File | Primary symbols |
|---|---|
| `Capture/MeetingCapture.swift` | `CaptureTarget`, `CaptureGap`, `CaptureEvent`, `MeetingCapture`; ScreenCaptureKit selected-source audio, optional AVAudioEngine microphone, pause/resume/stop, bounded capture event stream |
| `Audio/AudioFrame.swift` | `AudioFrame`, `AudioNormalizer`; source-tagged mono, non-interleaved Float32 conversion at 16 kHz |

Screen/system audio is configured at 48 kHz stereo and normalized before ASR. Kineto excludes its own process audio. Capture conversion and source-loss failures become gap events; they do not create guessed text.

### ASR

| File | Primary symbols |
|---|---|
| `ASR/SpeechRecognizer.swift` | `SpeechRecognizing`, `SpeechRecognitionError`; recognizer boundary |
| `ASR/ASREnginePreference.swift` | `ASREnginePreference`, `AppleSpeechStatus`, `LocaleAssetState`; user preference and runtime capability state |
| `ASR/AppleSpeechCapability.swift` | `AppleSpeechCapability`; installed EN/VI SpeechTranscriber locale probe, asset request, configured transcriber creation |
| `ASR/AppleSpeechStreamer.swift` | `VolatileTranscript`, `AppleSpeechMeetingPipeline`; per-source SpeechAnalyzer input, volatile UI results, final-before-publication persistence |
| `ASR/WhisperRecognizer.swift` | `WhisperRecognizer`; actor-owned C whisper fallback context, sustained-audio admission, isolated per-chunk decoding, no-speech rejection, cancellation callback, local timestamped final segments |
| `ASR/TranscriptCoordinator.swift` | `TranscriptEvent`, `TranscriptCoordinator`; Whisper fallback discontinuity detection, per-source two-second buffering, one in-flight plus two queued jobs, persistence-before-publication, bounded backpressure gaps, end-of-capture drain |

`MeetingCapture` admits at most four system and four microphone buffers for normalization, accumulates overflow intervals, and uses a 256-event oldest-preserving output buffer with retryable gap publication. The Apple path creates one analyzer per source, keeps volatile captions in UI state only, and writes final segments before it emits them. The Whisper fallback `TranscriptCoordinator` detects timestamp discontinuities, writes each final source segment and gap through `MeetingPackageStore` before UI publication, and limits each source to one in-flight two-second job plus two queued jobs; later saturated chunks become durable `recognition-backpressure` gaps. Translation runs in separately tracked tasks during live capture and is reconciled after source sealing so unfinished translations complete before summary generation.

`AppModel` probes Apple Speech assets and defaults to Apple Speech when an EN or VI locale is installed. It preserves the explicit Whisper setting and warms a verified 574 MB Whisper context when available, removing fallback cold-start and Metal initialization from Start Meeting.
`AppModel` owns the capture presentation transition as well as meeting lifecycle. After a successful Start Meeting it enters `.floating`; `KinetoApp` orders every identified main `WindowGroup` window out with reversible `orderOut(nil)` while the linked floating caption overlay remains visible. Returning to `.mainWindow` hides the pair and reveals existing main windows without closing them. The overlay is active-capture-only, nonactivating, and normally visible in screenshots and screen sharing; no privacy claim changes. Pause, Stop & Process, Show Meeting Details, source loss, processing, and non-capturing phases return to main-window mode. Resume leaves the main window shown until explicit Use Floating Captions is chosen from the live meeting.

### Translation, Summary, and Chat

| File | Primary symbols |
|---|---|
| `Translation/TranslationService.swift` | `TranslationService`; actor-owned installed-language sessions and finalized-only English↔Vietnamese records |
| `Summary/SummaryService.swift` | `SummaryService`; stopped-meeting-only Foundation Models generation, 6,000-character chunks, maximum 24 accepted items |
| `Summary/EvidenceValidator.swift` | `EvidenceValidator`; rejects missing/unknown evidence and non-extractive text |
| `Chat/MeetingLexicalRetriever.swift` | `MeetingLexicalRetriever`; deterministic in-memory final-segment retrieval with gap boundaries |
| `Chat/MeetingChatService.swift` | `MeetingChatService`; fresh tool-free local Foundation Models question answering, strict source citations, and truthful no-answer outcomes |

SwiftUI `translationTask` sessions remain scoped to their task closures and prepare both EN↔VI asset directions before a translation-enabled meeting starts. Translation is triggered from finalized events through separately created actor-owned installed-language sessions, tracked independently, and stored idempotently per source segment and target language. Stop cancels unfinished derived translation work, seals the authoritative source transcript without waiting on external translation calls, and then runs summary generation. Summary generation uses no tools, treats transcript text as untrusted data, and emits overview/decision/action items. Local chat runs only from one stopped snapshot: it retrieves final source segments with prompt-only non-citable gap boundaries; translations, summaries, prior turns, audio, remote providers, and other meetings never enter its fresh tool-free model session. Grounded turns require literal contiguous final-segment citations; `noRelevantEvidence` turns store none, while model/output failures retain retrieved excerpts only.

### Secure Storage

| File | Primary symbols |
|---|---|
| `Storage/MeetingPackageStore.swift` | `MeetingSnapshot`, `MeetingPackageStore`; state transitions, append/save validation, AES-GCM snapshots, durable generation commits, reopen, plaintext transcript export, delete |
| `Storage/MeetingKeyStore.swift` | `MeetingKeyStore`, `KeychainMeetingKeyStore`; per-meeting encryption keys in non-synchronizing, this-device-only Keychain items |
| `Storage/AsyncMutex.swift` | `AsyncMutex`; serializes reentrant async read-modify-write transactions |

A snapshot contains `meeting`, finalized `segments`, interval-aware `gaps`, derived `translations`, an optional derived `summary`, and append-only derived `chatTurns`. Each snapshot commit encrypts `manifest.knt` and `text.knt` with AES-GCM, authenticates meeting/generation/file context, fsyncs the generation and replaceable `current` pointer, then publishes the authoritative generation in non-synchronizing Keychain metadata as the final commit step. Deletion tombstones the package, removes Keychain authority first, then removes package contents; startup recovery completes interrupted deletion without opening encrypted meeting payloads.

Plaintext JSON transcript export includes `chatTurns`. Export remains intentionally outside the encrypted package and subsequent Kineto deletion boundary; `AppModel` warns the user in the save panel.

### Model Delivery

| File | Primary symbols |
|---|---|
| `ModelDelivery/ModelDescriptor.swift` | `ModelDescriptor.whisperLargeV3TurboQ5`; immutable ID, revision, origin URL, byte count, SHA-256, license |
| `ModelDelivery/ModelStore.swift` | `ModelStore`; streaming verification, versioned atomic install/repair, durable `current` pointer, active-model revalidation, removal |

The pinned model is `ggml-large-v3-turbo-q5_0.bin` at whisper.cpp model revision `5359861c739e955e79d9a303bcbc70fb988958b1`, 574,041,195 bytes, SHA-256 `394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2`, MIT. `AppModel.importModel` stages a user-selected file and activates it only after size/hash verification. The repository `Models/` copy is a verified development fallback, not an application download. `Binaries/CWhisper.xcframework/WHISPER_CPP_COMMIT` records native runtime provenance.

## Tests

`Packages/KinetoCore/Tests/KinetoCoreTests/` contains:

| File | Contract covered |
|---|---|
| `ASREnginePreferenceTests.swift` | ASR preference copy and stable volatile transcript identities |
| `AudioNormalizerTests.swift` | Audio conversion contract |
| `ModelStoreTests.swift` | Size/hash verification, model activation, mutation rejection, and same-revision repair |
| `TranscriptCoordinatorTests.swift` | Finalized source coordination, final-tail flush, gap behavior, and timestamp-discontinuity detection |
| `WhisperRecognizerTests.swift` | Silence and brief-noise rejection plus sustained-audio admission |
| `EvidenceValidatorTests.swift` | Evidence ID and extractive-support rejection |
| `MeetingPackageStoreTests.swift` | Encrypted storage, state/record invariants, terminal source/translation rejection, reopen/export/delete behavior |
| `KinetoCoreSmokeTests.swift` | Package-level smoke surface |
| `KinetoTests/FloatingCaptionPetVisualPreferencesTests.swift` | Five built-in themes, distinct sprites, versioned settings restore/per-field fallback, opaque canonical sRGB accent normalization, and accessibility motion behavior |

This list describes test source present in the repository; it is not a claim that external release gates have passed.
Focused pet/presentation coverage passed 33 tests with 0 failures. The final full Kineto macOS XCTest suite passed 40 tests with 0 failures; this repository-local evidence does not establish physical-Mac interaction, automatic floating after Start, reversible main-window ordering, Resume re-entry, or release readiness.

## Build, Model, and Release Support

| Path | Purpose |
|---|---|
| `Packages/KinetoCore/Package.swift` | Swift tools 6.2, macOS 26.1 floor, local `CWhisper` binary target, Apple framework links |
| `Kineto.xcodeproj/project.pbxproj` | App target and local package integration |
| `Config/Base.xcconfig` | Shared build identity/version settings |
| `Config/Debug.xcconfig`, `Config/Release.xcconfig` | Configuration-specific settings |
| `Config/ExportOptions.plist` | Developer ID export configuration |
| `scripts/build-whisper-xcframework.sh` | Builds the pinned native runtime artifact |
| `scripts/download-whisper-model.sh` | Prepares the pinned development/distribution model outside app runtime |
| `scripts/verify-model-artifacts.sh` | Verifies model/runtime provenance artifacts |
| `scripts/build-release-dmg.sh` | Assembles the release disk image workflow |

## Runtime Storage Layout

```text
~/Library/Application Support/Kineto/
├── Models/
│   └── <model id>/
│       ├── current
│       └── <revision>/<model file>
└── Meetings/
    └── <meeting UUID>/
        ├── current
        └── <generation UUID>/
            ├── manifest.knt
            └── text.knt
```

Key material is not stored in these directories; `KeychainMeetingKeyStore` stores it separately in non-synchronizing, this-device-only Keychain items.

## Current Boundaries and Unproven Gates

Focused pet/presentation coverage passed 33 tests with 0 failures. The final full Kineto macOS XCTest suite passed 40 tests with 0 failures. The unsigned Debug app launched and stayed running for smoke verification. These local results establish repository contracts and startup only. The following release evidence remains externally unavailable and must not be reported as complete: worst-supported-device performance/memory benchmarks; fullscreen Zoom/Google Meet/Teams platform trials; physical-Mac compact overlay-control hit areas, VoiceOver labels/order, nonactivation, action availability, automatic floating after Start, reversible ordering of all identified main windows, immediate hide on Pause, Stop & Process, Show Meeting Details, source loss, and processing; main-window visibility after Resume and explicit Use Floating Captions re-entry; visible-pet versus header drag separation with drag-time control inaccessibility and immediate latest-presentation restoration; menu reset and paused Resume; hidden-overlay noninteraction; multi-display clamp/restore; Reduce Motion and normal screen-share overlay trials; counsel review; and Developer ID signing/notarization.

## References

- Architecture and invariants: `docs/system-architecture.md`
- Technology decisions: `docs/technology-stack.md`
- Research basis: `docs/research-summary.md`
- Approved vertical-slice plan: `plans/260718-1629-kineto-local-bilingual-meeting-slice/`
