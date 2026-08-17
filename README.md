# Kineto

Kineto is a native, local-first macOS application for live meeting transcription, English/Vietnamese translation, and evidence-linked post-meeting summaries.

## Implemented slice

- Native SwiftUI/AppKit app for Apple Silicon, macOS 15.0+
- User-selected application or display audio through ScreenCaptureKit
- Optional microphone captured as a separate `You` source
- Local Whisper transcription through a pinned `whisper.cpp` XCFramework and model
- Apple Speech live transcription on macOS 26+ for every locale macOS exposes at runtime; automatic multilingual recognition and macOS 15 use Whisper
- Apple Translation EN↔VI with preflight asset preparation
- Evidence-linked summaries via Apple Foundation Models on macOS 26+, optional Grok / OpenAI / Gemini, or extractive fallback
- Grounded Ask chat with on-this-Mac Apple Intelligence or official BYOK providers (Grok, OpenAI, Gemini) through an isolated Chat Egress XPC
- Authenticated encrypted meeting packages with per-meeting Keychain keys
- Full local meeting library, interruption recovery, plaintext export, and cryptographic deletion
- No network entitlement in the application target; only isolated XPC helpers may use the network

Chinese recognition labels exist in the domain and local ASR mapping, but Chinese translation and summary are outside this supported slice.

## Prerequisites

- Apple Silicon Mac
- macOS 15.0 or newer (Apple Speech live captions and on-device Apple Intelligence chat require macOS 26+)
- Full Xcode 26.6 selected with `xcode-select`
- Screen Recording permission for selected-source capture
- Microphone permission only when microphone capture is enabled
- A locally supplied model matching `ModelDescriptor.whisperLargeV3TurboQ5`

## Build and verify

```bash
./scripts/verify-model-artifacts.sh --internal

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
Repository development artifacts are pinned and verified (in internal mode) by model size/SHA, source revision, framework structure, architecture, and required public symbols. Compiled archive bytes are not pinned for internal builds.

```bash
./scripts/verify-model-artifacts.sh --internal
```


Rebuild the native XCFramework or retrieve the model only through the pinned scripts:

```bash
./scripts/build-whisper-xcframework.sh
./scripts/download-whisper-model.sh
```

The application itself does not download models and has no network client entitlement. A user-selected model is copied into Application Support only after exact local verification. Optional Ask/summary cloud answers go through `KinetoChatEgressService.xpc` after consent, and send only retrieved excerpts.

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
