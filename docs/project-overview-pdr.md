# Kineto Project Overview and Product Requirements

## Document status

- **As of:** 2026-07-18
- **Product state:** Native macOS meeting-assistant vertical slice implemented in source: runtime-supported Apple ASR locales, with EN/VI translation and summaries.
- **Release state:** Not release-ready. Twelve deterministic Core contracts plus unsigned arm64 Debug and Release builds pass locally; real-device, meeting-platform, accessibility, privacy, legal, signing, notarization, and clean-account distribution gates remain open.
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
| Summary | Post-stop English or Vietnamese summary with selectable Executive brief, Action plan, or Discussion notes structures; Foundation Models availability and locale support are checked at runtime |
| Local chat | Post-stop question-and-answer over the active stopped meeting, including after reopening. Deterministic retrieval supplies only finalized source segments plus prompt-only gap boundaries; translations, summaries, earlier turns, audio, remote providers, and other meetings never enter the model. Foundation Models runs without tools |
| Evidence | Grounded chat turns require one or more exact contiguous final-segment quotes. `noRelevantEvidence` turns carry zero citations; unavailable, unsupported, invalid-output, and generation-failure turns retain only retrieved source excerpts |
| Persistence | Authenticated AES-GCM meeting generations; per-meeting 256-bit keys stored in Keychain as device-only, available-when-unlocked items. Encrypted chat history stores question, answer/outcome/reason, and citations or excerpts |
| Library | List and reopen local meetings; explicit plaintext JSON export includes chat history and remains outside Kineto's deletion boundary; key-first deletion removes encrypted chat history with its meeting package |
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

## Functional requirements

| ID | Requirement | Current evidence |
|---|---|---|
| FR-01 | The user must manually select an application or display and manually start each session. | `AppModel.chooseSource()`, `SCContentSharingPicker`, preflight UI |
| FR-02 | Start must require a selected source, verified model, and per-session participant-notification acknowledgment. | `AppModel.startMeeting()` guards and `HomeView` preflight controls |
| FR-03 | Selected-source and optional microphone audio must remain separately labeled and timestamped. | `MeetingCapture`, `AudioFrame`, `AudioSource` |
| FR-04 | Capture must support pause, resume, stop, and confirmed deletion. | `MeetingCapture`, `AppModel`, live controls |
| FR-05 | Audio must normalize to mono 16 kHz float samples before ASR. | `AudioNormalizer`; `AudioNormalizerTests` contract |
| FR-06 | Only finalized source segments may enter durable storage. | `TranscriptCoordinator`, `MeetingPackageStore.append`; storage test rejects volatile segments |
| FR-07 | Backpressure, normalization, source-loss, and recognition failures must surface as transcript gaps rather than fabricated continuity. | `MeetingCapture`, `TranscriptCoordinator`; coordinator test persists gaps |
| FR-08 | The model must fail closed unless bytes match the pinned revision, size, and SHA-256. | `ModelDescriptor`, `ModelStore`; model mutation test |
| FR-09 | Translation must consume finalized EN/VI segments and preserve the source segment ID. | `TranslationService`, `TranslationRecord` |
| FR-10 | Summary generation must occur only after stop and must reject unsupported or unknown evidence. | `SummaryService`, `EvidenceValidator`; evidence test |
| FR-11 | Meetings must be reopenable from encrypted local storage and deletable by destroying keys before package files. | `MeetingPackageStore`, `KeychainMeetingKeyStore`; lifecycle/tamper/deletion tests |
| FR-12 | Plaintext export must be explicit and disclosed as outside Kineto's encrypted storage and deletion boundary. | `AppModel.exportCurrentMeeting()`, save-panel disclosure, atomic export test |
| FR-13 | Local chat must run only after stop, search one meeting’s finalized source ledger, validate exact citations, and persist completed turns as encrypted derived records included in explicit export and key-first deletion. | `MeetingChatService`, `MeetingPackageStore.append(_ chatTurn:)`, chat/storage tests |

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
- Meeting deletion durably tombstones intent, rejects concurrent/late mutations, removes Keychain keys before package files, and finishes interrupted tombstones on relaunch; device crash-injection evidence remains an external gate.
- Export creates an explicit plaintext copy selected by the user. That copy is outside Kineto's encryption and deletion boundary.

### Capture and consent boundaries

- Application/display selection is the truthful supported boundary; a selected browser application may include audio beyond one tab.
- The operator must acknowledge participant notification every session.
- Final launch-market wording requires counsel approval; the current copy is implementation evidence, not legal approval.

## Acceptance evidence and limits

| Acceptance area | Repository evidence | Current conclusion |
|---|---|---|
| Platform contract | `Package.swift`, `Config/Base.xcconfig`, `KinetoCoreSmokeTests` | Source/config align to macOS 26.1+, arm64, Swift 6; no build result claimed |
| Audio normalization | `AudioNormalizerTests` | Deterministic contract source exists; not executed in this pass |
| Final segment and gap persistence | `TranscriptCoordinatorTests` | Flush/persistence contract source exists; not executed in this pass |
| Encrypted lifecycle | `MeetingPackageStoreTests` | Final-only, reopen, tamper rejection, audio-off key absence, deletion, export contracts exist |
| Summary provenance | `EvidenceValidatorTests` | Unsupported owner/date text is rejected by test source |
| Model integrity | `ModelStoreTests` | Exact-size/hash activation and post-activation mutation rejection are covered |
| Native workflow | `AppModel`, `HomeView` | Home, preflight, live, processing, summary, privacy, export, and delete paths implemented |
| Real-world readiness | Phase 7 plan | Not accepted: hardware benchmarks, platform/TCC trials, counsel, security review, and notarized artifact proof are open |

No app UI test target or recorded test/build result was found in the inspected slice. The plan and all phase checklists remain marked pending/unchecked, so repository implementation must not be presented as approval of their release gates.

## Release readiness statement

Kineto is an implemented local native vertical slice, not a verified public release. Public distribution is blocked until worst-supported-device EN/VI and resource benchmarks, Zoom/Meet/Teams and TCC trials, privacy/security review, counsel-approved consent copy, independent native/model provenance checks, and exact Developer ID signing/notarization/Gatekeeper evidence are complete.

## References

- `plans/260718-1629-kineto-local-bilingual-meeting-slice/plan.md`
- `plans/260718-1629-kineto-local-bilingual-meeting-slice/phase-01-toolchain-and-scaffold.md` through `phase-07-verification-and-release.md`
- `docs/research-summary.md`
- `docs/technology-stack.md`
- `docs/design-guidelines.md`
- `Packages/KinetoCore/Sources/KinetoCore/`
- `Packages/KinetoCore/Tests/KinetoCoreTests/`
- `KinetoApp/`
