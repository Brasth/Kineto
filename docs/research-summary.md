---
title: Kineto Bootstrap Research Summary
status: proposed
researched: 2026-07-18
scope: local English/Vietnamese macOS meeting assistant
---

# Kineto Bootstrap Research Summary

## Approved product contract

- Native Apple Silicon macOS app; minimum macOS 26.1.
- Tiered 8/16 GB support.
- Manual selected-application or display audio capture; microphone optional.
- Automatic bilingual English/Vietnamese transcription.
- Translate finalized segments EN→VI or VI→EN.
- Post-meeting summary in one user-selected language.
- Speaker labels `You` and `Selected Source`; use `Meeting` only after isolation proof.
- Raw audio retention optional per meeting; off by default.
- Verified local model download only if the selected ASR engine needs external weights; inference remains local.
- Direct Developer ID notarized distribution first.
- No cloud, accounts, Hermes, diarization, platform bots, or autonomous actions.

## Platform decision

- Checked-in `Kineto.xcodeproj`: one SwiftUI app target plus one local `KinetoCore` Swift package; add one model-only downloader XPC target only if the selected ASR needs external weights.
- Xcode owns app/helper bundles, entitlements, archive, signing, and notarization; SwiftPM owns Core compilation/tests and conditional local inference targets.
- No XcodeGen/Tuist, GRDB/SQLCipher, WhisperKit, localhost model server, ORM, or dependency-injection framework.
- `arm64` only; `MACOSX_DEPLOYMENT_TARGET = 26.1`.
- ScreenCaptureKit captures app/display audio and microphone as separate timestamped tracks.
- Application selection is the finest reliable audio boundary; browser-window selection cannot isolate one tab/window’s audio.
- Use `SCContentSharingPicker`; no Accessibility, process injection, virtual audio driver, or private API.
- First screen-recording grant may require relaunch. Mic denial must not block system audio.
- Main app owns capture and has no network entitlement. If external weights win the Phase 3 gate, a model-only downloader XPC service gets network-client access and cannot access meeting packages.
- App Sandbox and Hardened Runtime stay enabled even for direct distribution.
- Entitlements: app sandbox and audio input for the app; conditional network client plus model-only app group for the downloader.
- Purpose strings: microphone and system-audio capture.

## Local ASR decision

- Provisional candidate: `whisper.cpp` v1.9.1 built reproducibly as an arm64 static XCFramework and linked with **Do Not Embed**; pin source commit `f049fff95a089aa9969deb009cdd4892b3e74916` plus its build recipe.
- Provisional whisper checkpoint: multilingual `ggml-large-v3-turbo-q5_0.bin`.
- Candidate asset: 574,041,195 bytes; SHA-256 `394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2`.
- Runtime and Whisper weights are MIT; ship both notices.
- Keep `translate = false`; Whisper performs ASR only.
- One ASR context initially; preserve `You`/`Meeting` from capture-track metadata.
- Apple SpeechAnalyzer remains a bakeoff candidate, not baseline: current macOS 26.5 SpeechTranscriber runtime lacks `vi_VN`; DictationTranscriber exposes it but remains locale-selected.
- Ship one ASR engine after the bakeoff, not two permanent paths.

## Model delivery

- Link the signed static runtime into the app; download weights only.
- Embed an immutable binary `/resolve/<commit>/...` model URL, revision, byte count, SHA-256, and licenses inside the signed app.
- Download over HTTPS to private staging; constrain redirects, stream the hash, require exact size, and activate atomically.
- Corrupt, partial, or unexpected assets never load.
- Retain previous valid model only during atomic update; support explicit model removal.
- No downloaded code, dylib, plugin, script, or mutable remote manifest in v1.

## Translation decision

- Apple Translation framework, never Whisper or a general LLM.
- Check EN→VI and VI→EN independently with `LanguageAvailability.status(from:to:)`.
- Ask permission to install both system language pairs during onboarding.
- Translate finalized same-language batches only; link every result to the immutable source segment ID.
- Translation failure preserves original transcript and never interrupts capture.

## Summary decision

- Apple Foundation Models `SystemLanguageModel.default`.
- Runtime-gate availability and English/Vietnamese locale support.
- Unavailable model means summary unavailable/retry later; never silent cloud fallback.
- macOS 26.1 context is 4,096 total tokens. Use fresh-session map/reduce chunks at finalized utterance boundaries.
- Structured generation guarantees shape, not truth.
- Every factual field carries source IDs plus extractive support; application code rejects unknown IDs or unsupported values and renders the cited original span.
- Meeting text is untrusted data. Summary engine has no tools or side effects.

## Local data and privacy

- Raw audio off by default; bounded in-memory buffers only when off.
- Optional retained audio streams directly into encrypted chunks—no plaintext staging file.
- V1 persistence uses custom authenticated meeting packages—no plaintext database, ORM, GRDB, or SQLCipher.
- Immutable generation manifests authenticate package topology; separately sealed AES-GCM payload/audio chunks use fresh stored random nonces and bind meeting ID, payload kind, track, sequence, and length as AAD.
- Distinct per-meeting text/audio wrapping keys use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`; key-first tombstoned deletion enables independent audio erasure.
- Keep private files and model assets in sandbox Application Support; exclude from backup.
- UserDefaults stores nonsensitive preferences only.
- No transcript/audio/prompts/paths/source names in logs, analytics, crash messages, or diagnostics.
- Exports are explicit plaintext copies outside Kineto’s deletion boundary.
- Manual start every session; persistent capture/retention indicator; Pause, Stop, Stop+Delete; never auto-resume.

## Device behavior

- Bootstrap summary runs only after capture stops; Phase 5 measures whether it ships on the lowest supported 8 GB SoC.
- Set 16 GB support from the worst supported SoC with capture, translation backlog, and meeting client active.
- Set 8 GB support from the same gate; if memory/backlog fails, compare a smaller multilingual checkpoint or defer summary.
- Do not promise a hardware tier if any required quality/resource floor fails.
- Degradation order: stop summary → defer translation → preserve capture and finalized ASR.

## Required proof gates

1. Capture selected-app versus display mix; independent mic; denial/revocation/relaunch/source-loss behavior.
2. Fixed rights-cleared EN/VI/code-switch/noise corpus on real 8 and 16 GB Macs.
3. Compare Whisper against Apple speech paths; record EN WER, VI CER, switch errors, latency, dropped chunks, memory, swap, thermal state.
4. Verify both Translation directions install and work offline after approval.
5. Generate EN and VI summaries; every factual field has valid IDs plus extractive original support; no fabricated owner/date/amount.
6. If external weights ship, tampered/truncated/wrong-size downloads fail closed; update/removal/rollback are atomic.
7. Audio-off creates no audio artifact; encrypted store fails closed after nonce/key/topology mutation and crash-interrupted generation commits/deletion.
8. Release traffic inspection shows no main-app network access; a conditional helper reaches only its fixed model origin and cannot access meeting data.
9. The exact signed/notarized/stapled DMG passes Gatekeeper from a quarantined download on a clean account.

## Workstation readiness

- Observed: macOS 26.5.1, Apple M4, 16 GB, Swift 6.3.2, macOS SDK 26.5.
- Bootstrap blocker: full Xcode is not installed or selected; only Command Line Tools are active.
- Release blockers: Developer ID/notary credentials, real-device EN/VI and 8 GB gates, encrypted-store crash/deletion proofs, working immutable model origin, license notices, and clean-account quarantined-DMG verification.

## Unresolved questions

- Final 8 GB checkpoint depends on measured Turbo-versus-small quality/resource results.
- Developer ID certificate/team and notarization credentials will be required for release proof.
- Capture/recording disclosure wording requires product/legal review before public distribution.

## Primary sources

- ScreenCaptureKit: https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos
- System audio/mic capture: https://developer.apple.com/videos/play/wwdc2024/10088/
- Notarization: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- whisper.cpp v1.9.1: https://github.com/ggml-org/whisper.cpp/tree/v1.9.1
- Pinned model binary: https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-large-v3-turbo-q5_0.bin
- Apple Translation: https://developer.apple.com/documentation/translation/languageavailability
- Foundation Models: https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel
- Context management: https://developer.apple.com/documentation/foundationmodels/managing-the-context-window
- App Sandbox: https://developer.apple.com/documentation/security/app-sandbox
- Keychain: https://developer.apple.com/documentation/security/keychain-services
