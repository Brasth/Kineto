# Codebase Summary

## Overview

Kineto is a Swift 6 native macOS 26.1+ application with a thin SwiftUI/AppKit shell and a local `KinetoCore` Swift package. The implemented path is selected-source and optional-microphone capture → 16 kHz normalization → installed Apple SpeechAnalyzer streaming (volatile UI captions plus persisted final segments) or local whisper.cpp fallback → finalized source persistence → optional Apple Translation → post-stop Foundation Models summary → encrypted reopen/export/delete.

The application target is sandboxed and declares microphone plus user-selected file access, but no network client entitlement. Meetings created by the current UI set `retainsAudio` to `false`; only text-domain records are written.

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
| `KinetoApp/App/KinetoApp.swift` | `KinetoApp`; creates one `AppModel`, hosts `HomeView`, defines window sizing/style |
| `KinetoApp/App/AppModel.swift` | `@MainActor @Observable AppModel`; composes all Core actors, ScreenCaptureKit picker, capability checks, meeting lifecycle, live event consumption, derived-record orchestration, export/delete |
| `KinetoApp/UI/Home/HomeView.swift` | `HomeView`, `TranscriptRow`, `EvidenceSheet`; navigation and home/preflight/live/processing/summary/privacy screens |
| `KinetoApp/Kineto.entitlements` | App Sandbox, audio input, user-selected read/write; no network client entitlement |

`AppModel.Screen` is the UI state surface: `.home`, `.preflight`, `.live`, `.processing`, `.summary`, and `.privacy`. `HomeView` calls model actions; it does not capture, transcribe, translate, summarize, or encrypt directly.

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
| `Storage/MeetingPackageStore.swift` | `MeetingSnapshot`, `MeetingPackageStore`; state transitions, append/save validation, AES-GCM snapshots, durable generation commits, reopen, plaintext export, delete |
| `Storage/MeetingKeyStore.swift` | `MeetingKeyStore`, `KeychainMeetingKeyStore`; per-meeting 256-bit text/audio keys in non-synchronizing, this-device-only Keychain items |
| `Storage/AsyncMutex.swift` | `AsyncMutex`; serializes reentrant async read-modify-write transactions |

A snapshot contains `meeting`, finalized `segments`, interval-aware `gaps`, derived `translations`, an optional derived `summary`, and append-only derived `chatTurns`. Legacy v1 snapshots decode with empty chat history; a later chat append writes a v2 manifest with ordered `chatTurnIDs`. Each commit encrypts `manifest.knt` and `text.knt` with AES-GCM, authenticates meeting/generation/file context, fsyncs the generation and replaceable `current` pointer, then publishes the authoritative generation in non-synchronizing Keychain metadata as the final commit step. Deletion is serialized with mutations, first persists a tombstone, rejects later writes, deletes text/audio keys, removes package bytes, and clears the tombstone; launch recovery finishes interrupted creation/deletion. The current app neither retains nor writes raw audio.

Plaintext JSON export includes `chatTurns` and remains intentionally outside the encrypted package and subsequent Kineto deletion boundary; `AppModel` warns the user in the save panel. Key-first deletion removes only the encrypted meeting package and its chat history.

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

This list describes test source present in the repository; it is not a claim that external release gates have passed.

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

Key material is not stored in these directories; `KeychainMeetingKeyStore` stores it under service `com.huynguyen.Kineto.meeting-key` with accounts `<meeting UUID>.text` and `<meeting UUID>.audio`.

## Current Boundaries and Unproven Gates

Implemented code establishes the native local path, record separation, encrypted persistence, model verification, and UI orchestration. The following release evidence remains externally unavailable and must not be reported as complete: worst-supported-device performance/memory benchmarks, Zoom/Google Meet/Teams platform trials, counsel review, and Developer ID signing/notarization proof.

## References

- Architecture and invariants: `docs/system-architecture.md`
- Technology decisions: `docs/technology-stack.md`
- Research basis: `docs/research-summary.md`
- Approved vertical-slice plan: `plans/260718-1629-kineto-local-bilingual-meeting-slice/`
