# Code Standards

## Scope

These rules apply to `KinetoApp/` and `Packages/KinetoCore/`. The enforced baseline is Swift 6 language mode with complete strict concurrency, macOS 26.1+, and Apple Silicon `arm64`, as configured by `Config/Base.xcconfig` and `Packages/KinetoCore/Package.swift`.

## Swift 6 concurrency

- Treat strict-concurrency warnings as correctness failures. Do not weaken `SWIFT_STRICT_CONCURRENCY = complete` or add broad `@preconcurrency` imports to silence diagnostics.
- Put user-interface state and AppKit/SwiftUI interactions on `@MainActor`. `KinetoApp/App/AppModel.swift` is the composition root and the current pattern.
- Use actors for shared mutable state and serialized native resources. Current examples are `MeetingCapture`, `TranscriptCoordinator`, `WhisperRecognizer`, `ModelStore`, `MeetingPackageStore`, `TranslationService`, and `SummaryService`.
- Keep domain values crossing actor boundaries as value types conforming to `Sendable`; persisted records also conform to `Codable` and the equality/identity protocols needed by their contract.
- Protocols used across tasks must inherit `Sendable`, as `SpeechRecognizing` and `MeetingKeyStore` do. Async callbacks and stored closures must be `@Sendable`; UI callbacks must also be `@MainActor`.
- Prefer structured child tasks and explicit cancellation. A detached task requires a documented isolation reason and ownership/lifetime test.
- Never access actor-isolated mutable state through `nonisolated`, global mutable state, or an unsafe pointer escape.
- `@unchecked Sendable` is an audited exception, not a migration tool. It is allowed only around a non-Sendable Apple/native object when all mutable access is actor-confined, immutable, or lock-protected. State the invariant beside the wrapper and add a focused concurrency/lifetime test. Existing wrappers in capture, audio conversion, whisper cancellation/context, and the content-picker bridge define the narrow boundary.
- Do not carry `SCContentFilter`, `AVAudioPCMBuffer`, whisper pointers, or other non-Sendable framework/native objects deeper into the domain layer. Wrap them at the platform boundary and copy only the minimum stable value data.
- Avoid suspension while holding an ordinary lock. `NSLock` guards only short synchronous state transitions; actor methods and `AsyncMutex` guard async mutation.

## Records, evidence, and derived data

- Source records are append-only. Persist only finalized `Segment` values; volatile hypotheses remain in memory and may be replaced only before persistence.
- IDs, source, timing, language, text, confidence, and finality are immutable after acceptance. Create a new record for a new fact; never rewrite a finalized source record.
- Keep source and derived records separate. A `TranslationRecord` references `sourceSegmentID`; it never replaces source text. A `SummaryRecord` is created only from a stopped meeting snapshot.
- Every summary fact must carry `EvidenceReference` values to existing finalized segments. Run `EvidenceValidator`; unsupported owner, date, amount, action, or wording fails closed rather than being softened into output.
- Preserve capture gaps as durable `TranscriptGap` records. Never concatenate recognition across missing audio or hide a gap as an empty segment.
- Keep source labels truthful: `.you` is microphone input and `.selectedSource` is the chosen application/display boundary. Do not infer a speaker identity or call application-wide/browser-wide audio “the meeting.”
- Domain initializers enforce local invariants at creation (`Segment` currently requires nonnegative, ordered times). Storage must revalidate cross-record and package invariants when reopening untrusted bytes.
- `Meeting` and `MeetingSnapshot` are mutable aggregates only to perform validated state transitions and append records inside `MeetingPackageStore`; callers must not use mutable snapshots as alternate persistence.

## Storage and privacy

- `MeetingPackageStore` is the only durable meeting-package writer. Do not write transcript, translation, summary, evidence, or retained audio beside it as plaintext staging.
- Commit a new immutable generation, synchronize files/directories, and switch the `current` pointer only after the generation is durable. Never edit an active generation in place.
- Encrypt meeting content with authenticated encryption and bind identity/topology metadata as additional authenticated data. Authentication, decoding, missing-key, ordering, duplicate, and cross-meeting failures must fail closed as `MeetingStoreError.corrupted` or a more specific non-sensitive error.
- Generate distinct text and optional-audio keys. Store them with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, non-synchronizing Keychain attributes. Never persist raw key bytes in files, defaults, logs, fixtures, or crash metadata.
- Raw-audio retention is off in the implemented app (`retainsAudio: false`). Audio-off must create no audio key, package entry, temporary file, or recoverable plaintext.
- Delete meeting keys before best-effort package bytes. A plaintext export is outside Kineto’s deletion boundary; the UI and code must continue to label it explicitly.
- Model activation is size-and-SHA-256 verified before an atomic `current` pointer switch. Never activate a partial file, an unpinned revision, or downloaded executable code.
- Do not add a main-app network client/server entitlement. Any future downloader must remain isolated from meeting packages and accept only the pinned model origin and bytes.

## Errors and diagnostics

- Define small typed error enums for recoverable domain failures. Cases may expose non-sensitive status such as `missing`, `invalidState`, `checksumMismatch`, or an inference status code; they must not carry transcript text, prompts, evidence, paths, source/window names, model URLs, key material, or audio.
- User-facing errors are fixed, actionable, and privacy-safe. Follow `AppModel`: translate internal failures to generic messages instead of interpolating `error.localizedDescription`, `String(describing:)`, or a path.
- The project currently has no persistent application logger. If logging is introduced, use `Logger` with a stable subsystem/category and metadata-only events. Sensitive values are omitted, not merely marked public.
- Never log transcript/translation/summary/evidence text, Foundation Models prompts or responses, PCM/audio, meeting titles or IDs, selected application/window names, file URLs, security-scoped URLs, Keychain queries/data, or model download credentials.
- Release logging must default to no sensitive payload. Forced error/crash testing must use canary values and fail release if any canary appears in unified logs, diagnostics, analytics, or crash reports.
- `try?` is limited to best-effort cleanup or explicitly optional discovery. Do not suppress capture finalization, package commit/authentication, evidence validation, model verification, or deletion-key failures.
- Never turn an invariant breach into a fallback that presents incomplete derived output as complete. Surface a generic error and preserve the last authenticated generation.

## Tests

New observable behavior requires a deterministic contract test that fails for a plausible regression. Use Swift Testing (`import Testing`, `@Test`, `#expect`) in `Packages/KinetoCore/Tests/KinetoCoreTests/`; use XCTest only for future `XCUIApplication` UI automation and `XCTMetric` performance coverage.

At minimum, changes must cover the affected contract:

- actor ordering, cancellation, end-of-stream drain, and native lifetime ownership;
- final-only, append-only source persistence and duplicate/cross-meeting rejection;
- legal/illegal meeting transitions and stopped-snapshot summary rules;
- evidence IDs plus extractive support rejection;
- authenticated-package mutation, missing keys, topology/order changes, and atomic generation recovery;
- audio-off absence, independent audio-key deletion, key-first meeting deletion, and export boundaries;
- model size/hash verification, activation pointer integrity, removal, and rollback behavior;
- capture overflow/source loss as durable gaps, with no recognition across a gap;
- generic error copy and release-log canary absence.

Use actor-backed fakes for Sendable collaborators and unique temporary directories with deterministic cleanup. Do not use live network, real Keychain state, current time, random recognition output, or installed Apple language assets in Core tests unless the test is explicitly a separately gated real-Mac integration test.

From the repository root:

```bash
swift test --package-path Packages/KinetoCore
xcodebuild -project Kineto.xcodeproj -scheme Kineto \
  -configuration Debug -destination 'platform=macOS,arch=arm64' build
```

The current package suite covers smoke import, audio normalization, transcript drain/gaps, model activation/tamper rejection, evidence extraction, and encrypted meeting lifecycle/tamper/export. App/UI, TCC, real meeting-platform, real Keychain reboot/lock, performance, and release-log tests are not present; do not describe package-test success as proof of those gates.

## Review checklist

- Concurrency isolation is explicit; every crossing value is Sendable.
- No new `@unchecked Sendable` lacks a narrow invariant and test.
- Final source/evidence identity cannot be mutated by translation or summary code.
- Storage remains authenticated, generation-based, key-first on deletion, and plaintext-free except explicit export.
- Errors and diagnostics reveal no meeting or filesystem content.
- Tests defend the changed observable contract and do not replace required real-Mac proof.
