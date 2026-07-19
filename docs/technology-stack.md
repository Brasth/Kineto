---
title: Kineto Technology Stack
status: approved
approved: 2026-07-18
---

# Kineto Technology Stack

## Toolchain

- Full Xcode 26.6, pinned for local release and CI builds.
- Apple Swift 6.3 compiler; Swift 6 language mode.
- macOS 26.1 deployment target; Apple Silicon `arm64` only.
- Swift Package Manager for the local Core package and binary linkage.
- Xcode owns app/helper bundles, assets, entitlements, schemes, archive, Developer ID signing, notarization, and the deterministic DMG.
- Current prerequisite: install full Xcode 26.6; Command Line Tools alone cannot build the app project or XCFramework.

## Project shape

```text
Kineto.xcodeproj
Config/
  Base.xcconfig
  Debug.xcconfig
  Release.xcconfig
KinetoApp/
  App/
  UI/
  PlatformUI/
  Resources/
  Kineto.entitlements
KinetoModelDownloader/        # conditional: only if external ASR weights win
  DownloaderService.swift
  ModelTransferProtocol.swift
  KinetoModelDownloader.entitlements
Packages/KinetoCore/
  Package.swift
  Sources/KinetoCore/
    Domain/
    Session/
    Capture/
    Audio/
    ASR/
    Translation/
    Summary/
    Storage/
    Model/                    # conditional with external weights
  Sources/WhisperBridge/      # conditional if whisper wins
  Binaries/CWhisper.xcframework # conditional if whisper wins
  Tests/KinetoCoreTests/
KinetoAppUITests/
```

## Module ownership

### `KinetoApp`

- SwiftUI application lifecycle and composition root.
- AppKit bridges and `SCContentSharingPicker` presentation.
- Permission, consent, source selection, recording, transcript, and summary UI.
- Assets, localization, purpose strings, no-network entitlements, signing, and release resources.
- Imports `KinetoCore`; never imports whisper C/C++ APIs.

### `KinetoModelDownloader` (conditional)

- Exists only if the selected ASR requires external weights.
- Network-client plus model-only app-group access; no meeting-package access or arbitrary URL/path API.
- Downloads/verifies immutable descriptors and activates versioned weights atomically.

### `KinetoCore`

- Immutable meeting, segment, translation, summary, and evidence records.
- Meeting-session state machine and bounded asynchronous pipeline.
- ScreenCaptureKit stream ownership after source selection.
- Audio normalization, timestamps, buffering, and backpressure.
- Selected ASR contract and optional narrow Whisper C-bridge ownership.
- Finalized-segment Apple Translation coordination.
- Post-stop Foundation Models map/reduce summary and extractive evidence validation.
- Authenticated encrypted meeting packages and Keychain access.
- Versioned model-store lifecycle when external weights are selected.
- Must not import SwiftUI or expose whisper implementation types.

### `CWhisper.xcframework` (conditional)

- Shipped only if whisper wins the measured Apple-versus-whisper gate.
- Reproducibly built arm64 static XCFramework from pinned `whisper.cpp` v1.9.1 source commit.
- SwiftPM local binary target; linked into Kineto; **Do Not Embed**.
- Candidate bytes must match an independent clean pinned-source build before signing.

## Apple frameworks

- SwiftUI + AppKit: native desktop interface and lifecycle bridges.
- ScreenCaptureKit + CoreMedia + AVFoundation: selected app/display audio and optional microphone.
- Translation: installed, pair-gated EN↔VI translation of finalized segments.
- FoundationModels: post-meeting structured English or Vietnamese summaries.
- CryptoKit: SHA-256 model validation and AES-GCM meeting-package encryption.
- Security/Keychain Services: device-only, nonsynchronizing content keys.
- OSLog: privacy-safe static state and allowlisted error logging only.

## ASR assets

- Provisional whisper candidate: `ggml-large-v3-turbo-q5_0.bin`.
- Immutable revision: `5359861c739e955e79d9a303bcbc70fb988958b1`.
- Exact size: 574,041,195 bytes.
- SHA-256: `394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2`.
- Bake off against Apple speech APIs on the worst intended 8 GB SoC, then retain one production engine and only its required assets.

## Persistence

- Custom versioned authenticated meeting packages; no plaintext database.
- Immutable generation manifests plus a durable active pointer authenticate artifact topology and crash recovery.
- Independently sealed AES-GCM chunks use fresh stored random nonces and authenticated topology fields.
- Distinct per-meeting text/audio keys use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and tombstoned key-first deletion.
- Model weights are public integrity-sensitive assets in a model-only app group, separate from private meeting data.

## Testing

- Swift Testing for new `KinetoCore` unit and deterministic integration contracts.
- XCTest only for `XCUIApplication` UI automation and `XCTMetric` performance tests.
- Core tests run through SwiftPM under the selected Xcode toolchain.
- Xcode tests cover app composition, lifecycle, permission UX, and source picker.
- Real-Mac proof gates cover TCC permissions, ScreenCaptureKit isolation, Apple model assets, 8/16 GB resources, signing, notarization, and Gatekeeper.

## Dependency policy

- No third-party Swift source dependencies in the bootstrap.
- No XcodeGen, Tuist, CocoaPods, Carthage, GRDB, SQLCipher, WhisperKit, ORM, reactive framework, DI container, or localhost model server.
- Add a dependency only when an observed requirement beats the native implementation and its license, supply chain, binary size, privacy, and concurrency behavior pass review.
- Commit `Package.resolved` only after approving an external package.

## Rejected project shapes

- Monolithic app target with network entitlement: unsafe native inference code would combine meeting plaintext and unrestricted egress.
- Unconditional multi-target package graph: no second consumer/team justifies extra public APIs; the one conditional XPC target enforces the model-network boundary only when needed.
- Pure SwiftPM app bundle: recreates Xcode signing/asset/archive behavior and still cannot replace Xcode.

## Unresolved

- Final 8 GB ASR checkpoint remains benchmark-gated.
- Developer ID team/certificate and notarization credentials are unavailable until onboarding.
