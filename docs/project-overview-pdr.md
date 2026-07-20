# Kineto Project Overview and Product Requirements

## Document status

- **As of:** 2026-07-20
- **Product state:** Native macOS meeting-assistant vertical slice implemented in source: runtime-supported Apple ASR locales, with EN/VI translation and summaries.
- **Release state:** Not release-ready. Focused pet/presentation coverage passed 33 tests with 0 failures; the final full Kineto macOS XCTest suite passed 40 tests with 0 failures; and the unsigned Debug app launch smoke passed. Physical-Mac interaction, multi-display placement, accessibility, screen-share, meeting-platform, privacy, legal, signing, notarization, and clean-account distribution gates remain open.
- **Source of truth:** Current code and tests, reconciled with `plans/260718-1629-kineto-local-bilingual-meeting-slice/`.

## User problem

People in English/Vietnamese meetings need a transcript, cross-language reading aid, and concise follow-up without sending meeting content to a cloud service or inviting a platform bot. Existing workflows often require account-based services, upload audio, obscure the actual capture boundary, or produce summaries that cannot be traced to original speech.

Kineto addresses that problem with a manually started, local-first Mac workflow: the operator chooses an application or display, optionally includes their microphone, reviews a finalized bilingual transcript, and receives a post-stop summary whose factual items link to source evidence.

## Product outcome

A user on a supported Apple Silicon Mac can:

1. Select an application or display through the system content-sharing picker.
2. Acknowledge participant notification and the effective capture boundary for that session.
3. Capture selected-source audio and, optionally, microphone audio as distinct labeled tracks.
4. Transcribe locally with installed Apple Speech assets for live captions and final segments, or with the pinned multilingual whisper.cpp runtime when Apple Speech is unavailable or selected as the fallback.
5. Translate finalized English segments to Vietnamese and finalized Vietnamese segments to English using Apple Translation assets.
6. Stop capture before generating an English or Vietnamese summary with Apple Foundation Models.
7. Reopen, inspect, export, or delete the encrypted local meeting record.

## Supported vertical-slice scope

| Area | Supported scope in the current implementation |
|---|---|
| Platform | Native macOS 26.1+; Apple Silicon `arm64`; Swift 6 language mode |
| Capture | Manual selected-application or display audio via ScreenCaptureKit; optional microphone |
| Source labels | `Selected Source` and `You`; application/display scope remains visible |
| ASR | Apple SpeechAnalyzer/SpeechTranscriber is the default live path for a user-selected, runtime-supported macOS locale with its asset installed; volatile captions never persist. The user can select Whisper for local automatic multilingual recognition |
| Languages | Apple live ASR exposes every locale macOS reports at runtime and records the selected BCP-47 tag. Whisper remains the local automatic fallback. Translation and summaries remain EN/VI-only |
| Translation | Finalized EN→VI and VI→EN segments only; requires installed Apple Translation assets |
| Floating captions | A linked pair of automatic, nonactivating `NSPanel`s appears only when active capture is in `AppModel.capturePresentationMode == .floating`: a compact transcript subtitle bar follows below a tight transparent decorative companion AppKit child panel. Successful Start Meeting enters floating mode automatically; `KinetoApp` reversibly orders every identified main `WindowGroup` window out with `orderOut(nil)` and never closes them. The pair shares one displayed anchor, display clamp, capture lifecycle, and menu-bar Reset Caption Position action; only transcript placement persists. The active subtitle bar carries compact **Pause**, **Stop & Process**, and **Show Meeting Details** controls only when the canonical signal-gate presentation permits each action. Show Meeting Details, Pause, Stop & Process, source loss, processing, and every non-capturing phase return `capturePresentationMode` to `.mainWindow`, hide the pair, and reveal the existing live meeting window. Resume leaves the main window shown; **Use Floating Captions** exists only in that active live meeting surface and explicitly re-enters floating mode. Controls are separate from the accessible header drag region and caption text remains noninteractive. Pointer-dragging the visible companion is the primary move affordance: its frame remains under the pointer and the subtitle panel/frame remain linked, while the caption surface and controls are visually suppressed and inaccessible for the held companion drag, then restore immediately on release. The header remains the accessible fallback move handle. The panels may remain visible in screenshots and screen sharing; no privacy claim changes. |
| Pet Mode | Optional and default-off original pixel-art companion with five built-in themes—Signal Cat, Orbit Fox, Beacon Frog, Night Owl, and Meadow Rabbit—configured globally in Kineto Settings rather than meeting Preflight. During active capture its linked transparent child panel provides the primary pointer move affordance; it has no independent placement persistence. It receives non-content `FloatingCaptionPetState` plus persisted appearance, size, motion, and opaque canonical sRGB accent preferences; settings persist as a versioned Codable snapshot with independent per-field fallback for missing or invalid values. Picker colors that cannot be converted retain the prior valid accent. The pet has no capture data, transcript data, translation, audio, speaker, source application/window identity, or sentiment input; it does not retain or log data, create independent work, accept focus or content interaction, or conceal itself from screenshots or screen sharing, where it may be visible. Its arbitrary accent applies only to companion pixels, never to recording, warning, transcript, translation, focus, or action semantics. |
| Menu bar | Capture and paused status is generic and content-free; it exposes no caption text, source identity, or capture content, makes Reset Caption Position reachable, and keeps Resume available while paused |
| Summary | Post-stop English or Vietnamese summary with selectable Executive brief, Action plan, or Discussion notes structures; Foundation Models availability and locale support are checked at runtime |
| Local chat | Post-stop question-and-answer over the active stopped meeting, including after reopening. Deterministic retrieval supplies only finalized source segments plus prompt-only gap boundaries; translations, summaries, earlier turns, audio, remote providers, and other meetings never enter the model. Foundation Models runs without tools |
| Evidence | Grounded chat turns require one or more exact contiguous final-segment quotes. `noRelevantEvidence` turns carry zero citations; unavailable, unsupported, invalid-output, and generation-failure turns retain only retrieved source excerpts |
| Persistence | Authenticated AES-GCM meeting generations; per-meeting 256-bit keys are stored in Keychain as device-only, available-when-unlocked items. Encrypted chat history stores question, answer/outcome/reason, and citations or excerpts |
| Library | List and reopen local meetings; explicit plaintext JSON export includes chat history and remains outside Kineto's deletion boundary. Key-first deletion removes encrypted meeting data and the meeting package |
| Audio retention | **Off in this supported slice.** The app creates meetings with `retainsAudio: false`; no retained-audio sink is wired into the app workflow |
| Network | The main app entitlement file contains no network-client or network-server entitlement; model import is user-selected and locally size/hash verified |
| Distribution target | Direct Developer ID distribution, subject to the open release gates below |

## Explicit non-goals

The current vertical slice does not provide:

- Cloud transcription, cloud translation, cloud summaries, synchronization, analytics, or accounts.
- Meeting-platform bots, automatic meeting joining, or automatic recording start/resume.
- Diarization, speaker identity inference, or relabeling mixed source audio as a specific participant.
- Browser-tab audio isolation; application selection may include sibling browser/process audio.
- Autonomous actions, tools, calendar changes, messages, or task execution from meeting content.
- A localhost model server, downloadable executable code, plug-ins, or mutable remote model manifests.
- Intel Mac support or operating systems earlier than macOS 26.1.
- Retained raw audio in the current app workflow.
- A claim that the app activates Zoom, Google Meet, or Teams recording indicators.
- Public-release readiness until every external gate is evidenced.
- An independently positioned or persisted companion panel, companion intelligence, or any Pet Mode reaction to transcript/caption text, translations, audio, speakers, source identities, or sentiment.

## Functional requirements

| ID | Requirement | Current evidence |
|---|---|---|
| FR-01 | The user must manually select an application or display and manually start each session. | `AppModel.chooseSource()`, `SCContentSharingPicker`, preflight UI |
| FR-02 | Start must require a selected source, verified model, and per-session participant-notification acknowledgment. | `AppModel.startMeeting()` guards and `HomeView` preflight controls |
| FR-03 | Selected-source and optional microphone audio must remain separately labeled and timestamped. | `MeetingCapture`, `AudioFrame`, `AudioSource` |
| FR-04 | Capture must support pause, resume, stop-and-process, and confirmed deletion; successful Start Meeting automatically enters the floating caption presentation mode, while Pause, Stop & Process, Show Meeting Details, source loss, processing, and non-capturing states return to the main window and hide the pair. Resume remains available from the live meeting and menu bar while paused, leaves the main window shown, and requires explicit Use Floating Captions from the live meeting to re-enter floating mode. | `MeetingCapture`, `AppModel`, `KinetoApp`, live controls |
| FR-05 | Audio must normalize to mono 16 kHz float samples before ASR. | `AudioNormalizer`; `AudioNormalizerTests` contract |
| FR-06 | Only finalized source segments may enter durable storage. | `TranscriptCoordinator`, `MeetingPackageStore.append`; storage test rejects volatile segments |
| FR-07 | Backpressure, normalization, source-loss, and recognition failures must surface as transcript gaps rather than fabricated continuity. | `MeetingCapture`, `TranscriptCoordinator`; coordinator test persists gaps |
| FR-08 | The model must fail closed unless bytes match the pinned revision, size, and SHA-256. | `ModelDescriptor`, `ModelStore`; model mutation test |
| FR-09 | Translation must consume finalized EN/VI segments and preserve the source segment ID. | `TranslationService`, `TranslationRecord` |
| FR-10 | Summary generation must occur only after stop and must reject unsupported or unknown evidence. | `SummaryService`, `EvidenceValidator`; evidence test |
| FR-11 | Meetings must be reopenable from encrypted local storage and deletable by destroying keys before package files. | `MeetingPackageStore`, `KeychainMeetingKeyStore`; lifecycle/tamper/deletion tests |
| FR-12 | Plaintext transcript export must be explicit and disclosed as outside Kineto's encrypted storage and deletion boundary. | `AppModel.exportCurrentMeeting()`, save-panel disclosure, atomic export test |
| FR-13 | Local chat must run only after stop, search one meeting’s finalized source ledger, validate exact citations, and persist completed turns as encrypted derived records included in explicit export and key-first deletion. | `MeetingChatService`, `MeetingPackageStore.append(_ chatTurn:)`, chat/storage tests |
| FR-14 | During active capture, the compact transcript subtitle bar and tight transparent companion child panel must remain linked above/below one shared persisted transcript anchor and render only when `AppModel.capturePresentationMode == .floating`. Successful Start Meeting selects floating mode and `KinetoApp` reversibly orders every identified main `WindowGroup` window out; `.mainWindow` hides the pair and reveals those windows without closing them. The subtitle bar receives the canonical signal-gate presentation and renders compact Pause, Stop & Process, and Show Meeting Details controls only when that snapshot permits them; actions route through `AppModel` for revalidation, and Show Meeting Details returns to the existing live meeting window rather than a new route or panel. Pause, Stop & Process, source loss, processing, and non-capturing states also return to `.mainWindow`; Resume leaves the main window shown, and only Use Floating Captions from the active live meeting explicitly re-enters floating mode. Controls are separate from the accessible header drag region and caption text remains actionless. Pointer-dragging the visible companion is the primary move affordance: its frame remains under the pointer and the subtitle panel/frame remain linked, while the caption surface and controls are visually suppressed and inaccessible for the held companion drag and restore immediately on release. The header is the accessible fallback move handle; the companion remains drag-only, decorative, content-free, and normally visible in screenshots and screen sharing.

## Non-functional requirements

| ID | Requirement | Boundary or status |
|---|---|---|
| NFR-01 | The capture application must have no unrestricted network entitlement. | Present in `Kineto.entitlements`; release entitlement inspection remains required |
| NFR-02 | Meeting processing must remain local and continue without network access after required assets are installed. | Architectural boundary implemented; offline end-to-end trial remains required |
| NFR-03 | Capture callbacks and streams must be bounded so ML does not block capture. | Async stream buffering is bounded; saturation behavior needs real-load proof |
| NFR-04 | Source records must be append-only and derived records must reference source IDs. | Store guards and authenticated manifest validation implemented |
| NFR-05 | Local meeting content must fail closed on ciphertext or authenticated-context mutation. | AES-GCM and mutation test evidence |
| NFR-06 | Raw-audio-off sessions must create no audio key or audio artifact. | App always sets audio retention off; storage test proves no audio key |
| NFR-07 | Summary work must never use tools or side effects and must treat transcript text as untrusted data. | `LanguageModelSession` is created with `tools: []` and explicit instructions |
| NFR-08 | Capture/finalized ASR outrank translation and summary under constrained resources. | Pipeline ordering reflects this; worst-device load evidence remains open |
| NFR-09 | UI must use native macOS semantics and remain operable with keyboard, VoiceOver, reduced motion, and light/dark appearances. | Native SwiftUI/AppKit implementation exists; accessibility/UI trials remain open |
| NFR-10 | Release must use Hardened Runtime and an exact signed, notarized, stapled DMG accepted by Gatekeeper. | Release configuration/scripts exist; artifact proof is absent |

## Privacy and data boundaries

### Data that remains on the Mac

- In-memory selected-source and microphone PCM used for local inference.
- UI-only volatile Apple Speech captions, discarded on finalization or stop.
- Final transcript segments, visible gap records, translations, summaries, and evidence links.
- Imported Whisper model assets in Application Support.
- Authenticated encrypted meeting packages and device-only Keychain keys.

### Network boundary

- `Kineto.entitlements` enables the App Sandbox, audio input, and user-selected file access only; it does not declare network-client/server access.
- Meeting inference does not require a network endpoint.
- The implemented app imports model bytes through a user-selected file and verifies exact size and SHA-256 locally.
- Repository download scripts are development/release tooling, not proof that the shipping app can safely download assets.

### Raw audio boundary

- Raw audio retention is disabled in the current supported app path.
- Audio is not written to disk in this path. Capture-event buffering is bounded, but end-to-end peak memory and saturation behavior still require measured proof.
- The broader approved plan describes optional directly encrypted retention, but that sink is not implemented in the app workflow and is not claimed here.

### Storage, deletion, and export boundaries

- Meeting generations and manifests are AES-GCM authenticated with meeting/generation/file context.
- Per-meeting keys use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and do not synchronize.
- Meeting deletion durably tombstones intent, rejects concurrent/late mutations, removes meeting keys before package files, and finishes interrupted tombstones on relaunch; device crash-injection evidence remains an external gate.
- Plaintext transcript export creates an explicit user-selected copy, outside Kineto's encryption and deletion boundary.

### Capture and consent boundaries

- Application/display selection is the truthful supported boundary; a selected browser application may include audio beyond one tab.
- The operator must acknowledge participant notification every session.
- The automatic floating caption overlay is a linked pair of nonactivating `NSPanel`s projected only for active capture while `AppModel.capturePresentationMode == .floating`: a compact transcript subtitle bar follows below a tight transparent decorative companion AppKit child panel. During active capture, the pair shares one transcript anchor, display clamp, lifecycle, and menu-bar Reset Caption Position action; only the transcript anchor persists. Successful Start Meeting enters floating mode and `KinetoApp` reversibly orders identified main `WindowGroup` windows out without closing them. The subtitle bar renders compact Pause, Stop & Process, and Show Meeting Details controls only when the canonical signal-gate presentation permits them; they are separate from the accessible header drag handle, caption text remains noninteractive, and Show Meeting Details returns to the existing live meeting window rather than a new route or panel. Pause, Stop & Process, source loss, processing, and non-capturing states return the mode to `.mainWindow`, hide the pair, and reveal the main window. Resume leaves the main window shown; Use Floating Captions exists only in the active live meeting surface and is the explicit re-entry path. Pointer-dragging the companion is the primary move affordance: its frame remains under the pointer and the subtitle panel/frame remain linked, while the caption surface and controls are suppressed and inaccessible for the held companion drag, then restore immediately on release. Header-initiated dragging keeps the caption surface visible. The panels retain normal screenshot and screen-share visibility; no privacy claim changes.
- Pet Mode is optional and default-off, is configured globally in Kineto Settings, is a decorative active-capture-only pixel-art companion with five immutable built-in themes—Signal Cat, Orbit Fox, Beacon Frog, Night Owl, and Meadow Rabbit—and receives non-content `FloatingCaptionPetState` plus persisted appearance, size, motion, and opaque canonical sRGB accent preferences. Settings use a versioned Codable snapshot with per-field fallback; failed color-picker conversion retains the prior valid accent. Its sole interaction is the pointer move affordance; it has no independent placement persistence, capture data, transcript data, content, audio, speaker, source-identity, or sentiment access; no focus, data retention/logging, or independent work; and shares the transcript panel's normal screenshot/screen-share visibility. Its arbitrary accent applies only to companion pixels, never to recording, warning, transcript, translation, focus, or action semantics.
- The capture and paused menu-bar status remains generic and content-free; it does not expose caption text, source identity, or capture content, and keeps Reset Caption Position and paused Resume reachable.
- Final launch-market wording requires counsel approval; the current copy is implementation evidence, not legal approval.

## Acceptance evidence and limits

| Acceptance area | Repository evidence | Current conclusion |
|---|---|---|
| Platform contract | `Package.swift`, `Config/Base.xcconfig`, `KinetoCoreSmokeTests` | Source/config align to macOS 26.1+, arm64, Swift 6; no build result claimed |
| Audio normalization | `AudioNormalizerTests` | Deterministic contract source exists; not executed in this pass |
| Final segment and gap persistence | `TranscriptCoordinatorTests` | Flush/persistence contract source exists; not executed in this pass |
| Encrypted lifecycle | `MeetingPackageStoreTests` | Meeting encryption, export, deletion, and recovery contracts are covered by repository tests |
| Summary provenance | `EvidenceValidatorTests` | Unsupported owner/date text is rejected by test source |
| Model integrity | `ModelStoreTests` | Exact-size/hash activation and post-activation mutation rejection are covered |
| Pet/presentation behavior | `KinetoTests/FloatingCaptionPetVisualPreferencesTests.swift` and focused presentation tests | Focused pet/presentation coverage passed: 33 tests, 0 failures |
| Native workflow | `AppModel`, `HomeView`, `FloatingCaptionView`, `KinetoApp` | Final full Kineto macOS XCTest suite passed: 40 tests, 0 failures; unsigned Debug app launch smoke passed. This is not physical-Mac interaction evidence |
| Real-world readiness | Phase 7 plan | Not accepted: hardware benchmarks, fullscreen Zoom/Meet/Teams and TCC trials, automatic floating after Start, reversible main-window ordering, Use Floating Captions availability and Resume re-entry, compact-control hit-area and action-availability checks, VoiceOver labels/order for Pause, Stop & Process, Show Meeting Details, and Use Floating Captions, nonactivation while invoking controls, immediate full-overlay hide on pause/stop/Show Details/source loss/processing, companion-versus-header drag separation and drag-time control inaccessibility, menu reset and paused Resume, multi-display clamp/restore, screen-share overlay trials, counsel, security review, and notarized artifact proof remain open |

The supplied local test and Debug launch results establish repository contracts and startup only. They do not establish real-device compact-control hit areas, availability, VoiceOver order/labels, nonactivation, automatic floating after Start, reversible ordering of all identified main windows, immediate full-overlay hide on Pause, Stop & Process, Show Meeting Details, source loss, or processing, Resume leaving the main window shown, explicit Use Floating Captions re-entry, or Show Meeting Details revealing the current live window; nor do they establish companion/header drag separation, drag-time control inaccessibility, reset, paused Resume, hidden-overlay noninteraction, multi-display clamp/restore, accessibility, Reduce Motion, fullscreen meeting-app, or screen-share behavior. Those physical-device validation gates remain open.


## Release readiness statement

Kineto is an implemented local native vertical slice, not a verified public release. Public distribution is blocked until worst-supported-device EN/VI and resource benchmarks; fullscreen Zoom/Meet/Teams and TCC trials; compact-control hit-area, VoiceOver, nonactivation, immediate pause/stop hide, and current-live-window reveal validation; companion/header drag separation, drag-time control inaccessibility, menu reset, paused Resume, hidden-overlay noninteraction, multi-display clamp/restore, Reduce Motion, and screen-share overlay validation; privacy/security review; counsel-approved consent copy; independent native/model provenance checks; and exact Developer ID signing/notarization/Gatekeeper evidence are complete.

## References

- `plans/260718-1629-kineto-local-bilingual-meeting-slice/plan.md`
- `plans/260718-1629-kineto-local-bilingual-meeting-slice/phase-01-toolchain-and-scaffold.md` through `phase-07-verification-and-release.md`
- `docs/research-summary.md`
- `docs/technology-stack.md`
- `docs/design-guidelines.md`
- `Packages/KinetoCore/Sources/KinetoCore/`
- `Packages/KinetoCore/Tests/KinetoCoreTests/`
- `KinetoApp/`
