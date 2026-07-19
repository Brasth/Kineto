---
phase: 5
title: "Translation and Summary"
status: pending
priority: P1
dependencies: [2, 4]
---

# Phase 5: Translation and Summary

## Overview

Translate finalized EN/VI segments and generate one post-stop English or Vietnamese summary whose factual fields are rejected unless they carry valid source IDs plus extractive support from original text.

## Requirements

- Functional: Pair-gated bidirectional translation, code-switch preservation, summary overview/decisions/actions, evidence navigation.
- Non-functional: No live LLM contention, no tools/side effects, bounded context, explicit runtime unavailability.

## Architecture

`TranslationService` consumes finalized source segments only. `SummaryService` consumes an immutable meeting-snapshot generation after stop, performs bounded map/reduce, and commits each stage with an idempotency key and durable status. `EvidenceValidator` requires cited IDs plus verbatim support spans or deterministic normalized values in original source text; otherwise the field is omitted/unknown.

## Related Code Files

- Create: `Packages/KinetoCore/Sources/KinetoCore/Translation/{TranslationService,TranslationAvailability}.swift`
- Create: `Packages/KinetoCore/Sources/KinetoCore/Summary/{SummaryService,SummarySchema,EvidenceValidator,MeetingSnapshot,ProcessingStage}.swift`
- Create: `Packages/KinetoCore/Tests/KinetoCoreTests/{TranslationContractTests,EvidenceValidatorTests,SummaryFallbackTests}.swift`

## Implementation Steps

1. Before implementing the full summary path, measure bounded Foundation Models work on the worst supported 8 GB SoC and set shipped/deferred behavior.
2. Check source/target pair status at runtime and prepare language assets only after user intent; never infer pair support from locale lists.
3. Translate only finalized segments whose spoken language differs from the selected reading language; preserve source ID/locales/status/disclosure.
4. Freeze an immutable meeting-snapshot generation and partition it by token budget while retaining IDs/timestamps.
5. Key each translation/summary stage by snapshot generation, source IDs, locale/model, and stage; atomically commit output plus cancelled/failed/completed status.
6. Generate extractive partial facts, then validate each factual field against its cited original span/normalized value before reduction and display.
7. Keep prompt-injection text inert, pass no tools/side effects, and omit/mark unknown any unsupported owner/date/amount/decision/action.
8. On unavailability, cancellation, crash, or context limit, provide idempotent retry or transcript/translation-only completion without duplicate derived records.

## Success Criteria

- [ ] EN→VI and VI→EN pair checks/fixtures pass on a provisioned Mac.
- [ ] Code-switch meetings retain each original segment and translate only for the selected reading language.
- [ ] Translation/summary failure never delays capture/finalized ASR or mutates source records.
- [ ] Every factual field resolves to existing IDs and verified extractive support in original text.
- [ ] Unsupported owner/date/amount remains absent or explicitly unknown.
- [ ] Cancellation/relaunch/retry never duplicates derived records or exposes partial output as complete.
- [ ] The measured 8 GB summary policy and unavailable/disabled/context-limit fallback are explicit.

## Risk Assessment

- Framework locale availability can vary by OS asset state; gate at runtime and test both directions on clean accounts.
- Foundation Models behavior can change across macOS releases; application validation, not prompt wording, enforces provenance.
- Summary work may pressure 8 GB devices; defer it, cap chunks, and allow cancellation before affecting capture-critical work.
