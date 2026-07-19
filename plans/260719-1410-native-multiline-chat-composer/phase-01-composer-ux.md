---
phase: 1
title: Composer UX
status: completed
priority: P2
dependencies: []
---

# Phase 1: Composer UX

## Overview

Implement the approved compact multiline question composer in the existing Summary sidebar without changing domain, persistence, or evidence behavior.

## Requirements

- Replace the chat `TextField` in `KinetoApp/UI/Home/HomeView.swift` with a bounded native `TextEditor`.
- Preserve embedded newlines while editing; cap drafts to 1,500 characters at the binding boundary.
- Return inserts a newline. Command-Return and the explicit Send button share one guarded send path.
- Clear and unfocus only when `AppModel` synchronously accepts the request by entering its existing answer-in-flight state. Preserve drafts for empty, unavailable, busy, raced, and error paths.
- Add compact local-processing and encrypted-retention disclosure, state-specific availability/progress copy, and persistent VoiceOver label/hint.
- Keep the existing `HSplitView`, transcript pane, newest-first turn rendering, evidence links, `AppModel` API, and local-only Core boundaries unchanged.

## Architecture

`HomeView` remains the only modified product file. A focused private composer view/helper owns transient draft and focus state, while `AppModel.askCurrentMeeting(question:)` remains the sole submit gateway and continues to own stopped-state eligibility, cancellation, snapshot retrieval, local generation, encrypted append, and stale-result suppression.

## Related Code Files

- Modify: `KinetoApp/UI/Home/HomeView.swift`
- Inspect only: `KinetoApp/App/AppModel.swift`
- Inspect only: `Packages/KinetoCore/Sources/KinetoCore/Chat/MeetingChatService.swift`
- Inspect only: `Packages/KinetoCore/Sources/KinetoCore/Storage/MeetingPackageStore.swift`

## Implementation Steps

1. Add local focus and bounded-draft support next to the existing chat draft state; truncate both typed and pasted input without changing embedded newlines.
2. Replace the horizontal field/send row with a vertical native composer: transcript-scope copy, encrypted-local-retention disclosure, compact multiline editor, keyboard/count helper, and explicit Send control.
3. Route Command-Return and Send through one helper. Consume only Command-Return; allow ordinary Return to reach the editor. Preserve drafts unless the existing model accepts the request.
4. Make transcript-not-ready, summary-generating, and answer-in-flight states distinct while retaining current no-answer, turn, citation, and evidence-sheet rendering.
5. Add accessible editor/button names, keyboard hints, character-count value, and state text without creating a custom accessibility bridge.

## Success Criteria

- [ ] The stopped/reopened Summary view presents a compact multiline native editor capped at 1,500 characters.
- [ ] Return adds a line; Command-Return and Send create at most one accepted request and share the same behavior.
- [ ] Draft text is retained whenever submission is not accepted.
- [ ] Scope, local encrypted-retention, availability, progress, and keyboard behavior remain understandable visually and to VoiceOver.
- [ ] No provider, storage, service, evidence, transcript, or persisted-turn behavior changes.

## Risk Assessment

The main risks are accidental multiline submission, draft loss during a state race, and a textarea that consumes the review sidebar. Bound editor height/length, rely on the model's existing acceptance state, keep all unmodified Return keypresses unhandled, and avoid an AppKit wrapper or sidebar restructure.
