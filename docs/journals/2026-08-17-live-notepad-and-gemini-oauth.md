# 2026-08-17 — Live notepad and official Gemini OAuth foundation

Granola-style hybrid notes, plus the official Gemini OAuth pieces that do not require a vendor client ID for Grok or OpenAI.

## What shipped

- Live notepad during capture. Notes persist into the encrypted package (`MeetingScratchpad`, max 20k).
- After stop, **Enhance notes** asks the connected generator for transcript fills only. Operator paragraphs stay verbatim and in order.
- Fills interleave via `afterParagraph` (0 = before the first note). Ungrounded fills are dropped. Unstructured answers with valid citations become one trailing fill.
- Recap is a derived record (`MeetingRecapRecord`) with `.user` / `.filled` blocks. Filled blocks must carry extractive evidence.
- Package snapshot **v4**: `scratchpad` / `recap` decode with `decodeIfPresent` so older packages still open. Manifest stores `scratchpadRevision`, `hasRecap`, `recapBlockIDs`.
- Review workspace: Notes is first on regular width; compact still has Transcript | Notes | Summary | Ask. Live capture has Transcript | Notes.
- Credential Keychain envelope: `ChatProviderSecret` is `.apiKey` or `.oauth`. Legacy raw API-key items still decode.
- Official Gemini OAuth types: PKCE S256, Google auth/token endpoints, iOS-style redirect for `*.apps.googleusercontent.com`. Chat Egress codec allows `oauth2.googleapis.com` and can send Gemini `Authorization: Bearer` when `authKind` is `oauth`.
- Grok and OpenAI stay console API keys. No unofficial SuperGrok / ChatGPT / Antigravity subscription OAuth.

## Not in this PR

Sign-in with Google is not wired through Settings yet. Token exchange / refresh still needs an XPC method, `ASWebAuthenticationSession`, a URL scheme, and AppModel refresh-before-send. Existing API-key Gemini / Grok / OpenAI paths are unchanged.

## Verification still required on a Mac

This sandbox cannot run Xcode. Before merge, run the Kineto scheme, Core recap/package tests, and Chat Egress codec tests on Apple Silicon.
