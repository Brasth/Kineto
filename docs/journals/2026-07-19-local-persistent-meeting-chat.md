---
date: 2026-07-19
topic: Local persistent meeting chat
status: implemented-manual-smoke-gate-open
---

# Local Persistent Meeting Chat

## Decision

Stopped and reopened meetings now support local-only, source-grounded chat through Apple Foundation Models. The feature remains unavailable while a meeting is live, never sends meeting content to a service, and answers only from the meeting’s finalized source ledger.

## Implementation boundary

- Chat retrieves lexical matches from final transcript segments and treats transcript gaps as hard evidence boundaries.
- The model receives bounded retrieved context as untrusted meeting content; it has no tools or external retrieval path.
- Every displayed answer is accepted only when its citations resolve to retrieved final-source IDs and their quoted support is exact. Unsupported answers/citations are rejected rather than presented as meeting facts.
- `AppModel` owns chat task lifetime so reopening, deletion, navigation, and replacement cannot publish a stale response. Summary review exposes the preserved conversation alongside the existing evidence view.

## Storage and privacy

- `ChatTurnRecord` stores the conversation in the existing encrypted meeting snapshot; export includes it and meeting deletion removes it with the rest of the package/key material.
- Snapshot decoding remains compatible with v1 records and v2 snapshot manifests, while new chats persist through the current format without weakening manifest or authenticated-generation checks.
- Journal content intentionally contains no transcript, prompt, participant, or meeting-specific data.

## Review corrections incorporated

Reviewer follow-up tightened final-source-only retrieval, excluded gap-crossing support, made citation validation strict rather than best-effort, guarded asynchronous task publication, and aligned encrypted history/export/delete handling with existing lifecycle semantics.

## Evidence recorded

The Core test suite and Debug application build passed, and the native app launched successfully. Coverage exercised retrieval/gap boundaries, citation rejection, encrypted snapshot compatibility, chat history lifecycle, export/delete behavior, and task cancellation/publication protections.

## Remaining manual gate

A real-Mac stopped-meeting flow still needs manual verification: finalize/reopen a meeting, ask a locally grounded question, inspect citations and history, then export/delete it; repeat where Apple Foundation Models are unavailable to confirm the honest unavailable state. The smoke app launched, but its current UI session had no accessible stopped meeting to drive this flow. This remains a smoke gate, not a claim of release readiness.

## Composer refinement

The Summary review now separates generated review from a dedicated **Ask** workspace, so the conversation and its composer retain their own vertical space while the source transcript stays primary in the adjoining pane. The compact multiline composer preserves typed drafts unless the existing local request is accepted, keeps ordinary Return for line breaks, sends with Command-Return or the visible Send button, limits questions to 1,500 characters, and discloses local encrypted retention. Empty conversations offer neutral, non-autonomous question starters. The refactor is presentation-only: it does not alter retrieval, evidence validation, persistence, export, deletion, or model-provider boundaries.

## Composer verification

The Core suite and Debug app build passed after the refinement. A native screenshot confirmed that the Debug app opened its meeting library, including saved meetings. Native automation could not select one or drive its controls because `osascript` lacks macOS Assistive Access in this environment. Manual real-Mac verification remains required for the editor’s Return/Command-Return behavior, focus and VoiceOver hints, character limit, draft restoration after an answer-save error, and compact-sidebar layout.
