---
title: Kineto Design Guidelines
status: proposed-for-wireframe-review
updated: 2026-07-18
---

# Kineto Design Guidelines

## Direction: Dark Broadcast Studio

Kineto is a focused, dark-first meeting workspace with a luminous mint signal accent. Meeting content dominates; the live state feels active without becoming a telemetry dashboard. The memorable element remains a **signal rail** connecting capture, transcription, translation, and post-stop evidence validation.

Use native macOS controls, behaviors, typography, and adaptive materials. Dark is the authored reference appearance; light mode remains fully supported. The HTML wireframe approximates these decisions for review and is not a source of hardcoded SwiftUI values.

## Product principles

1. **Trust is visible:** always show whether capture is active, where processing occurs, and whether raw audio is retained.
2. **Source before derivation:** original transcript is visually primary; machine translation and summary are labeled and subordinate.
3. **One primary action:** each state has one dominant next step—download, start, stop, or export.
4. **Progressive disclosure:** routine meeting flow stays simple; model, storage, and diagnostics detail lives in secondary views.
5. **Native over novel:** use platform pickers, menus, toolbars, sheets, alerts, keyboard conventions, and accessibility semantics.

## Information architecture

```text
Home / Library
├── New Meeting
├── Recent meetings
├── Model & Language
└── Privacy & Storage

Contextual meeting flow
Home → New Meeting → Live Focus → Processing → Summary
             └── Blocked capability setup only when required
```

- Home and Summary show the library sidebar; Live, Processing, and blocked setup hide it.
- Live uses the full canvas for transcript plus an optional trailing capture-health inspector.
- Summary restores the library and offers a resizable/collapsible trailing evidence inspector.
- At compact widths, hide inspectors before collapsing the library.
- Never create nested scrolling around the transcript; transcript is the primary scroll region.

## Core screens

### Home and contextual setup

- Home starts with a ready-to-capture meeting card, source, summary language, raw-audio policy, and recent meetings.
- Do not show a permanent checklist of already-satisfied permissions and models.
- Open focused setup only for an unavailable permission, model, translation pair, or language asset.
- A blocked-capability view states the cause, retained progress, exact recovery action, and safe dismissal behavior.
- Microphone denial does not block system audio.
- Put participant-notification language beside the manual Start button.
- Raw-audio retention status must be explicit before capture starts.

### Live Meeting

- Persistent recording mark, elapsed time, effective selected-source boundary, and local-processing badge.
- Original segments use normal foreground text; translations use secondary text plus an accent rule.
- Volatile ASR is visually softer and replaced in place; finalized text becomes stable.
- Speaker labels are `You` and `Selected Source`; use `Meeting` only after source-isolation proof and never imply participant recognition.
- Controls: Pause, Stop, Stop & Delete. Destructive actions remain separated and labeled.
- Capture-health inspector shows effective source scope, source tracks, translation backlog, and resource state without private content.

### Processing

- Stopping rejects callbacks, drains/flushes bounded ASR work, and seals the source transcript before summary work begins.
- Show translation finalization, summary generation, and extractive evidence validation as distinct stages.
- Allow summary cancellation without deleting the authoritative transcript or finalized translations.
- Failure offers idempotent retry or transcript-only completion; it never reopens capture or invents a completed result.

### Summary

- Summary language is the meeting-selected English or Vietnamese locale.
- Overview, decisions, and action items each link to original segment IDs plus supporting spans.
- Evidence inspector shows timestamp, track label, spoken language, highlighted original support, and labeled translation when present.
- Unknown or unsupported owner/date/amount stays explicitly unknown; UI never converts absence into an assignment.

## Visual system

### Typography

Use San Francisco through semantic SwiftUI text styles. Do not bundle display fonts.

- Window/section title: `.title2` or platform-equivalent, semibold.
- Main document heading: `.title`, semibold, tight but system-controlled tracking.
- Transcript: `.body`, regular, comfortable line spacing.
- Speaker/field label: `.caption`, medium or semibold.
- Timestamp/timer: monospaced digits; avoid layout movement.
- Support Dynamic Type and never encode state by font size alone.

### Color and materials

Use semantic platform colors and materials; support light appearance, but author and validate the dark capture experience first.

- Dark window/sidebar/surface roles use deep green-black graphite with clear separators.
- Primary text uses high-contrast label color; secondary metadata uses secondary-label color.
- Signal accent uses luminous mint for tint, focus, active pipeline state, waveform texture, and translation rule.
- Recording/destructive uses system red plus label/icon; never color alone.
- Warning uses system orange plus recovery text.
- A very subtle signal/waveform texture may appear only in Live Focus and must disappear with Reduce Transparency or increased contrast.
- Do not use decorative gradients, translucent transcript cards, or multiple brand accents.

### Spacing and shape

- 4 pt base rhythm; common gaps 8, 12, 16, 24, and 32 pt.
- Content gutters: 20–28 pt depending on window width.
- Control hit regions: at least 28 pt on macOS, with standard system control sizes.
- Corners: system defaults; cards approximately 8–10 pt where grouping needs a boundary.
- Prefer separators and material changes over shadows. Reserve elevation for floating recording controls and sheets.

## Components

- **Signal rail:** four textual states with dot and connector; color and fill indicate progress.
- **Blocked capability card:** shown only for a missing requirement; includes cause, progress, retry, and safe dismissal.
- **Processing stages:** transcript, translation, and summary/evidence status without implying completion early.
- **Utterance:** timestamp, source label, spoken-language tag, original text, optional translated text.
- **Evidence link:** source count or timestamp button; keyboard and VoiceOver reachable.
- **Capture badge:** persistent recording/local/retention state, not a transient toast.
- **Meeting package row:** title, date/duration, and language metadata; no content preview in notifications.

## Interaction and motion

- State feedback begins immediately; operations over 300 ms show determinate progress when available.
- Use native transitions only when they explain state change; 150–250 ms target for custom micro-interactions.
- Volatile-to-final transcript replacement may crossfade without moving the reading position.
- All motion must remain interruptible and honor Reduce Motion.
- Provide menu commands and keyboard shortcuts for New Meeting, Start/Pause/Stop, Add Marker, and Export where safe.
- Stop & Delete always requires a confirmation dialog describing exactly what is removed.

## Accessibility

- Full keyboard traversal with visible focus and logical order.
- VoiceOver labels include control purpose and current capture/permission state.
- Announce finalized segments and errors politely; do not continuously announce volatile tokens.
- Never depend on teal/red/orange alone—pair color with text, icon shape, or both.
- Preserve readable transcript width at larger text sizes; wrap rather than truncate source content.
- Verify Increase Contrast, Reduce Transparency, Reduce Motion, dark mode, and largest practical text size.
- Live transcript and recording controls remain usable when the optional inspector is hidden.

## Privacy copy rules

- Say **“processed on this Mac”**, not “100% private.”
- Say **“raw audio off/on for this meeting”**, not a vague “private mode.”
- Label mixed application/system audio **“Selected Source”** and disclose browser/application-wide scope; use **“Meeting”** only after isolation proof.
- Require explicit per-session acknowledgment that the operator informed participants; do not imply Zoom/Meet/Teams recording indicators are active.
- Disclose that explicit exports are plaintext copies outside Kineto’s deletion boundary.

## Wireframe review artifact

Open `plans/design/kineto-wireframes.html`. Review five states in dark and light appearance:

1. Contextual blocked setup
2. Home / ready meeting
3. Live Focus without library sidebar
4. Post-stop Processing
5. Evidence-linked Summary with library and inspector

## Acceptance checklist

- Manual start and persistent capture indicator are unmistakable.
- Original text remains visually authoritative over translation and summary.
- EN/VI code-switching is readable without creating separate meeting modes.
- Local processing and raw-audio retention are visible before and during capture.
- Effective source scope and explicit per-session participant-notification acknowledgment appear before Start and remain visible during capture.
- Pause, Stop, and Stop & Delete remain reachable with keyboard and assistive technology.
- Window remains usable at compact width without horizontal scrolling or hidden primary controls.
