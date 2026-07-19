---
phase: 7
title: "Verification and Release"
status: pending
priority: P1
dependencies: [1, 2, 3, 4, 5, 6]
---

# Phase 7: Verification and Release

## Overview

Prove the vertical slice on supported hardware, close privacy/security/distribution gaps, and produce a signed, notarized direct-download artifact with reproducible model provenance.

## Requirements

- Functional: End-to-end capture through encrypted reopen, evidence-linked summary, export, deletion, relaunch.
- Non-functional: 8/16 GB gates, offline meeting path, TCC recovery, tamper resistance, signed/notarized hardened release.

## Architecture

Verification is layered: deterministic Core contract tests, app build/launch tests, real-device fixture benchmarks, real meeting-platform trials, security/privacy review, then release-signing checks. CI cannot replace Mac/TCC/notarization evidence.

## Related Code Files

- Create/update: `KinetoTests/`, `KinetoAppUITests/`, `Packages/KinetoCore/Tests/`
- Create: `scripts/verify-model-artifacts.sh`, `scripts/build-release-dmg.sh`; add `scripts/build-whisper-xcframework.sh` only if whisper ships
- Create: `Config/Release.xcconfig`, `Config/ExportOptions.plist`, deterministic DMG layout/assets
- Update after proof: `docs/{deployment-guide,codebase-summary,system-architecture,project-roadmap}.md`

## Implementation Steps

1. Run deterministic package tests, app build, app launch, and focused UI workflow tests with no skipped failures.
2. Confirm Phase 3/5 gates on the worst supported SoC in each shipped 8/16 GB tier under active Zoom/Meet/Teams workloads; do not generalize from a newer 16 GB Mac.
3. Re-run EN/VI dialect/accent/code-switch/names/numbers/currency/dates/noise/overlap/negation regression without reopening the selected-engine decision unless thresholds fail.
4. Exercise TCC grant/relaunch/denial/revocation, mic-only, source/topology loss, lock/sleep/wake, crash/relaunch, queue gaps, model/storage partial failures, deletion tombstones, and interrupted export/processing.
5. Run release-mode canary transcript/prompt/source/path values through every forced error/crash path; collect unified logs/diagnostics/crash reports and fail on any canary. Verify main-app/helper entitlements and offline meeting behavior.
6. Make launch-market recording/consent counsel approval and exact per-session acknowledgment copy a hard release gate; state that external capture does not activate meeting-platform recording indicators.
7. Independently rebuild/compare native binaries, verify model provenance/notices, then sign/notarize/staple the app. Build the deterministic DMG, sign/notarize/staple that exact DMG, record its digest, and Gatekeeper-test the same quarantined clean-account artifact.
8. Record exact toolchain/model/framework availability, supported SoC/memory matrix, benchmark evidence, limitations, rollback instructions, and final decisions in project docs.

## Success Criteria

- [ ] Every observable contract introduced in Phases 1–6 has deterministic or real-device proof.
- [ ] The minimum SoC and 8/16 GB feature matrix is backed by worst-supported-device measurement.
- [ ] Meeting capture/processing works with network disabled; the capture app has no network entitlement and the helper cannot access meeting data.
- [ ] Canary values never appear in logs, diagnostics, analytics, or crash metadata.
- [ ] Counsel-approved participant-notification copy and explicit per-session acknowledgment are present before release.
- [ ] The exact distributed DMG and contained app are hardened, Developer ID-signed, notarized, stapled, digest-recorded, and accepted by Gatekeeper.
- [ ] Independently reproduced native bytes, notices, model provenance, update/removal, and offline rollback match the release.

## Risk Assessment

- Signing/notarization requires user-owned Apple credentials and agreements; this is a hard external release gate.
- Launch-market counsel approval is mandatory; do not imply Zoom/Meet/Teams indicators are activated by external capture.
- If hardware or bilingual gates fail, narrow support, reduce the checkpoint, or defer summary—never hide degradation or loosen evidence rules.
