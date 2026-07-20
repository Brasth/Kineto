---
phase: 3
title: Verification and documentation
status: in-progress
priority: P1
dependencies:
  - 1
  - 2
---

# Phase 3: Verification and documentation

## Overview

Prove the new storage and overlay contracts without weakening existing local-first privacy, encryption, capture, or accessibility guarantees. Update product and operational documentation only after focused behavior is demonstrably correct.

## Requirements

- Functional: test storage limits, encrypted round-trip, export exclusion, delete/recovery cleanup, four-row ordering, translation association, placement persistence/clamping, and active-capture-only interaction.
- Functional: test all failure paths leave capture usable and storage/package state valid.
- Non-functional: validate VoiceOver, Reduce Motion, Increase Contrast, compact width, multi-display movement, Finder drops, and screen sharing on real macOS hardware.
- Documentation: describe the precise file-only input, size/count quota, encryption/deletion boundary, explicit drop target, and transcript-export exclusion. Do not claim release proof from local tests.

## Architecture

Layered verification keeps deterministic contracts closest to their owner:

1. `KinetoCore` tests own encrypted blobs, mutation serialization, versioning, export projection, recovery, and deletion.
2. `KinetoTests` own presentation ordering, overlay lifecycle, placement normalization, header routing, and accessibility-facing presentation values.
3. Xcode build/test validates target membership and strict Swift concurrency.
4. Real-device trials validate AppKit event handling, security-scoped Finder input, screen/display behavior, TCC, and real meeting-platform exposure.

## Related Code Files

- Modify: `Packages/KinetoCore/Tests/KinetoCoreTests/MeetingPackageStoreTests.swift`
- Create/modify: focused tests under `KinetoTests/`
- Modify: `Kineto.xcodeproj/project.pbxproj` for test membership
- Modify: `docs/design-guidelines.md`
- Modify: `docs/system-architecture.md`
- Modify: `docs/project-overview-pdr.md`
- Modify: `docs/user-guide.md`
- Modify: `docs/codebase-summary.md` when source locations or storage map change
- Modify: `docs/project-roadmap.md` only to record actual evidence or still-open release gates

## Implementation Steps

1. Add Core tests for allowed regular-file encrypted round-trip/reopen, ciphertext non-plaintext inspection, descriptor-only snapshot behavior, count and aggregate-byte boundaries, duplicate rejection, tamper/missing-blob rejection, and concurrent add serialization. Include a security-scoped external file fixture that proves access remains active through the full asynchronous stream and is released after every success and failure path.
2. Add Core fault-injection/reopen tests for every attachment publication boundary: before blob publish, after final blob move but before descriptor commit, after descriptor commit, and during cleanup. Each outcome must recover to either one decryptable committed descriptor/blob pair or no descriptor, blob, staging residue, or consumed quota.
3. Add Core tests for legacy package decoding, manifest v3 topology validation, transcript-only plaintext export, delete, tombstone recovery, and incomplete attachment-stage cleanup.
4. Add app tests for a maximum of four rows, provisional slot precedence, chronological final history, exact translation association, pet-state isolation, and hidden/noncapturing presentation behavior.
5. Add coordinator-level tests or pure geometry helper tests for normalized per-display persistence, malformed preference rejection, clamping after height changes, fallback placement, and caption-body inertness.
6. Run focused Core tests, `swift test --package-path Packages/KinetoCore`, the macOS XCTest scheme, and unsigned arm64 Debug build. Repair regressions rather than loosening contracts.
7. Run the Debug app and exercise: capture start, header-only panel move, Finder file drop, rejection display, accepted import, caption-body inertness, pause/stop/delete, display move/disconnect, and meeting reopen.
8. Perform real-device accessibility and exposure trials: VoiceOver, keyboard-only header reachability, Reduce Motion, Increase Contrast, large text, full-screen Spaces, screen capture, Zoom, Google Meet, and Teams.
9. Update documentation after successful deterministic and smoke validation. State the attachment capabilities and unproven external gates precisely.
10. Request code review focused on cryptographic package durability, AppKit event/focus semantics, and capture-latency regression risk.

## Success Criteria

- [ ] Every deterministic attachment, export, delete, recovery, and presentation contract is covered by a focused test that fails for a plausible regression.
- [ ] Core package tests, macOS XCTest suite, and unsigned arm64 Debug build pass.
- [ ] App smoke path proves a user can reposition the panel and import a bounded file without interrupting capture.
- [ ] Real-device evidence records the result of platform, display, accessibility, and screen-share trials; absent trials remain listed as open gates.
- [ ] Documentation matches implementation and does not claim unsupported attachment processing or automatic attachment export.

## Risk Assessment

- **False assurance:** Xcode tests cannot prove Finder security scope, other-app click behavior, or screen-share disclosure. Keep real-device trials as required release evidence.
- **Sensitive diagnostics:** import errors can leak source paths. Assert user-visible status is generic and source paths do not enter persisted metadata or logs.
- **Regression masking:** tests that only inspect source code miss encrypted package behavior. Test round-trip, failure cleanup, and mutation ordering with real temporary files.
- **Scope drift:** attachment preview/export/model ingestion makes this a different product feature. Treat each as a new approved design decision.
