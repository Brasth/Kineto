# Kineto Project Roadmap

## Status basis

- **As of:** 2026-07-18
- **Current milestone:** Native local EN/VI meeting-assistant vertical slice implemented across the Phase 1–6 areas.
- **Release milestone:** Open. Phase 7 evidence has not been produced.
- **Interpretation rule:** “Implemented” below means source/config/test contracts are present. It does **not** mean the phase's plan checklist, real-device gate, legal gate, or distribution gate has passed.

The approved plan and its seven phase files still carry `status: pending`, and their success-criteria boxes remain unchecked. This roadmap therefore separates delivered implementation from accepted release evidence.

## Delivered vertical-slice implementation

| Phase | Implemented result | Repository evidence | Acceptance state |
|---|---|---|---|
| 1. Toolchain and scaffold | Checked-in Xcode app, local Swift package, macOS 26.1/arm64/Swift 6 settings, sandbox entitlement without network access | `Kineto.xcodeproj`, `Config/`, `KinetoApp/Kineto.entitlements`, `Package.swift` | **Debug app build and launch smoke passed; signed Release gate open** |
| 2. Domain and secure storage | Authenticated generation store; Keychain authority; staged creation; deletion tombstones; terminal source ledger; reopen/export/delete | `Domain/`, `Storage/`, `MeetingPackageStoreTests` | **Core contracts pass; fault-injection and locked-Keychain device trials open** |
| 3. Model delivery and ASR | Pinned whisper.cpp recognizer; exact model and native archive/header/metadata verification; crash-safe immutable activation | `ASR/`, `ModelDelivery/`, `Binaries/CWhisper.xcframework`, tests/scripts | **Runtime and artifact verifier pass; worst-device gate open** |
| 4. Capture and live transcript | Owned callback buffers, optional mic, monotonic timestamps, bounded per-source inference queues, interval gaps, final-tail drain/cancellation | `Capture/`, `Audio/`, `TranscriptCoordinator`, tests | **Source contracts pass; real platform/TCC trials open** |
| 5. Translation and summary | Preflight EN↔VI asset preparation; nonblocking tracked translation; post-stop extractive Foundation Models summary with field isolation | `TranslationService`, `SummaryService`, `EvidenceValidator` | **Local EN↔VI shell trial passed; clean-account/framework-device matrix open** |
| 6. Native app experience | Full library, preflight, picker, independent mic fallback, interruption recovery, truthful processing, evidence spans, export/delete | `AppModel`, `KinetoApp`, `HomeView` | **Build and UI launch/preflight smoke passed; accessibility/platform matrix open** |
| 7. Verification and release | Hardened Release config, Developer ID export, exact artifact gate, DMG notarization acceptance/stapling/Gatekeeper script | `Config/`, `scripts/`, deployment guide | **Unsigned local gates pass; credentialed exact-DMG proof open** |

## Evidence already represented in tests

The Swift Testing suite currently contains 14 passing contracts across seven test files:

- Product name and minimum-system-version contract.
- 48 kHz stereo to mono 16 kHz audio normalization.
- Transcript final-tail flush, durable gaps, and timestamp-discontinuity detection.
- Whisper silence/brief-noise rejection and sustained-audio admission.
- Encrypted meeting creation/reopen with finalized records only.
- AES-GCM mutation rejection and key-first tombstoned deletion outcome.
- Meeting listing and atomic plaintext export shape.
- Stopped-meeting rejection of late source and translation records.
- Keychain-authoritative generation rollback defense.
- Interrupted deletion tombstone recovery.
- Extractive summary evidence acceptance and unsupported owner/date rejection.
- Model exact-size/hash activation, mutation rejection, and same-revision repair.

Observed local evidence also includes the arm64 Debug app build, a system-picker trial showing non-Kineto windows/displays, a warmed Start Meeting transition measured at 0.598 seconds, live selected-source YouTube transcription with EN→VI translation, local Whisper inference and silence-hallucination probes, Foundation Models capability gating, and the strengthened model/XCFramework provenance script. These do not replace clean-account, real-meeting-platform, accessibility, worst-device, or signed-release trials.

## Known implementation/evidence gaps before external release testing

These are repository closure items, separate from credentials, counsel, and real-device gates:

1. **Run the signed Release matrix.** User-owned Developer ID and notarization credentials are required to archive/export, obtain Apple's `Accepted` notarization result, staple the exact DMG, and capture clean-account Gatekeeper evidence.
2. **Extend fault/device evidence.** Add crash-point injection around package creation/commit/deletion/model activation, then test Keychain locked/post-reboot behavior and interruption-safe export on supported hardware.
3. **Keep retained audio out of claims or implement it fully.** The current app always sets `retainsAudio: false` and has no encrypted audio sink.
4. **Complete real capture saturation and topology trials.** Exercise stop under load, source loss, pause/resume, lock/sleep/wake, TCC denial/revocation, and Zoom/Meet/Teams topology changes.
5. **Complete Apple language-framework trials.** Test clean-account Translation asset installation/cancellation and Foundation Models EN/VI availability, output, cancellation, and unavailable fallback.
6. **Inspect final signed bytes.** Record built entitlements, Hardened Runtime, archive contents, privacy strings, notices, exact digests, and absence of meeting-sensitive diagnostics.

## Remaining external release gates

### Gate A — Worst-supported-device ASR and resource evidence

**Status:** Open.

Required evidence:

- Freeze a rights-cleared EN/VI/code-switch/silence/noise/overlap/names/numbers/currency/dates/negation corpus.
- Record Whisper-versus-Apple candidate results before treating the selected checkpoint as final.
- Test the worst intended Apple Silicon SoC in every shipped 8 GB and 16 GB tier while Zoom/Meet/Teams workload is active.
- Record EN WER, VI CER, code-switch errors, real-time factor, latency, dropped chunks, peak memory, swap, thermal state, cold/warm model load, and cancellation behavior.
- Set the minimum supported SoC and the exact 8/16 GB feature matrix from results. If a floor fails, narrow support, select a smaller checkpoint, or defer summary; do not soften the gate.

**Exit:** Every advertised hardware tier meets declared quality and resource thresholds, with raw measurements retained.

### Gate B — Meeting-platform, capture-boundary, and TCC trials

**Status:** Open.

Required evidence on macOS 26.1+:

- Zoom, Google Meet in supported browsers, and Microsoft Teams scenarios.
- Selected-application versus display audio, optional mic, mic-only degradation, application/browser scope disclosure, and topology/source loss.
- First grant/relaunch, denial, revocation, lock, sleep/wake, pause/resume, stop during utterance, stop under saturation, crash/relaunch, and interrupted processing.
- Visible gap behavior with proof that recognition does not join speech across missing PCM.
- Confirmation that external capture does not claim or trigger platform recording indicators.

**Exit:** Actual behavior matches the UI disclosure and no platform-specific limitation is hidden.

### Gate C — Apple language-framework availability and offline behavior

**Status:** Open.

Required evidence:

- EN→VI and VI→EN status/install/use on clean provisioned accounts.
- Both directions work after network is disabled and preserve source linkage.
- English and Vietnamese Foundation Models summary availability on supported device tiers.
- Model unavailable, locale unsupported, cancellation, and context-limit paths preserve finalized transcript/translation and expose retry or truthful unavailability.
- Every displayed factual summary field resolves to an original segment and extractive support.

**Exit:** Supported language/device matrix and graceful-degradation policy are measured and documented.

### Gate D — Privacy and security release review

**Status:** Open.

Required evidence:

- Release-mode traffic inspection proves the main app has no network access and the meeting workflow functions offline.
- Built-product entitlement inspection proves no accidental network entitlement; any future model helper has fixed-origin model-only access and no meeting-package access.
- Canary transcript, prompt, source-name, and path values are absent from unified logs, diagnostics, analytics, and crash metadata across forced failures.
- Independent review of authenticated package structure, nonce/key behavior, crash commits, deletion semantics, plaintext export cleanup, and Keychain locked/post-reboot behavior.
- Independent pinned-source reproduction of shipped whisper.cpp native bytes, model provenance, license notices, update/removal behavior, and offline rollback.

**Exit:** Security/privacy reviewers sign off on recorded artifacts; unresolved high-severity findings block release.

### Gate E — Counsel and participant-notification approval

**Status:** Open and externally owned.

Required evidence:

- Launch-market counsel reviews recording/capture obligations and approves exact user-facing copy.
- Per-session acknowledgment uses the approved text and is never remembered as a standing consent.
- Disclosures clearly state application/display capture scope, participant-notification responsibility, lack of meeting-platform recording indicators, machine-generated content, and plaintext export boundary.

**Exit:** Counsel approval and final copy are recorded for every launch market.

### Gate F — Developer ID notarized distribution

**Status:** Open and externally credential-dependent.

Required evidence:

- Supply the Developer ID team/certificate and `notarytool` Keychain profile.
- Archive with the pinned release toolchain; verify Hardened Runtime, signatures, entitlements, notices, and model/runtime provenance.
- Build the exact deterministic DMG intended for distribution.
- Sign, notarize, and staple both required artifacts; record the distributed DMG SHA-256.
- Download the same artifact with quarantine on a clean account, then pass Gatekeeper and an offline end-to-end smoke workflow.
- Preserve notarization logs, signature inspection, digest, toolchain version, rollback instructions, and supported hardware matrix.

**Exit:** The exact distributed DMG—not a substitute archive—passes notarization, stapler validation, Gatekeeper, and the clean-account smoke workflow.

## Release gate matrix

| Gate | Current status | Evidence owner/input | Release blocker |
|---|---|---|---|
| Repository build and deterministic tests | 12 contracts pass; arm64 Debug and Release builds recorded locally | Engineering + full Xcode 26.6 environment | No |
| Worst-device 8/16 GB benchmarks | Not run/recorded | Hardware lab / target Macs | Yes |
| Zoom/Meet/Teams and TCC trials | Not run/recorded | QA on real Macs/accounts | Yes |
| Translation/Foundation Models availability | Not run/recorded | QA on clean provisioned Macs | Yes |
| Privacy/security review and canary logs | Not run/recorded | Security/release engineering | Yes |
| Launch-market counsel and approved copy | Not supplied | Counsel/product | Yes |
| Developer ID signing/notarization/Gatekeeper | Credentials and artifact proof absent | Apple credentials + release engineering | Yes |

## Decision rules for release

- Preserve capture and finalized ASR before translation; preserve both before summary.
- Do not advertise a hardware tier that fails its measured quality/resource floor.
- Do not relabel application/browser-wide audio as `Meeting` without isolation proof.
- Do not add network entitlement to the main capture app.
- Do not ship optional audio retention until direct-to-encrypted storage and independent deletion are implemented and proven.
- Do not display a factual summary item merely because its citation ID exists; extractive support is mandatory.
- Do not claim “private,” “offline,” “secure,” “notarized,” or “release-ready” beyond the exact evidence produced.

## Deferred beyond the vertical slice

The roadmap does not include cloud services, accounts/sync, diarization, platform bots, browser-tab isolation, autonomous actions, Intel support, automatic capture, or downloadable executable plug-ins. Adding any of these requires a new product decision and threat/privacy review rather than extending this release milestone.

## References

- `docs/project-overview-pdr.md`
- `plans/260718-1629-kineto-local-bilingual-meeting-slice/plan.md`
- `plans/260718-1629-kineto-local-bilingual-meeting-slice/phase-01-toolchain-and-scaffold.md` through `phase-07-verification-and-release.md`
- `docs/research-summary.md`
- `docs/technology-stack.md`
- `docs/design-guidelines.md`
- Current source under `Packages/KinetoCore/` and `KinetoApp/`
