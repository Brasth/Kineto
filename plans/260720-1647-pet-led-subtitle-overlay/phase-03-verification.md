---
phase: 3
title: Verification and documentation
status: completed
priority: P1
dependencies:
  - 1
  - 2
---

# Phase 3: Verification and documentation

## Overview

Prove deterministic geometry and presentation behavior with focused tests, then build and smoke-test the macOS app. Record physical-device validation that automated tests cannot establish.

## Requirements

- Automated: cover companion-to-caption inverse geometry, linked centering, clamping, and active-last four-row presentation behavior.
- Automated: run the focused floating-caption suite, then the full `Kineto` test scheme.
- Build: run the documented unsigned Debug build and launch the resulting app long enough to prove it remains running.
- Manual: verify companion-led drag, header fallback, multi-display transfer, reset, hidden-companion noninteraction, VoiceOver, Reduce Motion, nonactivation, fullscreen meeting apps, and screen-sharing visibility.

## Related Code Files

- Modify: `KinetoTests/FloatingCaptionPresentationTests.swift` and/or the established focused placement-test location.
- Modify: `docs/design-guidelines.md`, `docs/project-overview-pdr.md`, `docs/system-architecture.md`, and `docs/codebase-summary.md` only where changed behavior requires a contract update.
- Verify: `Kineto.xcodeproj/project.pbxproj` if a new test source is necessary.

## Implementation Steps

1. Add only behavior-level tests that fail if pet-led inverse placement or linked clamping is wrong.
2. Run focused overlay tests, then the full app test scheme; fix failures at the source.
3. Build unsigned Debug, launch the executable, observe it remain running, and stop it cleanly.
4. Update affected documentation to identify the companion as the primary pointer drag affordance and the caption as the following subtitle bar.
5. Document physical-Mac checks as release evidence, not as automated-test claims.

## Success Criteria

- [ ] Focused behavior tests pass.
- [ ] Full app test suite passes.
- [ ] Unsigned Debug build succeeds and app smoke launch remains running.
- [ ] Documentation matches the one persisted caption anchor, companion-led pointer drag, and subtitle-bar composition.
- [ ] Unavailable physical-device checks remain explicitly open rather than inferred from local automation.

## Risk Assessment

| Risk | Mitigation |
|---|---|
| Tests exercise only formulae, not coordinator wiring | Pair pure placement tests with focused caption projection tests and an app launch smoke test. |
| Manual behavior is overstated | Separate observed automated/build evidence from required real-device validation. |
| Stale docs describe header-led drag as primary | Update only the affected captions contract after behavior is proven. |
