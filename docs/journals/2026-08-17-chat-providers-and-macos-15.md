# 2026-08-17 — Chat providers, Ask UI, macOS 15 floor

Implemented phases 1–7 of the cloud-provider plan.

## What shipped

- `MeetingChatGenerating` seam with Apple Foundation Models behind `#available(macOS 26.0, *)`.
- Official BYOK providers: Grok (`api.x.ai`), OpenAI (`api.openai.com`), Gemini (`generativelanguage.googleapis.com`).
- Isolated `KinetoChatEgressService.xpc` with `network.client` only. The main app entitlement is unchanged.
- Keychain store `com.huynguyen.Kineto.chat-provider`, this-device-only, never written into meeting packages.
- First-send consent sheet plus composer badge that changes with the provider.
- Redesigned Ask conversation: oldest-first, side-by-side source on wide layout, Stop, provider picker.
- Same remote generator can write the summary overview; extractive items still fill the rest.
- Multi-turn: last six grounded answers may enter the prompt as history, not evidence.
- Official OAuth scaffolding only. No Antigravity CLI token path.
- Deployment target 15.0. Apple Speech and on-device Apple Intelligence remain macOS 26 runtime gates.

## Verification still required on a Mac

This sandbox cannot run Xcode. Before merge, run the Kineto scheme, Core tests, and Chat Egress codec tests on Apple Silicon.
