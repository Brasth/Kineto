---
phase: 6
title: "Native App Experience"
status: pending
priority: P1
dependencies: [2, 3, 4, 5]
---

# Phase 6: Native App Experience

## Overview

Implement the approved Dark Broadcast Studio workflow as native SwiftUI/AppKit views driven solely by Core state and truthful capability status.

## Requirements

- Functional: Contextual blocked setup, Home, Live Focus, Processing, Summary/library/inspector, settings, export, delete.
- Non-functional: macOS semantics, keyboard/VoiceOver, reduced motion, light mode support, compact-window integrity.

## Architecture

A `@MainActor AppModel` observes typed Core events and projects immutable view state. SwiftUI owns app/navigation/content; small AppKit bridges own content picker, window commands, and platform-only dialogs. Views do not call capture/model/storage frameworks directly.

## Related Code Files

- Create: `KinetoApp/App/{KinetoApp,AppModel,AppEnvironment}.swift`
- Create: `KinetoApp/UI/{Home,Setup,Live,Processing,Summary,Settings}/`
- Create: `KinetoApp/UI/Components/{SignalRail,TranscriptRow,CaptureHealth,PrivacyIndicator,EvidenceInspector}.swift`
- Create: `KinetoApp/PlatformUI/{ContentSharingPickerBridge,WindowCommands}.swift`
- Add: `KinetoAppUITests/MeetingWorkflowUITests.swift`

## Implementation Steps

1. Translate the approved wireframe into native split view, toolbar, sheets, dialogs, materials, typography, semantic colors, and focus behavior.
2. Show blocked setup only for missing model/permission/capability; normal launch opens Home ready to select a source.
3. Implement preflight language, summary-language, microphone, retention, effective source boundary, and explicit per-session participant-notification acknowledgment; remember only non-sensitive preferences, never the acknowledgment.
4. Implement Live Focus with persistent capture/privacy/source-scope indicators, health rail, original-first transcript, subordinate translation, gap disclosure, Pause, Stop, and confirmed Stop & Delete.
5. Implement Processing from durable per-stage status; cancellation preserves committed artifacts and idempotent retry never displays partial output as complete.
6. Implement Summary/library with evidence buttons that reveal the cited original support span, machine-generated disclosure, atomic export, and delete boundaries.
7. Add keyboard commands, VoiceOver labels/order/announcements, Dynamic Type-safe layouts, reduced motion, system/light/dark appearance, and compact-window behavior.

## Success Criteria

- [ ] The five approved states match `docs/design-guidelines.md` and the wireframe interaction model.
- [ ] Capture state, processing location, effective source scope, retention, machine-derived content, and export boundary are always visible where relevant.
- [ ] Start requires explicit per-session participant-notification acknowledgment using legally approved launch-market copy.
- [ ] Original transcript is authoritative; every factual evidence action reaches the cited supporting source span.
- [ ] Primary actions remain reachable at compact width with no horizontal scrolling or hidden stop control.
- [ ] Keyboard-only and VoiceOver flows can select, acknowledge, start, pause, stop, inspect evidence, export, and delete.
- [ ] Light/dark/system and reduced-motion states remain usable; color is never the sole status signal.

## Risk Assessment

- HTML is a behavior/reference artifact, not hardcoded SwiftUI geometry; native platform behavior wins where they differ.
- Too much live telemetry harms comprehension; keep detailed diagnostics behind the trailing inspector.
- Destructive controls must remain reachable but never adjacent/equivalent to routine stop without confirmation.
