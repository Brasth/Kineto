# Kineto

Kineto is a native, local-first macOS application for live meeting transcription, English/Vietnamese translation, and evidence-linked post-meeting summaries.

## Implemented slice

- Native SwiftUI/AppKit app for Apple Silicon, macOS 26.1+
- User-selected application or display audio through ScreenCaptureKit
- Optional microphone captured as a separate `You` source
- Local Whisper transcription through a pinned `whisper.cpp` XCFramework and model
- Apple Speech live transcription for every locale macOS exposes at runtime; automatic multilingual recognition falls back to Whisper
- Apple Translation EN↔VI with preflight asset preparation
- Apple Foundation Models summaries with selectable brief, action-plan, or discussion-note structures and source evidence
- Authenticated encrypted meeting packages with per-meeting Keychain keys
- Full local meeting library, interruption recovery, plaintext export, and cryptographic deletion
- No network entitlement in the application target

Chinese recognition labels exist in the domain and local ASR mapping, but Chinese translation and summary are outside this supported slice.

## Prerequisites

- Apple Silicon Mac
- macOS 26.1 or newer
- Full Xcode 26.6 selected with `xcode-select`
- Screen Recording permission for selected-source capture
- Microphone permission only when microphone capture is enabled
- A locally supplied model matching `ModelDescriptor.whisperLargeV3TurboQ5`

## Build and verify

```bash
swift test --package-path Packages/KinetoCore
./scripts/verify-model-artifacts.sh
xcodebuild \
  -project Kineto.xcodeproj \
  -scheme Kineto \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Launch the built app from Xcode or the Debug products directory. Import the pinned Whisper model when the preflight screen reports that a verified model is required.

## Model and native runtime

Repository development artifacts are pinned and verified by size, SHA-256, source revision, native archive/header/metadata hashes, architecture, and required public symbols:

```bash
./scripts/verify-model-artifacts.sh
```

Rebuild the native XCFramework or retrieve the model only through the pinned scripts:

```bash
./scripts/build-whisper-xcframework.sh
./scripts/download-whisper-model.sh
```

The application itself does not download models and has no network client entitlement. A user-selected model is copied into Application Support only after exact local verification.

## Data and privacy boundary

Meeting text is encrypted with AES-GCM. Per-meeting keys and authoritative generation metadata use non-synchronizing, this-device-only Keychain items. Deletion records durable intent before destroying keys and package bytes. Plaintext exports are explicitly outside Kineto’s encrypted storage and deletion boundary.

Raw-audio retention is not connected in the current application workflow. Captured PCM is transient and used for local inference.

## Release

`scripts/build-release-dmg.sh` requires user-owned Developer ID and notarization credentials. It archives and exports the app, verifies entitlements and Hardened Runtime, builds the exact DMG, waits for Apple notarization acceptance, staples and validates the DMG, runs Gatekeeper assessment, and records its SHA-256.

Do not distribute publicly until the external gates in `docs/deployment-guide.md` and `docs/project-roadmap.md` are complete: clean-account Gatekeeper proof, real Zoom/Meet/Teams and TCC trials, accessibility checks, worst-device performance evidence, language-framework device coverage, privacy canaries, and launch-market counsel approval.

## Documentation

- `docs/user-guide.md` — opening the app, model import, permissions, recording workflow, and troubleshooting
- `docs/project-overview-pdr.md` — product contract and requirements
- `docs/system-architecture.md` — boundaries, data flow, concurrency, storage
- `docs/codebase-summary.md` — repository and symbol map
- `docs/design-guidelines.md` — native UI and accessibility rules
- `docs/code-standards.md` — implementation standards
- `docs/deployment-guide.md` — signing, notarization, Gatekeeper, rollback
- `docs/project-roadmap.md` — delivered scope and remaining gates
- `plans/260718-1629-kineto-local-bilingual-meeting-slice/` — approved seven-phase plan

## License notices

See `THIRD_PARTY_NOTICES` for pinned Whisper runtime/model provenance and licensing. Project source licensing has not been declared; do not infer a redistribution license for Kineto source code.
