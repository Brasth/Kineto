# Research Report: Live Transcript Latency

- **Date:** 2026-07-18
- **Scope:** End-to-end delay from speech to UI text/translation in Kineto
- **Mode:** Debug root-cause + architecture research (no code changes)

## Executive Summary

Yes — live transcript delay can be reduced. The dominant lag is **architectural**, not “Whisper is slow on M-series.”

Kineto only shows text after a **fixed audio chunk fills**, **one serialized Whisper job finishes**, and an **encrypted package generation commits**. There is **no end-of-utterance flush** and **no volatile/partial text**. So the UI cannot “update the world right after a person speaks”; it updates after the chunk pipeline.

Translation is already **after** source segments and can lag more. That matches the product preference (source first, translation acceptable delay) — but translation also **persists before UI**, and `TranslationService` is a single actor (serial).

**Primary levers (impact order):**  
1) stop blocking UI on per-segment store commit  
2) silence / VAD early flush  
3) shorter chunks (± overlap)  
4) optional dual recognizer if mic+source contend  
5) volatile partials only if still not enough (larger change)

## Latency budget (code-derived)

```text
speech ──capture/normalize──► 2s chunk buffer
                              │ wait 0..2s to fill (often ~1s avg)
                              ▼
                         job queue (1 in-flight + 2 queued / source)
                              │ wait if previous ASR still running
                              ▼
                      WhisperRecognizer (single actor / context)
                              │ inference ~ RTF × chunk (turbo+Metal usually << chunk)
                              ▼
                   MeetingPackageStore.append (AES-GCM generation)
                              │ disk + crypto commit BEFORE UI event
                              ▼
                      TranscriptEvent.finalized → AppModel.segments
                              │
                              ├─ UI shows original
                              └─ Task → TranslationService (actor, serial)
                                         → store.append(translation)
                                         → UI shows translation
```

### Component costs

| Stage | Current behavior | Typical contribution |
|---|---|---|
| Chunk fill wait | Fixed `chunkDuration = 2` | **0–2s** after speech in window; **no early cut on silence** |
| Queue wait | 1 in-flight + 2 queued per `AudioSource` | 0 if idle; **multiplies** if RTF>1 or dual sources share one Whisper |
| Whisper | `large-v3-turbo-q5_0`, Metal, ≤4 threads, `no_context=true` | Often **sub-second per 2s** on Apple Silicon; not usually the only bottleneck |
| Store before UI | `store.append` then `output.yield` | **Can dominate** if every segment = new encrypted generation |
| Translation | Async task after source UI append | Extra Apple Translation + **another store commit** before translation UI |
| Partial/volatile | **None** | Entire phrase invisible until final path completes |

### Measured hooks already present

- `AppModel.lastTranscriptLagSeconds` ≈ `now - meetingStart - segment.endTime`  
  Good rough “how far behind live” signal — use it in live inspector while tuning.

### Doc / plan drift

- Code default: **2s** chunks (`TranscriptCoordinator`)  
- Plan `260718-1935-latency-translation-summary`: claimed **4s** default implemented  
- Some narrative docs still mention older buffer stories  
Treat **code** as truth: **2s fixed chunks, final-only**.

## Root causes (debug)

### RC-1 — Fixed window, not utterance-driven (primary UX gap)
Coordinator only cuts at `chunkSampleCount`. If someone finishes speaking at t=0.4s into a window, UI waits until t=2.0s **plus** ASR+store. Feels like “delay after person speaks.”

### RC-2 — Persist-before-publish on hot path
```text
try await store.append(segment)
output?.yield(.finalized(segment))
```
Source ledger durability is correct as a product rule, but **blocking the live UI event on a full generation commit** is optional. Same pattern for translations.

### RC-3 — Single serialized recognizer for all sources
`WhisperRecognizer` is one actor/context. Mic (`You`) and `Selected Source` jobs cannot truly run in parallel. Dual-track meetings can queue behind each other.

### RC-4 — Final-only product contract
No volatile hypotheses. Industry “live captions” feel fast because they stream partials; Kineto intentionally waits for finalized segments. Plan deferred “rolling volatile partial hypotheses.”

### RC-5 — Translation serial + store
Acceptable to lag, but:
- `TranslationService` actor = one translate at a time  
- UI translation appears only after store append succeeds  
So translation lag = source lag + queue + MT + store.

### RC-6 — Backpressure drops under load
If ASR falls behind: queue depth 2 then **`recognition-backpressure` gaps** (audio skipped). Shortening chunks without enough throughput **increases** gap risk.

## External research (streaming Whisper)

Sources (2024–2026 practice):
- Live Whisper streaming commonly uses **2–5s** windows; smaller = lower latency, weaker context ([chunk size guides](https://www.saytowords.com/blogs/Whisper-Chunk-Size-Best-Practices/), [realtime streaming guides](https://www.saytowords.com/blogs/Real-Time-Streaming-with-Whisper/)).
- Overlap **0.5–1s** reduces boundary cuts.
- Whisper-Streaming / LocalAgreement class systems target ~**3s** average latency with confirmed partials ([whisper_streaming](https://github.com/ufal/whisper_streaming)).
- Apple Silicon Metal: turbo-class models often **multiples of realtime**; inference alone is rarely multi-second per 2s chunk on M-series ([Apple Silicon Whisper benchmarks](https://www.promptquorum.com/local-llms/apple-silicon-whisper-metal-benchmark)).
- VAD-gated chunking is standard for “update when they stop talking.”

**Implication for Kineto:** Hardware can support snappier finals. Pipeline design is the limiter.

## Target UX (proposed)

| Stream | Target feel | Numeric guardrail (start) |
|---|---|---|
| Original transcript | Appears soon after pause / clause end | p50 **≤ 1.5s**, p95 **≤ 3s** from speech end → first final text |
| Translation | Noticeably later OK | p50 **≤ 3s**, p95 **≤ 6s** after source text visible |
| Under load | Prefer brief lag over silent drops | Minimize `recognition-backpressure` gaps |

## Design options (ranked)

### A — Publish-first, durable-second (highest ROI / KISS)
- Yield finalized segment to UI as soon as ASR returns  
- Persist asynchronously; on persist failure → surface gap/error, do not silently lie  
- Same for translation: show then commit (or commit batched)

**Pros:** Cuts store latency from perceived path; small design change  
**Cons:** Brief window where UI has text not yet sealed (must define crash semantics)  
**Risk:** Must not weaken stop/seal invariants — seal still waits for durable source ledger

### B — Silence / VAD early flush (best “after person speaks”)
- While buffering, detect ≥300–500ms low-energy → `cutJob` residual early  
- Still min chunk floor (e.g. ≥0.8–1.0s) to avoid tiny garbage jobs  
- Keep max chunk cap (2s)

**Pros:** Matches user mental model  
**Cons:** Tuning; noise floors; bilingual energy quirks  
**Risk:** More small jobs → more Whisper calls; watch backpressure

### C — Shorter fixed chunks (1.0–1.5s) ± overlap
- Lower max wait  
- Optional 0.25–0.5s overlap or carry last partial context (`no_context=false` carefully)

**Pros:** Simple knob  
**Cons:** Quality/punctuation; more CPU; without VAD still waits full window after short utterances  
**Note:** Going below ~1s often hurts Whisper quality more than it helps feel

### D — Dual Whisper context (You vs Selected Source)
Only if lag metrics show cross-source queueing.

**Pros:** Parallel tracks  
**Cons:** ~2× model memory pressure with 574MB weights context; thermal  
**YAGNI** until measured

### E — Volatile partial hypotheses
Stream non-final text, replace on final.

**Pros:** Caption-app feel  
**Cons:** New UI contract, no persist of volatile, VoiceOver noise, complexity — **explicitly deferred** in latency plan  
Do only after A–C plateau

### F — Smaller / faster model
Not first lever on M-series turbo+Metal. Revisit only if RTF measured > ~0.5 on worst device.

## Recommended strategy

```text
Phase 0  Instrument: per-stage timings (chunk wait, queue, ASR ms, store ms, translate ms)
         Use lastTranscriptLagSeconds + new histograms in debug builds only

Phase 1  A: UI publish not blocked on store for live path
         Keep seal/stop waiting on durable ledger

Phase 2  B: silence early-flush with min/max chunk bounds
         Keep translation async; optionally UI-before-store for MT too

Phase 3  Measure. If still slow:
         C: 1.5s max chunk + small overlap OR no_context revisit
         D: only if dual-source queue proven

Phase 4  E: volatile partials — product decision, new plan
```

**Do not** only flip `chunkDuration` to 0.5s and call it done — will thrash quality and backpressure.

## Non-goals / constraints

- Raw audio retention stays off  
- Finalized segments remain sole durable source text  
- No cloud ASR  
- Capture must not block on ML (already true)  
- Translation failure must not block source (already true for live tasks; keep it)

## Verification plan

1. Scripted 1-speaker phrases with known end times; log stage ms.  
2. 1:1 call with mic+selected source both active — check cross-source queue.  
3. Fast talker 5+ min — count backpressure gaps before/after.  
4. Translation-on vs off — prove source latency independent.  
5. Crash mid-live after UI-visible pre-persist (if A) — define recovery expectation.

## Unresolved questions

1. Acceptable crash window if UI shows text before generation commit?  
2. Worst supported device RTF for 1s / 1.5s / 2s chunks (unmeasured here)?  
3. Is mic usually on in real meetings (drives dual-context need)?  
4. Product: any volatile text allowed in live UI, or finals only forever?

## References

- Code: `TranscriptCoordinator.swift`, `WhisperRecognizer.swift`, `AppModel.consume`, `TranslationService.swift`, `MeetingPackageStore.append`
- Plan: `plans/260718-1935-latency-translation-summary/plan.md` (deferred volatiles)
- External: whisper streaming chunk practice; whisper_streaming LocalAgreement; Apple Silicon Metal turbo benchmarks (links in body)
