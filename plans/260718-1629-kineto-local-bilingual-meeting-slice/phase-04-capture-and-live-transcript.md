---
phase: 4
title: "Capture and Live Transcript"
status: pending
priority: P1
dependencies: [1, 2, 3]
---

# Phase 4: Capture and Live Transcript

## Overview

Capture selected-source audio and optional microphone as separate timestamped tracks, feed bounded ASR work, optionally stream retained audio into encrypted chunks, and persist finalized source/gap records.

## Requirements

- Functional: Manual select/start/pause/resume/stop/delete across Zoom, Google Meet, and Teams desktop/browser scenarios.
- Non-functional: Capture never waits on ML, bounded memory, deterministic shutdown, independent permission degradation.

## Architecture

`MeetingCapture` owns `SCStream`; callbacks perform minimal copies into bounded per-track fan-out queues. `AudioNormalizer` preserves source timing. Overflow drops oldest pending ASR audio, emits a durable `CaptureGap`, and forces a recognizer boundary so speech never bridges missing audio. Optional retention has its own bounded direct-to-encrypted sink. `TranscriptCoordinator` appends finalized records only.

## Related Code Files

- Create: `Packages/KinetoCore/Sources/KinetoCore/Capture/{MeetingCapture,CaptureConfiguration,CaptureEvent}.swift`
- Create: `Packages/KinetoCore/Sources/KinetoCore/Audio/{AudioFrame,BoundedAudioQueue,AudioNormalizer,EncryptedAudioSink}.swift`
- Create: `Packages/KinetoCore/Sources/KinetoCore/ASR/TranscriptCoordinator.swift`
- Create: `KinetoApp/PlatformUI/ContentSharingPickerBridge.swift`
- Create: `Packages/KinetoCore/Tests/KinetoCoreTests/{BoundedAudioQueueTests,TranscriptCoordinatorTests,CaptureShutdownTests}.swift`

## Implementation Steps

1. Present `SCContentSharingPicker`; preserve its effective application/display boundary and never imply browser-tab isolation.
2. Before start, warn for browser/application-wide audio scope; keep the effective boundary visible live and pause/stop on topology change.
3. Verify audio-focused `SCStream` behavior on macOS 26.1; otherwise consume/discard minimum video frames.
4. Capture source audio and microphone independently with timestamps and `Selected Source`/`You`; use `Meeting` only after an isolation trial proves it.
5. Normalize off callback threads. On overflow, record exact gap intervals, force ASR boundaries, and surface retained-audio gaps without blocking callbacks.
6. If retention is enabled, stream each track directly into bounded encrypted chunks; never stage plaintext.
7. Feed one recognizer serially; replace volatile UI state and append only finalized source/gap records.
8. Stop in order: reject callbacks, close queues, drain normalization, flush/end recognizer, await terminal final event, commit/seal ledger, then freeze processing snapshot.
9. Persist interrupted lifecycle state; on launch never restart capture, finish deletion tombstones, recover the last valid ledger, mark interruption, and offer idempotent derived-stage retry.

## Success Criteria

- [ ] First-grant/relaunch, denied/revoked permission, mic-only, lock/sleep, and interrupted-session states have truthful recovery.
- [ ] Tracks never merge before labeling; UI never calls application-wide/browser audio `Meeting` without proof.
- [ ] Capture callbacks stay bounded and execute no ASR, translation, encryption, or UI work.
- [ ] Queue saturation persists visible gap records and never joins speech across missing PCM.
- [ ] Stop-during-utterance and stop-under-saturation flush the final tail before sealing evidence.
- [ ] Retention on/off, sink saturation, audio deletion, Zoom, Meet, and Teams trials verify actual behavior and scope disclosure.

## Risk Assessment

- ScreenCaptureKit’s finest reliable audio boundary is application-level; selected browser windows may still include sibling-tab/process audio.
- TCC behavior and audio-only output details require real-mac proof, not simulator/unit confidence.
- Meeting applications can change process/audio topology during calls; surface source loss rather than silently switching.
