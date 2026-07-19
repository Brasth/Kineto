---
phase: 2
title: Verification
status: in-progress
priority: P2
dependencies:
  - 1
---

# Phase 2: Verification

## Overview

Prove that the UI refinement compiles, preserves the existing local chat contract, and behaves correctly on a native macOS review screen.

## Requirements

- Run Core tests to guard unchanged local retrieval, exact citation, encrypted chat persistence, export, and deletion behavior.
- Build the Debug app with the repository's existing scheme and no code signing.
- Perform native keyboard and accessibility smoke checks because no UI-test target exists.

## Related Code Files

- Verify: `Packages/KinetoCore/Tests/KinetoCoreTests/MeetingChatServiceTests.swift`
- Verify: `Packages/KinetoCore/Tests/KinetoCoreTests/MeetingPackageStoreTests.swift`
- Verify: `KinetoApp/UI/Home/HomeView.swift`
- Update after proof only if warranted: `docs/user-guide.md`, `docs/design-guidelines.md`

## Implementation Steps

1. Run focused Core chat and storage tests, then the full Core test suite.
2. Build the native app with `xcodebuild -project Kineto.xcodeproj -scheme Kineto -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build`.
3. On macOS, verify typed and pasted 1,500-character bounds; Return newline; Command-Return and Send; blank/unavailable/busy draft preservation; local disclosure; focus traversal; VoiceOver labels/hints; and saved-turn evidence navigation.
4. Confirm no network entitlement, service/provider, persistence, or evidence contract changed. Update documentation only when the observed behavior requires it.

## Success Criteria

- [ ] Focused and full Core tests pass.
- [ ] The Debug app builds without new diagnostics.
- [ ] Native smoke confirms multiline input, keyboard send, draft preservation, responsive compact-sidebar layout, and accessible labels/hints.
- [ ] Existing local-only, source-grounded, encrypted chat behavior remains unchanged.

## Risk Assessment

Core tests cannot prove native text-editor key handling, VoiceOver wording, or Dynamic Type layout. Treat the native smoke as a required release-evidence gate; do not substitute a successful build for interactive validation.
