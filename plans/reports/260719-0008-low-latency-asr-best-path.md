# Research Report: Best Path to Lower Live Transcript Latency

- **Date:** 2026-07-19
- **Scope:** How Kineto can get meaningfully lower latency **without** repeating the gap storm
- **Constraint:** Local-only, EN/VI, whisper.cpp already shipped, hold-buffer just restored continuity
- **Mode:** Research + architecture (implementation separate)

## Executive Summary

Kineto already fixed the dumb walls (publish-before-store, silence flush, hold-not-drop). What’s left is the **final-only, non-streaming Whisper contract**.

Industry low-latency Whisper systems do **not** win by `chunkDuration = 0.5` and hope. They win with:

1. **Confirmed streaming partials** (LocalAgreement-class policy)  
2. **Rolling window + overlap** (not isolated 2s `no_context` slices)  
3. **Never drop audio** under load (already fixed)  
4. Optional: **native streaming ASR** (Apple SpeechAnalyzer volatiles) where locale allows  

**Best path for Kineto now:**  
**Phase L1 (safe/fast ROI)** → instrument + dual-track scheduling + lighter store commits  
**Phase L2 (real latency win)** → streaming confirmation engine (partial → stable → final)  
**Phase L3 (optional bakeoff)** → SpeechAnalyzer for EN (and VI if/when available) vs Whisper  

Do **not** re-aggressive silence cuts without hold-buffer (you already learned this).

## Research Methodology

- Sources: prior Kineto latency/gap reports, current coordinator/recognizer code, 3 external research passes (2024–2026)
- Key terms: LocalAgreement, Whisper-Streaming, partial/volatile results, overlap chunking, SpeechAnalyzer, hold-buffer backpressure
- Evaluation criteria: end-to-end lag after speech end, gap rate, EN/VI quality, local-only, memory/thermal, YAGNI

## Current Kineto baseline (after hold-buffer fix)

```text
capture → hold buffer
       → cut on max 2.0s OR (min 0.8s + 0.4s relative silence)
       → queue depth 4 (hold if full; drop only >12s)
       → single Whisper context (no_context=true)
       → UI yield then store
       → translation async
```

| Already done | Still missing for “caption app” feel |
|---|---|
| UI before store | Volatile/partial text |
| Silence early cut | Overlap / rolling context |
| Hold not drop | Confirmed streaming policy |
| Relative pause | Dual recognizer if mic+source |
| | Per-stage latency metrics |

**Hard truth:** Final-only Whisper will always feel ~`silence + inference` behind. Partials are how products feel “live.”

## Key Findings

### 1. Streaming Whisper state of the art

**Whisper-Streaming / LocalAgreement** ([Macháček et al.](https://arxiv.org/html/2307.14743), guides 2025):

- Run decode on a growing buffer repeatedly  
- Emit text only when N consecutive passes agree on a prefix (LocalAgreement-2 common)  
- Trim confirmed audio; keep tail for context  
- Reported live latency often **~2–4s average** on long speech without custom silicon tricks; with turbo+Metal and tight policy, sub-2s finals are plausible  

**Efficient streaming Whisper** ([arXiv 2412.11272](https://ar5iv.labs.arxiv.org/html/2412.11272)):

- Same theme: streaming policy + buffer management, not naive short independent chunks  

**Implication:** Kineto’s `no_context=true` independent chunks is the **batch mindset**. Low latency needs a **streaming mindset**.

### 2. Chunking without gaps

Consensus:

| Pattern | Latency | Continuity | Risk |
|---|---|---|---|
| Independent short chunks + drop queue | Low until overload | **Bad** | Gap storm (you hit this) |
| Independent chunks + hold buffer | Medium | Good | Lag under load |
| Rolling window + overlap + confirm | Low perceived | Good | More CPU, more code |
| Native streaming ASR volatiles | Lowest perceived | Good | Locale/engine split |

**Overlap 0.5–1.0s** is standard to avoid boundary cuts ([streaming guides](https://www.saytowords.com/blogs/Real-Time-Streaming-with-Whisper/)).

### 3. Apple SpeechAnalyzer

WWDC25 SpeechAnalyzer / SpeechTranscriber:

- Designed for **live** STT with **volatile/partial** results  
- On-device, low latency path on Apple Silicon  
- Kineto research already flagged: **VI locale not solid on SpeechTranscriber** at last check; DictationTranscriber path is locale-selected  

So SpeechAnalyzer is a **strong EN latency weapon**, not an automatic full EN/VI replacement yet. Bakeoff required; keep Whisper as VI/fallback.

MacStories/community reports claim Apple path can feel faster than Whisper for interactive use — useful signal, not a ship gate.

### 4. whisper.cpp / Metal / turbo

- `large-v3-turbo` is already the right speed-class model for local live  
- Metal RTF on M-series often multiplies of realtime → inference rarely the only bottleneck  
- Techniques that help: VAD skip silence, overlap, avoid re-decoding confirmed audio, don’t thrash context  
- WhisperKit ANE work shows further decoder latency cuts possible, but that’s a **new runtime**, not a tweak  

### 5. What NOT to do

1. **Re-drop audio** for “lower latency”  
2. **minChunk 0.3s** spam without streaming confirm  
3. **Two permanent ASR engines** without locale matrix  
4. **Promise sub-500ms finals** with final-only Whisper large  
5. Translate on the source critical path  

## Comparative Analysis (Kineto options)

| Option | Perceived lag | Gap risk | EN/VI | Effort | Fit |
|---|---|---|---|---|---|
| A. Tune knobs only | Small | Medium if aggressive | OK | Low | Ceiling hit |
| B. Dual Whisper (You/Source) | Medium if dual-track | Low | OK | Medium | Good L1 |
| C. Batched store commits | Small residual | Low | OK | Medium | Good L1 |
| D. Overlap + light context | Medium | Low | Better continuity | Medium | Good L1.5 |
| E. LocalAgreement streaming | **Large** | Low if hold kept | OK | **High** | **Best L2** |
| F. SpeechAnalyzer volatiles | **Largest** (EN) | Low | VI gap | High | L3 bakeoff |
| G. Smaller model | Medium | Low | Quality hit | Medium | Only if RTF bad |

## Recommended architecture

### Target UX budget

| Event | Target |
|---|---|
| First volatile text after speech starts | ≤ 0.8–1.2s (L2/L3) |
| Stable/final after short pause | ≤ 1.5–2.5s |
| Translation after source visible | ≤ +1–3s OK |
| Backpressure gaps | ≈ 0 except >12s overload |

### Layered design

```text
Capture PCM
  → Hold buffer (never drop casually)          [DONE]
  → StreamingASRController per source
       - rolling window
       - optional overlap
       - emit .volatile (UI only, not stored)
       - emit .stable / .finalized (store)
  → MeetingPackageStore (finals only)          [KEEP]
  → Translation on finalized only              [KEEP]
```

**Invariant preserved:** durable ledger = finals only. Volatiles are UI foam.

### LocalAgreement-2 sketch (L2)

```text
buffer grows with live audio
every step_ms (e.g. 250–500ms) or on silence:
  decode(buffer) → hypothesis H_t
  confirmed = LCP(H_{t-1}, H_t)   # LocalAgreement-2
  if confirmed grows:
     publish volatile/stable delta
     optionally trim audio before confirmed end
on long silence:
     finalize remainder → Segment isFinal=true → store
```

Use **one decode stream per AudioSource** (or dual contexts) so You/Meeting don’t block each other.

## Implementation Strategy

### Phase L0 — Measure (1 session)
- Log: chunk_wait_ms, queue_wait_ms, whisper_ms, store_ms, lag_seconds  
- Classify gaps by reason  
- **Gate:** no more latency work without numbers  

### Phase L1 — Safe wins (do next)
1. **Keep hold-buffer** (non-negotiable)  
2. **Dual Whisper context** if mic+source both on (or global fair scheduler)  
3. **Store batching**: commit multiple segments per generation / coalesce  
4. Mild overlap (e.g. 0.4–0.6s) **or** `no_context=false` carefully with prompt reset rules  
5. Soft UI “catching up…” when hold buffer > N seconds  

Expected: better dual-track lag, fewer store spikes; not magic captions.

### Phase L2 — Real latency (best investment)
1. Introduce `TranscriptEvent.volatile(segment)` (or separate UI channel)  
2. Streaming confirmation controller (LocalAgreement-2)  
3. UI: volatile muted style; final replaces in place (design guidelines already allow)  
4. Persist **only** finals  
5. Tests: no durable volatile; agreement stability; hold under load  

Expected: product feels “live.”

### Phase L3 — Engine bakeoff (only if L2 still short)
1. SpeechAnalyzer path for EN with volatiles  
2. Whisper remains VI + fallback  
3. Single `SpeechRecognizing` surface; locale routing  
4. Kill weaker path if one wins cleanly  

### Explicit non-goals near-term
- Cloud streaming ASR  
- Diarization  
- Sub-300ms guaranteed finals on large-v3-turbo final-only  

## Common Pitfalls

| Pitfall | Result |
|---|---|
| Short chunks + drop queue | Gap spam (lived this) |
| Volatile written to store | Ledger corruption / flicker forever |
| Dual engine without locale matrix | VI regressions |
| Streaming without trim | RAM climb |
| Translate volatiles | Wrong/flickering MT |

## Resources

### Internal
- `plans/reports/260718-2348-live-transcript-latency.md`
- `plans/reports/260718-2356-transcript-gaps-backpressure.md`
- `TranscriptCoordinator.swift`, `WhisperRecognizer.swift`
- Design: volatile-to-final allowed in `docs/design-guidelines.md`

### External
- [Whisper-Streaming paper](https://arxiv.org/html/2307.14743)
- [Efficient Whisper on Streaming Speech](https://ar5iv.labs.arxiv.org/html/2412.11272)
- [Realtime Whisper guide](https://www.saytowords.com/blogs/Real-Time-Streaming-with-Whisper/)
- [WWDC25 SpeechAnalyzer](https://developer.apple.com/videos/play/wwdc2025/277/)
- [ufal/whisper_streaming](https://github.com/ufal/whisper_streaming)

## Next Actions

1. **L0 metrics** in debug build (mandatory)  
2. Choose product: **finals-only forever** vs **volatile UI OK**  
3. If volatile OK → plan L2 LocalAgreement  
4. If dual-track lag in metrics → L1 dual context first  
5. Do not retune silence to 0.25s as the “latency strategy”  

## Unresolved Questions

1. Is volatile/partial UI acceptable for Kineto v1? (design says yes visually)  
2. Worst-device RTF for 1s/2s turbo chunks? (unmeasured)  
3. Is VI on SpeechAnalyzer available on your macOS 26.x build today?  
4. Typical session: mic on or selected-source only?

## Appendix: Decision tree

```text
Need lower latency?
  ├─ Gaps still high? → fix continuity first (hold-buffer) [done]
  ├─ No metrics? → L0 instrument
  ├─ Mic+source both lagging each other? → L1 dual context
  ├─ Want caption-app feel? → L2 streaming partials (best)
  └─ EN-only ultra-low and Apple locale OK? → L3 SpeechAnalyzer bakeoff
```
