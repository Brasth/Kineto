# Latency, Translation Drain, Conversation Summary

Status: implemented

## Goal
Lower final transcript latency, finish remaining translations after Stop, and produce conversation-focused evidence-linked summaries.

## Acceptance
1. Default ASR chunk duration is 4 seconds; coordinator still drains residual audio and emits gaps under backpressure.
2. Stop seals the source ledger, drains pending translations (does not cancel them), then generates summary.
3. After source is stopped, translation and summary derived writes remain allowed; late source/gap writes stay rejected.
4. Summary uses map/reduce with conversation overview prose plus exact evidence excerpts.
5. Existing Core tests pass after contract updates; Debug build succeeds.

## Done
- 4s ASR default chunk
- Post-stop idempotent translation writes
- Stop drains/reconciles translations before summary
- Two-pass SummaryService + excerpt evidence validator
- Stop/source-loss/delete lifecycle race fixes
- Docs + contracts updated
- 14/14 Core tests pass; Debug build succeeded

## Deferred
- Rolling volatile partial hypotheses
- Second Whisper context / explicit global recognizer scheduler
- Persisted derivation plan fields on Meeting
- Template settings UI
