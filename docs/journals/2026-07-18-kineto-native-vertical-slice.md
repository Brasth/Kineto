---
date: 2026-07-18
topic: Kineto native macOS vertical slice
status: implemented-local-slice-release-gates-open
---

# Kineto Native Vertical Slice

## Context

Kineto now has a source-complete native macOS 26.1+ vertical slice for local English/Vietnamese meeting capture, transcription, translation, evidence-linked summary, encrypted reopen, plaintext export, and deletion.
The boundary is deliberately narrow: Apple Silicon `arm64`, manual capture, no account or cloud path, and raw-audio retention disabled in the app workflow.
“Implemented” here means the source, configuration, test contracts, and recorded local smoke evidence exist; it does not mean Phase 7 release acceptance is complete.
This journal pass inspected repository evidence but did not rerun builds, tests, scripts, or UI scenarios.

## Decisions

### Local-first architecture

- `KinetoApp` is a thin SwiftUI/AppKit orchestration layer over the local `KinetoCore` Swift package.
- The sandbox entitlement grants audio input and user-selected file access but no network client/server entitlement.
- ScreenCaptureKit, AVFoundation, Apple Translation, Foundation Models, CryptoKit, and Keychain provide the platform boundary; meeting processing stays in the app process and local storage.
- The application does not download a model. A user-selected model is copied from a security-scoped URL and activated only after exact local verification.
- Finalized `Segment` and `TranscriptGap` records are authoritative. Translation and summary records remain separate derived collections linked to source IDs.

### Pinned Whisper runtime and model delivery

- The sole production ASR path is local `whisper.cpp`; translation is disabled in Whisper so Apple Translation remains the dedicated translation path.
- `ModelDescriptor.whisperLargeV3TurboQ5` pins `ggml-large-v3-turbo-q5_0.bin` to 574,041,195 bytes and SHA-256 `394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2`.
- The native XCFramework provenance is pinned to whisper.cpp commit `f049fff95a089aa9969deb009cdd4892b3e74916`.
- `ModelStore` streams verification, stages imports as partial files, re-verifies after copy, synchronizes bytes, and atomically switches the active pointer.
- `activeModel` rechecks pointer, size, and digest before recognition; failed imports are removed and never activated.
- `scripts/verify-model-artifacts.sh` also fixes expected hashes for the archive, public header, and XCFramework metadata, then checks `arm64`, required symbols, provenance, and notices.

### Source-separated bounded capture

- ScreenCaptureKit captures the selected application or display as `Selected Source`; an optional AVAudioEngine microphone tap remains a separate `You` track.
- Callback-owned audio is copied before crossing concurrency boundaries, normalized to mono non-interleaved Float32 at 16 kHz, and never mislabeled as a participant identity.
- System and microphone normalization each use four-slot admission; the event stream preserves the oldest 256 accepted events while overflow intervals are coalesced and retried as durable gaps. Conversion failures, source loss, and timestamp discontinuities likewise become source- and interval-aware gaps instead of fabricated continuity.
- `TranscriptCoordinator` buffers eight-second chunks per source, permits one in-flight recognition job plus two queued jobs per source, and records later saturation as `recognition-backpressure` gaps.
- A gap cuts the current source buffer, preventing recognition from joining speech across missing PCM.
- Final segments and gaps are persisted before UI publication. Stop rejects further capture, drains accepted normalization and recognition work, flushes the final tail, and only then closes the transcript.
- Translation runs in separately tracked tasks, so derived work cannot block capture-event consumption or source persistence.

### Translation and Foundation Models

- SwiftUI `translationTask` prepares EN→VI and VI→EN assets only after explicit preflight intent; its framework-owned session is never retained beyond the task closure.
- `TranslationService` creates actor-owned installed-language sessions for finalized English or Vietnamese source segments, preserves the source segment ID, and stores target-language results idempotently.
- Stop cancels unfinished derived translation tasks without awaiting external framework calls, seals the authoritative source meeting as stopped, and only then starts summary generation.
- `SummaryService` uses Apple Foundation Models with runtime availability gating, no tools, transcript-as-untrusted-data instructions, bounded 6,000-character chunks, and at most 24 accepted items.
- `EvidenceValidator` requires existing source IDs and exact contiguous support. Invalid overview, decision, or action fields are omitted independently rather than converting unsupported text into fact.
- Translation or summary failure preserves the finalized source ledger and reports truthful local unavailability.

### Encrypted storage and lifecycle hardening

- Each meeting snapshot is AES-GCM encrypted with additional authenticated data binding the meeting, generation, and file identity.
- Per-meeting 256-bit keys live in non-synchronizing, available-when-unlocked, this-device-only Keychain items.
- Creation uses a hidden sibling stage, synchronization, and atomic exposure so an incomplete package is not presented as a meeting.
- Commits write and synchronize immutable generations, durably advance the replaceable `current` pointer, then publish authoritative Keychain generation metadata as the final commit step.
- Keychain generation authority prevents replay through restoration of an older `current` file; authentication, topology, identity, decoding, and finalized-record violations fail closed.
- `AsyncMutex` serializes async read-modify-write transactions that actor reentrancy could otherwise interleave.
- Deletion first durably records a tombstone, destroys text/audio keys, then removes package bytes; launch recovery completes interrupted tombstones.
- Stopped meetings reject late segments, gaps, and translations, closing stale-producer paths after stop or delete.
- Relaunch converts interrupted recording/paused state into a durable interruption gap and stopped snapshot rather than silently resuming capture.
- Plaintext JSON export is atomic and explicitly outside Kineto’s encrypted storage and subsequent deletion boundary.
- Raw-audio retention remains off (`retainsAudio: false`); no retained-audio sink, audio key, or audio artifact is claimed for the implemented workflow.

## Native workflow outcome

- `AppModel` drives six native states: Home, Preflight, Live, Processing, Summary, and Privacy.
- The system content-sharing picker is restricted to one application or one display; the effective source boundary stays explicit.
- Preflight requires a verified model, selected source, and per-session participant-notification acknowledgment; microphone denial degrades to selected-source-only capture.
- Live supports pause/resume, stop, visible transcript gaps, original-first transcript rows, and subordinate translation.
- Processing drains source work and translations before the stopped snapshot and optional summary.
- Summary/library supports encrypted reopen, evidence inspection, explicit plaintext export, and confirmed deletion.
- Source loss and interrupted relaunch preserve finalized work and surface a recovery notice instead of implying completeness.

## Specialist-review fixes incorporated

The 2026-07-18 red-team review recorded 15 accepted corrections. The delivered slice visibly incorporates the corrections that could be closed in repository code:

- model networking is absent from the meeting process, while model/runtime provenance is pinned and locally verified;
- native callback lifetimes are owned, inference queues are bounded, gaps are durable, and the recognizer tail is drained;
- storage gained staged generations, authenticated topology, Keychain-authoritative rollback defense, terminal late-record rejection, and deletion tombstone recovery;
- translation was removed from the capture-critical path, summary fields gained extractive support validation, and unsupported fields fail independently;
- a recording-time SIGTRAP caused by reusing an expired SwiftUI Translation session was reproduced from the macOS crash report and removed by separating in-scope asset preparation from actor-owned live translation;
- the UI preserves actual application/display scope, interruption state, local-processing truth, and plaintext-export boundaries;
- the artifact verifier now checks exact model/runtime bytes, architecture, symbols, metadata, provenance, and notices;
- the release script encodes exact-DMG signing, notarization, stapling, Gatekeeper, and digest steps without claiming credentials or acceptance.

Two review concerns remain intentionally outside the completion claim: encrypted retained audio was not wired and is therefore disabled, and worst-device ASR/summary viability still requires measurement.

## Observed verification evidence

The project roadmap records 14 passing Swift Testing contracts across seven files, covering package smoke/minimum OS, audio normalization, Whisper silence/brief-noise rejection, transcript tail/gaps/discontinuities, encrypted lifecycle, mutation rejection, export, terminal source/translation rejection, generation rollback defense, deletion recovery, evidence rejection, and model mutation/repair.
Observed local evidence also includes arm64 Debug and Release builds, a system-picker trial excluding Kineto while exposing other windows/displays, a warmed Start Meeting transition measured at 0.598 seconds, live selected-source YouTube transcription with EN→VI translation, local Whisper inference and silence-hallucination probes, Foundation Models capability gating, and a passing strengthened model/XCFramework artifact verifier.
The source tree contains the local package tests, checked-in XCFramework, pinned model and digest, Debug/Release configuration, and release assembly scripts supporting those records.
These are development and repository-local observations, not evidence for a distributable release.

## Risks and open release gates

- **Signing/notarization:** no user-owned Developer ID certificate, private key, team state, notary profile, Apple `Accepted` result, stapler validation, Gatekeeper result, or exact published DMG digest is proven.
- **Clean account:** no quarantined exact-DMG install and offline end-to-end workflow has been recorded on a clean user account.
- **Real platforms:** Zoom, Google Meet, and Microsoft Teams capture boundaries, TCC grant/denial/revocation, topology loss, lock/sleep/wake, pause/resume, mic-only fallback, and saturation behavior remain unproven on real workflows.
- **Accessibility:** keyboard traversal, VoiceOver, focus order, contrast/appearance variants, compact layouts, reduced motion/transparency, and announcements have not completed an accessibility matrix.
- **Worst device:** no recorded EN WER, VI CER, code-switch accuracy, real-time factor, latency, memory, swap, thermal, model-load, or cancellation matrix exists for the worst intended 8 GB and 16 GB Apple Silicon tiers.
- **Apple framework matrix:** clean-account Translation asset installation/offline reuse and Foundation Models EN/VI availability, cancellation, context-limit, and unavailable fallbacks remain unproven across supported devices.
- **Crash/security:** full crash-point injection, locked/post-reboot Keychain trials, interrupted export trials, and independent encrypted-package review remain open despite deterministic lifecycle contracts.
- **Privacy canary:** no release-mode traffic inspection or forced-error/crash sweep has shown canary transcript, prompt, source-name, and path values absent from logs, diagnostics, analytics, and crash metadata.
- **Counsel:** launch-market recording/capture obligations, exact participant-notification copy, and per-session acknowledgment language have not received external counsel approval.

## Outcome

The repository now supports a coherent local native vertical slice with explicit trust boundaries, bounded source processing, provenance-checked inference, source-linked derivation, and fail-closed encrypted persistence.
The next milestone is evidence production, not feature expansion: close the hardware, platform, accessibility, clean-account, privacy, counsel, signing, notarization, and exact-artifact gates before describing Kineto as release-ready.
