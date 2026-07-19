---
phase: 3
title: "Model Delivery and ASR"
status: pending
priority: P1
dependencies: [1, 2]
---

# Phase 3: Model Delivery and ASR

## Overview

Select one EN/VI ASR engine/checkpoint through an early fixture and worst-supported-hardware gate, then implement only the winning production runtime and its model lifecycle.

## Requirements

- Functional: Compare Apple Speech and one whisper candidate, select one, then install/use only the winning production assets for EN/VI fixtures.
- Non-functional: Measured 8 GB viability, immutable origin, exact size/hash, versioned activation/rollback, bounded memory, no executable code download.

## Architecture

`SpeechRecognizer` defines the volatile/final event contract. A minimal spike compares Apple `SpeechAnalyzer` with one whisper candidate before production integration. If whisper wins, the network-only helper stages verified weights into immutable version directories; an active pointer and recognizer lease protect in-use/rollback versions. `WhisperRecognizer` owns one serial context through `WhisperBridge`.

## Related Code Files

- Create: `Packages/KinetoCore/Sources/KinetoCore/ASR/{SpeechRecognizer,RecognitionEvent}.swift`
- Conditional if whisper wins: `Packages/KinetoCore/Sources/KinetoCore/Model/{ModelDescriptor,ModelAvailability,ModelStore}.swift`
- Conditional if whisper wins: `KinetoModelDownloader/{DownloaderService,ModelTransferProtocol}.swift`, `KinetoModelDownloader/KinetoModelDownloader.entitlements`
- Conditional if whisper wins: `Packages/KinetoCore/Sources/KinetoCore/ASR/WhisperRecognizer.swift`, `Packages/KinetoCore/Sources/WhisperBridge/{include/WhisperBridge.h,WhisperBridge.c}`, `Packages/KinetoCore/Binaries/CWhisper.xcframework`
- Create: `Packages/KinetoCore/Tests/KinetoCoreTests/RecognitionContractTests.swift`; conditional `ModelStoreTests.swift`

## Implementation Steps

1. Freeze EN/VI/code-switch/silence/noise fixtures and explicit quality, live RTF, peak memory, thermal, cold/warm load, and cancellation thresholds.
2. Run minimal Apple `SpeechAnalyzer` and whisper candidate spikes on the worst intended 8 GB SoC under an active meeting client; set the minimum SoC, 8 GB feature policy, engine, and checkpoint before Phase 4.
3. If whisper wins, reproducibly build v1.9.1 commit `f049fff95a089aa9969deb009cdd4892b3e74916` as a static arm64 XCFramework, expose a narrow C façade, and verify candidate bytes against a clean independent pinned-source release build.
4. If whisper wins, pin the model descriptor to 574,041,195 bytes and SHA-256 `394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2`.
5. Constrain helper HTTPS redirects/final host, cancellation/resume, size/hash overflow checks, immutable version activation, active-pointer switching, in-use leases, previous-version rollback, and safe removal.
6. Emit replaceable volatile hypotheses and one finalized event with stable timing/language/confidence metadata.
7. Run the full fixture gate on the selected implementation and delete the losing production path/artifacts.

## Success Criteria

- [ ] The engine/checkpoint, minimum SoC, and 8 GB feature policy are recorded before Phase 4; exactly one production ASR path remains.
- [ ] EN/VI fixtures meet declared quality/RTF/memory/thermal thresholds on the worst supported SoC.
- [ ] Partial/tampered/unapproved-host/oversized/wrong-size/wrong-hash downloads never activate.
- [ ] Update/remove/load/cancel/crash preserve in-use and previous verified versions; offline rollback works.
- [ ] A clean independent pinned-source build reproduces the shipped native binary or blocks signing.
- [ ] Final recognition events are ordered, unique, cancellable, and own/release all native lifetimes.

## Risk Assessment

- If no candidate passes on 8 GB, narrow support or choose a smaller checkpoint before building capture/UI around the failing assumption.
- Automatic language detection can miss intra-utterance switches; re-detect at bounded utterance boundaries and preserve spoken-language metadata.
