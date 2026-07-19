---
title: Native multiline meeting-chat composer
description: >-
  Focused native SwiftUI textarea-style composer for stopped/reopened local
  meeting chat.
status: in-progress
priority: P2
branch: research/macos-meeting-intelligence
tags:
  - macos
  - swiftui
  - accessibility
  - local-chat
blockedBy: []
blocks: []
created: '2026-07-19T06:53:08.136Z'
createdBy: 'ck:plan'
source: skill
---

# Native multiline meeting-chat composer

## Objective

Replace the stopped/reopened meeting chat's single-line input with a compact, accessible native multiline composer. Preserve all local-only retrieval, encrypted persistence, source-evidence, transcript, and task-lifecycle contracts.

## Confirmed product contract

- The composer appears only in the existing Summary review of an active stopped/reopened meeting.
- It accepts at most 1,500 characters, including pasted text.
- Return inserts a newline; Command-Return and the explicit Send button use the same guarded submission path.
- Only accepted sends clear the draft. Empty, unavailable, busy, raced, and persistence-error paths retain it.
- The UI discloses that questions and answers are processed on this Mac and saved in the encrypted meeting package.
- `AppModel.askCurrentMeeting(question:)`, Core chat retrieval, encrypted storage, source citations, evidence navigation, transcript layout, and saved-turn order remain unchanged.

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Composer UX](./phase-01-composer-ux.md) | Completed |
| 2 | [Verification](./phase-02-verification.md) | In Progress |

## Dependencies

- Builds on the existing local persistent-meeting chat implementation.
- Does not block or alter the broader bilingual meeting slice plan; it is a presentation-only refinement.
