---
phase: 1
title: Storage contract
status: completed
priority: P1
dependencies: []
---

# Phase 1: Storage contract

## Overview

Extend the encrypted meeting package with a bounded attachment descriptor set and separately encrypted file blobs. Preserve atomic generation publication, serialized mutations, legacy package readability, transcript-only export, and key-first deletion.

## Requirements

- Functional: accept only regular files; enforce 10-file and 250 MiB aggregate limits; reject duplicate bytes, unreadable sources, directories, quota overflow, and interrupted copies.
- Functional: copy accepted bytes under package-local encrypted storage and publish a descriptor only after the blob is durable.
- Functional: list descriptors in the encrypted snapshot for meeting lifecycle ownership, but exclude descriptors and bytes from current plaintext transcript export.
- Functional: legacy v1/v2 packages decode with zero attachments; new packages use a versioned manifest topology that validates attachment IDs and bounded metadata.
- Non-functional: stream files in fixed chunks; never materialize a 250 MiB input in one `Data`, JSON payload, or actor message.
- Non-functional: all capacity checks, duplicate checks, staging, blob publication, and descriptor commit are serialized by the existing `mutationMutex`.

## Architecture

Create a value-type `AttachmentRecord` descriptor with a stable UUID, original filename, UTI string, byte count, content digest, encrypted blob reference, import timestamp, and meeting ownership. It contains no `URL` or bytes.

Add `attachments` to `MeetingSnapshot` with a missing-key default of `[]`. Add manifest v3 with ordered `attachmentIDs` and validate the snapshot/manifest topology, ID uniqueness, count, total bytes, descriptor ownership, and the referenced encrypted blob’s presence.

Encrypt each file with a bounded, versioned chunk format under an attachment-specific per-meeting Keychain key and stable attachment AAD. Publish the blob from a package-local staging path before committing the descriptor generation. Use an explicit transcript-export projection instead of serializing `MeetingSnapshot` directly.

## Related Code Files

- Create: `Packages/KinetoCore/Sources/KinetoCore/Domain/AttachmentRecord.swift`
- Create: focused attachment streaming helper under `Packages/KinetoCore/Sources/KinetoCore/Storage/`
- Modify: `Packages/KinetoCore/Sources/KinetoCore/Storage/MeetingPackageStore.swift`
- Modify: `Packages/KinetoCore/Sources/KinetoCore/Storage/MeetingKeyStore.swift`
- Modify: `Packages/KinetoCore/Tests/KinetoCoreTests/MeetingPackageStoreTests.swift`
- Modify: Xcode/package source registration only if the project does not auto-discover the new Core source.

## Implementation Steps

1. Define `AttachmentRecord` as `Codable`, `Equatable`, and `Sendable`; enforce normalized nonempty filenames, valid meeting ownership, nonnegative size, fixed digest format, and no source-path field.
2. Add `attachments` to `MeetingSnapshot` with custom backward-compatible decode. Keep attachment bytes structurally outside transcript, translation, chat, and summary domain records.
3. Add a dedicated attachment key purpose to `MeetingKeyStore`; extend create, lookup, delete, and in-memory test stores. Do not reuse the optional audio-retention key.
4. Implement a chunked encrypted blob writer/reader using bounded buffers, authenticated header/chunk records, cryptographically random nonces, attachment-specific AAD, durable sync, and a deterministic ciphertext path below the meeting package.
5. Add `MeetingPackageStore.addAttachment(meetingID:sourceURL:)` and any minimal descriptor lookup API. The storage operation owns security-scoped access: call `startAccessingSecurityScopedResource()` before the first resource read and release it with `defer` only after hashing, encryption, fsync, publish, or failure cleanup completes. Validate regular-file resource values, file count, aggregate bytes, and streamed SHA-256 before publication.
6. Execute the complete add operation through `mutationMutex`: stage encrypted blob within the meeting package, atomically move it to the attachment path, commit the descriptor snapshot/manifest generation, and remove staged output on every ordinary failure.
7. Upgrade manifest encoding to v3. Decode v1/v2 manifests with no attachment IDs; validate v3 descriptor ordering, uniqueness, quota, meeting ownership, and encrypted blob presence before returning a snapshot.
8. Replace direct `MeetingSnapshot` JSON export with a transcript-export projection that preserves the current externally observed transcript contract while omitting attachment descriptors and bytes.
9. Extend recovery to sweep incomplete attachment/blob/metadata stages and orphan blob candidates safely without deleting the Keychain-authoritative current generation. Ensure tombstone delete and ordinary delete remove attachment blobs and stages.
10. Keep `MeetingPackageStore` APIs the only attachment persistence boundary. No capture, ASR, translation, chat, or summary type accepts attachment content.

## Success Criteria

- [ ] A regular file survives encrypted write, relaunch snapshot readback, and authenticated decrypt with no plaintext bytes in the package.
- [ ] The 11th file and a byte total above 250 MiB are rejected without publishing metadata or blobs.
- [ ] Duplicate byte content is rejected deterministically without a second descriptor.
- [ ] A missing/tampered blob or manifest topology mismatch fails closed.
- [ ] Existing v1/v2 fixtures reopen with zero attachments; new v3 fixtures preserve attachment descriptors.
- [ ] Plaintext transcript export includes neither attachment metadata nor bytes.
- [ ] Delete, tombstone recovery, and interrupted attachment staging leave no readable attachment artifact.

## Risk Assessment

- **Memory pressure:** whole-file sealing would allocate up to 250 MiB. Mitigate with fixed-size chunk I/O and test over-limit rejection without a full-file load.
- **Broken references:** committing metadata before blobs creates unreadable snapshots. Mitigate by publishing durable blobs before Keychain-authoritative descriptor generations.
- **Data exposure:** snapshot JSON export would reveal descriptors after schema expansion. Mitigate with a dedicated transcript projection and regression tests.
- **Crash residue:** existing recovery does not sweep attachment stages. Mitigate with package-local staging and explicit startup recovery.
