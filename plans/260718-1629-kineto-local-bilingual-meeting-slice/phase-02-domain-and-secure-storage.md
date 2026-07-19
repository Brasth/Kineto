---
phase: 2
title: "Domain and Secure Storage"
status: pending
priority: P1
dependencies: [1]
---

# Phase 2: Domain and Secure Storage

## Overview

Define the authoritative meeting ledger, explicit session state machine, and authenticated local package before capture or model code can write user data.

## Requirements

- Functional: Create, append, finalize, reopen, export, and delete a meeting without mutating finalized source records.
- Non-functional: Crash-safe commits, fail-closed authentication, no plaintext staging, independent optional-audio deletion.

## Architecture

`MeetingSession` owns runtime and durable lifecycle transitions; immutable value records carry stable IDs and timestamps. `MeetingPackageStore` writes immutable generation manifests, independently sealed payload chunks with fresh stored 96-bit random AES-GCM nonces, and a durably switched active-generation pointer while retaining the prior generation. Distinct per-meeting text/audio wrapping keys use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`; file topology and chunk order are authenticated.

## Related Code Files

- Create: `Packages/KinetoCore/Sources/KinetoCore/Domain/{Meeting,Segment,TranslationRecord,SummaryRecord,EvidenceReference,CaptureGap}.swift`
- Create: `Packages/KinetoCore/Sources/KinetoCore/Session/MeetingSessionState.swift`
- Create: `Packages/KinetoCore/Sources/KinetoCore/Storage/{MeetingPackageStore,MeetingPackageManifest,SealedChunk,MeetingKeyStore,DeletionTombstone}.swift`
- Create: `Packages/KinetoCore/Tests/KinetoCoreTests/{MeetingLedgerTests,MeetingSessionStateTests,MeetingPackageStoreTests}.swift`

## Implementation Steps

1. Define typed `MeetingID`, `SegmentID`, monotonic source sequence, track, spoken language, time range, revision/finality, and confidence metadata.
2. Define states: idle, checking prerequisites, ready, capturing, paused, stopping, processing, completed, failed, deleting; persist lifecycle generation and reject illegal transitions.
3. Keep source segments append-only; allow volatile hypotheses outside persistence and one final record per accepted source ID.
4. Bind schema version, meeting ID, artifact kind, track, sequence, ciphertext length, finality, and a fresh system-generated 96-bit nonce; serialize the nonce with each sealed chunk and reject duplicate nonce use under one DEK.
5. Generate distinct per-meeting text/audio DEKs and wrapping keys with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`; cache only active-session DEKs in memory and define pause/fail-closed behavior on lock.
6. Fsync/close chunks and directories, fsync an immutable generation manifest, atomically switch and fsync a small active pointer, and retain the prior generation until the switch is durable.
7. Make Stop & Delete terminal: persist a tombstone, reject every later producer append, stop/cancel/join producers, delete per-meeting Keychain items before best-effort files, and finish tombstones on relaunch.
8. Stream optional audio directly to separate encrypted chunks; audio-off allocates no audio key or artifact.
9. Export through a restrictive destination-local temporary file, fsync/close, atomically replace the final name, and clean or disclose abandoned plaintext on failure/relaunch.

## Success Criteria

- [ ] Finalized source text/ID cannot be overwritten by translation or summary code.
- [ ] Illegal state transitions fail without partial storage mutations.
- [ ] Mutation, missing key, nonce reuse, remove/reorder/duplicate/cross-meeting/truncate, wrong AAD, and locked/post-reboot access all fail closed.
- [ ] Fault injection at every generation commit boundary preserves either the prior valid package or the complete new package.
- [ ] Audio-off creates no audio key, file, manifest entry, or recoverable plaintext.
- [ ] Deletion keys/tombstones defeat late producers, stale manifests, and recoverable snapshots while allowing independent audio deletion.
- [ ] Interrupted/cancelled export never presents a partial final file and reports any plaintext it cannot clean.

## Risk Assessment

- A custom encrypted format is security-sensitive: keep the schema small, versioned, test-vector driven, and reviewed before capture integration.
- Keychain loss makes encrypted content unrecoverable by design; disclose this instead of adding insecure recovery.
- Export is outside Kineto’s deletion boundary and must be explicitly labeled in UI and docs.
