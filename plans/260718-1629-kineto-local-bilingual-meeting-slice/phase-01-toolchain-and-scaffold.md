---
phase: 1
title: "Toolchain and Scaffold"
status: pending
priority: P1
dependencies: []
---

# Phase 1: Toolchain and Scaffold

## Overview

Establish the reproducible native build boundary: checked-in Xcode app, one local Core package, pinned configuration, sandbox entitlements, and a local inference interface that cannot leak into UI code.

## Requirements

- Functional: App launches to the Home shell and imports `KinetoCore`.
- Non-functional: Xcode 26.6, Swift 6 mode, macOS 26.1 deployment, `arm64`, App Sandbox, Hardened Runtime.

## Architecture

Xcode exclusively owns the `.app`, resources, entitlements, archive, signing, and notarization. SwiftPM owns `KinetoCore`, Core tests, and conditional local inference targets selected in Phase 3. `KinetoApp` is the composition root and has no network-client entitlement; Phase 3 adds a model-only downloader XPC target only if the selected engine needs external weights.

## Related Code Files

- Create: `Kineto.xcodeproj`, `Config/{Base,Debug,Release}.xcconfig`
- Create: `KinetoApp/{App,UI,PlatformUI,Resources}/`, `KinetoApp/Kineto.entitlements`
- Create: `Packages/KinetoCore/Package.swift`
- Create: `Packages/KinetoCore/Sources/{KinetoCore,WhisperBridge}/`
- Create: `Packages/KinetoCore/Tests/KinetoCoreTests/`

## Implementation Steps

1. Install/select full Xcode 26.6; record `xcodebuild -version`, Swift version, SDK, and developer directory.
2. Create the macOS SwiftUI app with explicit bundle identifier, deployment target, architecture, signing placeholders, purpose strings, sandbox, audio-input, and screen-capture requirements; omit network-client/server entitlements.
3. Add the local package with tools version matching Xcode 26.6, `.macOS("26.1")`, and Swift 6 language mode.
4. Define `KinetoCore` plus conditional inference targets selected in Phase 3; no C/C++ API may reach the app.
5. Add shared schemes/configuration files; keep secrets, team IDs, and machine paths outside committed settings.
6. Add Swift Testing smoke coverage for Core, entitlement-contract checks, and one app launch smoke path.

## Success Criteria

- [ ] `swift test` passes for `KinetoCore` under the selected Xcode toolchain.
- [ ] `xcodebuild build` succeeds for the macOS app at deployment target 26.1 and `arm64`.
- [ ] App launches and renders the Home shell without importing whisper APIs in `KinetoApp`.
- [ ] The app has no network-client/server entitlement; any later downloader target must have no meeting-package access or arbitrary network/path operation.
- [ ] A clean checkout contains no generated project dependency or local absolute path.

## Risk Assessment

- Full Xcode is currently absent: implementation is blocked until installed.
- A conditional model helper is justified only if Phase 3 selects external weights; do not create it for an Apple-system ASR path.
- Avoid XcodeGen/Tuist and additional subsystem targets; they create drift without solving a demonstrated boundary.
