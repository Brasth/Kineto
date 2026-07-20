---
title: Kineto Logo Design
status: approved-for-concept-generation
updated: 2026-07-20
---

# Kineto Logo Design

## Decision

Use one static abstract signal-rail identity as the sole brand geometry. The rail represents connected evidence flow across capture, transcript, translation, and evidence review. It does not represent recording state, privacy state, translation progress, or errors.

## Identity system

1. Symbol-only macOS app icon.
2. Monochrome template mark for menu bar, toolbar, and sidebar.
3. Symbol-plus-Kineto wordmark lockups for onboarding, exports, documentation, and marketing.

The app icon contains no text. Status indicators remain separate native macOS UI using semantic labels, shapes, and colors.

## Visual constraints

- Minimal geometric silhouette with two or three strong nodes/endpoints.
- Dark-first graphite field with a luminous mint accent.
- Black, white, reversed, and alpha-only monochrome variants.
- No microphone, waveform, speech bubble, lock, shield, language flags, EN/VI text, recording dot, gradients, or animation.
- Must remain recognizable without mint or any other color.
- Do not bake macOS rounded corners, masks, shadows, blur, or material effects into source artwork.

## Production constraints

- Maintain one vector master in sRGB.
- Derive all concept and production exports from that master.
- Prefer one validated Xcode 26 Icon Composer `.icon` authority; fall back to `AppIcon.appiconset` if archive/install/distribution behavior is not deterministic.
- Never ship or maintain both icon packaging authorities.
- Concept generation is exploratory; generated raster images are not production source assets.

## Validation gates

- Symbol remains legible at 16, 20, 24, 32, 64, 128, 256, 512, and 1024 px contexts.
- One-color rendering works on light, dark, and semantic macOS material backgrounds.
- No pinholes, tangencies, disappearing nodes, or hairline details.
- Wordmark lockup remains readable at approximately 120 px minimum width.
- Direction does not imply always-on recording, cloud processing, guaranteed privacy, unsupported language coverage, or a system glyph.
- Trademark and asset provenance review passes before production packaging.

## Concept variants

Generate three signal-rail candidates from one geometry family. Compare symbol-only app icon, monochrome template mark, and symbol-plus-wordmark lockup before expanding the asset family.
