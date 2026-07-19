# Deployment Guide

## Release status

Kineto targets macOS 26.1 or later on Apple Silicon (`arm64`) and direct Developer ID distribution. The repository contains build and release automation, but there is no externally verified release yet. A local archive, an unsigned/unnotarized build, or a passing Core package suite is not a releasable artifact.

The main app is sandboxed with microphone and user-selected-file access only. `KinetoApp/Kineto.entitlements` has no network client/server entitlement. Meeting capture, transcription, translation, summary, and encrypted storage are intended to operate locally; the raw-audio option is off in the implemented app.

## Repository artifacts

| Path | Purpose |
|---|---|
| `Kineto.xcodeproj` | `Kineto` macOS app, shared scheme, archive settings |
| `Packages/KinetoCore/Package.swift` | Swift 6 Core package and tests |
| `Binaries/CWhisper.xcframework` | Local arm64 whisper.cpp binary target |
| `Models/ggml-large-v3-turbo-q5_0.bin` | Pinned development model bytes |
| `Config/Base.xcconfig` | macOS 26.1, Swift 6, strict concurrency, arm64 |
| `Config/Release.xcconfig` | Optimized validated Release settings |
| `Config/ExportOptions.plist` | Automatic Developer ID archive export |
| `scripts/download-whisper-model.sh` | Pinned model acquisition and verification |
| `scripts/build-whisper-xcframework.sh` | Pinned whisper.cpp XCFramework build |
| `scripts/verify-model-artifacts.sh` | Intended release artifact gate; see known blockers |
| `scripts/build-release-dmg.sh` | Archive, export, DMG, notarization, Gatekeeper, digest |

All commands below run from the repository root.

## Workstation prerequisites

1. Use macOS on Apple Silicon and full Xcode 26.6, not Command Line Tools alone or an Xcode 27 beta. Select the installed Xcode and accept its first-launch requirements:

   ```bash
   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -runFirstLaunch
   xcodebuild -version
   xcrun swift --version
   xcrun --sdk macosx --show-sdk-version
   xcode-select -p
   ```

2. For a reproducible native framework build, make `git`, `cmake`, `libtool`, and `xcodebuild` available. Model acquisition additionally needs `curl`, `stat`, and `shasum`.

3. For release export, the signing Mac must have the actual Developer ID Application certificate and private key, the correct Apple Developer team/agreement state, and automatic signing configured for bundle ID `com.huynguyen.Kineto`. `Config/ExportOptions.plist` intentionally contains no team ID or credentials.

4. Create a `notarytool` Keychain profile with user-owned Apple credentials outside the repository. Apple credentials, app-specific passwords/API keys, team IDs, profile names, and certificate material must never be committed. Before release, the shell must already contain real local values for `DEVELOPER_ID_APPLICATION` and `KINETO_NOTARY_PROFILE`; this guide does not claim that they are configured.

   Verify local provisioning without printing secrets:

   ```bash
   security find-identity -v -p codesigning
   test -n "${DEVELOPER_ID_APPLICATION:-}"
   test -n "${KINETO_NOTARY_PROFILE:-}"
   xcrun notarytool history --keychain-profile "$KINETO_NOTARY_PROFILE"
   ```

5. Keep prior released DMGs and their `.sha256` files outside `build/release/`; `scripts/build-release-dmg.sh` deletes that directory at the start of every run.

## Model and framework preparation

### Acquire or import the model

The approved model descriptor is:

- revision `5359861c739e955e79d9a303bcbc70fb988958b1`;
- file `ggml-large-v3-turbo-q5_0.bin`;
- byte count `574041195`;
- SHA-256 `394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2`.

For a developer checkout, acquire the pinned bytes:

```bash
./scripts/download-whisper-model.sh
shasum -a 256 -c Models/ggml-large-v3-turbo-q5_0.bin.sha256
test "$(stat -f '%z' Models/ggml-large-v3-turbo-q5_0.bin)" = 574041195
```

For an installed app, obtain those same verified bytes through an approved distribution channel, open **New Meeting**, choose **Import verified model…**, and select the `.bin` file. `AppModel.importModel` copies it to a security-scoped staging file, and `ModelStore` checks size and SHA-256 before moving it under the sandboxed Application Support model directory and switching the `current` pointer. A failed check removes the staging file and does not activate the model.

The main app does not download a model and has no network entitlement. `scripts/download-whisper-model.sh` is a developer/release-host workflow, not an in-app network path.

### Build and verify CWhisper

The approved whisper.cpp commit is `f0499fff95a089aa9969deb009cdd4892b3e74916`.

```bash
./scripts/build-whisper-xcframework.sh
test -d Binaries/CWhisper.xcframework
test -f Binaries/CWhisper.xcframework/macos-arm64/Headers/whisper.h
test "$(tr -d '[:space:]' < Binaries/CWhisper.xcframework/WHISPER_CPP_COMMIT)" \
  = f0499fff95a089aa9969deb009cdd4892b3e74916
```

The build script clones only the pinned commit, compiles a static arm64 library with Metal enabled and macOS 26.1 as the deployment target, then records provenance in `Binaries/CWhisper.xcframework/WHISPER_CPP_COMMIT`. Release approval additionally requires an independent pinned-source rebuild and byte/provenance/license comparison; a successful local script run alone is insufficient.

### Known repository gate defects

Do not bypass these failures or describe the release gate as passing:

- `scripts/verify-model-artifacts.sh` contains model SHA-256 `39421709…`, which disagrees with `ModelDescriptor.swift`, the download script, and the checked-in `.sha256` file (`394221709…`).
- The same verifier expects whisper commit `f0499fff95a089aa9969deb009cdd4892ba374916`, while the framework build script and checked-in provenance contain `f0499fff95a089aa9969deb009cdd4892b3e74916`.

Consequently, this intended gate currently fails even for the repository’s pinned artifacts:

```bash
./scripts/verify-model-artifacts.sh
```

The constants must be reconciled in source and independently verified before any release build. This guide records the blocker; it does not authorize skipping the script.

## Package and application builds

Verify Core independently before app composition:

```bash
swift test --package-path Packages/KinetoCore
swift build --package-path Packages/KinetoCore --configuration release
```

Build the application without archiving:

```bash
xcodebuild -project Kineto.xcodeproj -scheme Kineto \
  -configuration Debug -destination 'platform=macOS,arch=arm64' build

xcodebuild -project Kineto.xcodeproj -scheme Kineto \
  -configuration Release -destination 'generic/platform=macOS' build
```

Launch the resulting Debug app from Xcode and exercise the changed workflow. There are currently no app/UI test targets in the shared scheme, so `swift test` does not prove launch, TCC, ScreenCaptureKit, Translation asset, Foundation Models, signing, or Gatekeeper behavior.

## Signing, notarization, and DMG pipeline

After all non-signing release gates and the known artifact-verifier defects are closed, run:

```bash
./scripts/build-release-dmg.sh
```

The script performs the following exact pipeline:

1. Run `scripts/verify-model-artifacts.sh`.
2. Remove and recreate `build/release/`.
3. Archive `Kineto.xcodeproj`, scheme `Kineto`, Release configuration to `build/release/Kineto.xcarchive`.
4. Export with `Config/ExportOptions.plist` to `build/release/export/Kineto.app` using automatic Developer ID signing.
5. Verify the app signature with `codesign` and assess the app with `spctl`.
6. Stage `Kineto.app` plus an `/Applications` symlink and create `build/release/Kineto.dmg`.
7. Sign the DMG with the identity named by `DEVELOPER_ID_APPLICATION` and a secure timestamp.
8. Submit that DMG with the Keychain profile named by `KINETO_NOTARY_PROFILE`, wait for Apple’s result, staple and validate the DMG ticket, assess the DMG with Gatekeeper, and write `build/release/Kineto.dmg.sha256`.

Inspect the final bytes, not an earlier copy:

```bash
shasum -a 256 -c build/release/Kineto.dmg.sha256
codesign --verify --deep --strict --verbose=2 build/release/export/Kineto.app
xcrun stapler validate build/release/Kineto.dmg
spctl --assess --type open --context context:primary-signature --verbose=4 \
  build/release/Kineto.dmg
```

The release script submits the exact signed DMG, waits for Apple's `Accepted` result, staples and validates that DMG, then runs Gatekeeper assessment. This is the artifact users receive. The clean-account procedure below additionally mounts that same digest-recorded DMG and verifies/assesses its contained app; preserve both DMG-ticket and contained-app evidence.

## Clean-account Gatekeeper proof

Publish only after testing the same digest-recorded DMG through the real distribution path on a clean macOS 26.1+ account. A local unquarantined file is not equivalent. After downloading it through the intended browser/channel:

```bash
DMG="$HOME/Downloads/Kineto.dmg"
xattr -p com.apple.quarantine "$DMG"
shasum -a 256 "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG"
mkdir -p "$TMPDIR/Kineto-release-check"
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$TMPDIR/Kineto-release-check"
codesign --verify --deep --strict --verbose=2 \
  "$TMPDIR/Kineto-release-check/Kineto.app"
spctl --assess --type execute --verbose=4 \
  "$TMPDIR/Kineto-release-check/Kineto.app"
hdiutil detach "$TMPDIR/Kineto-release-check"
```

Confirm the digest equals the published `.sha256`, copy to `/Applications`, launch normally, and exercise TCC grant/relaunch/denial/revocation plus the offline meeting workflow. Preserve the command output, notarization result, OS/hardware identity, and artifact digest as release evidence without including meeting content or credentials.

## Rollback and removal

There is no automatic updater. Rollback means reinstalling a previously retained, digest-verified, notarized DMG whose meeting-schema compatibility has been established. Quit Kineto, retain or explicitly export any required meetings, remove `/Applications/Kineto.app`, and install the older verified app. Do not downgrade across an unknown package schema; the current encrypted manifest is version 1, and no migration/downgrade contract is implemented.

To remove only the imported model, quit Kineto and remove its model directory:

```bash
rm -rf "$HOME/Library/Containers/com.huynguyen.Kineto/Data/Library/Application Support/Kineto/Models/whisper-large-v3-turbo-q5_0"
```

The next launch must report that a verified model is required. `ModelStore` has a removal API, but the current UI does not expose model removal or previous-revision rollback; only re-import of the pinned revision is implemented.

For uninstall, first delete each meeting in Kineto so `MeetingPackageStore` deletes the per-meeting Keychain keys before package files. Manually remove plaintext exports from their user-selected destinations. Then quit and remove the app and sandbox container:

```bash
rm -rf /Applications/Kineto.app
rm -rf "$HOME/Library/Containers/com.huynguyen.Kineto"
tccutil reset ScreenCapture com.huynguyen.Kineto
tccutil reset Microphone com.huynguyen.Kineto
```

Deleting the container without in-app meeting deletion can leave Keychain items behind. If the app cannot open, remove generic-password items with service `com.huynguyen.Kineto.meeting-key` in Keychain Access before deleting the container; do not script or log their account/data values.

## Release blockers

Public release remains blocked until evidence exists for all of the following:

- the pinned model and CWhisper archive/header/metadata checks pass `scripts/verify-model-artifacts.sh`, and independent provenance/license review confirms those recorded sources;
- the package test suite and Debug app build pass under the pinned Xcode toolchain; Release archive/export remains blocked on user-owned signing and notarization credentials;
- worst-supported-device benchmarks for every claimed 8 GB and 16 GB tier under active Zoom, Google Meet, and Teams workloads, including EN/VI/code-switch quality, live latency, memory, swap, and thermal behavior;
- real platform trials for capture boundaries, source/topology loss, mic-only mode, lock/sleep/wake, TCC grant/relaunch/denial/revocation, interruption, deletion, and offline operation;
- clean-account Apple Translation EN↔VI asset availability and Foundation Models EN/VI summary behavior, including unavailable/deferred fallbacks;
- release-mode privacy canaries proving transcript, prompt, evidence, source/path, audio, and credential values never enter logs, diagnostics, analytics, or crash reports;
- launch-market counsel approval of recording/consent disclosures and exact per-session acknowledgment copy; external ScreenCaptureKit capture does not activate Zoom/Meet/Teams recording indicators;
- user-owned Developer ID/team agreements, certificate/private key, and notary credentials, plus successful exact-DMG notarization/stapling and contained-app Gatekeeper evidence;
- a real quarantined download of the exact published digest passing Gatekeeper on a clean account; and
- documented model/app rollback and removal trials against the same released artifact.

Until every gate is recorded, label artifacts as development builds, not signed/notarized releases.
