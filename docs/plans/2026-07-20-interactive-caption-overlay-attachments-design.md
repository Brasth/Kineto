---
title: Historical: Interactive Caption Overlay Attachment Design
status: superseded
date: 2026-07-20
---

# Historical: Interactive Caption Overlay Attachment Design

## Superseded decision

This design is retained only as historical context. The user-approved full removal of attachment import supersedes and cancels its meeting-attachment proposal. Kineto does not support attachment import, file drops, attachment storage, attachment quotas, attachment export, or attachment-related release gates.

No implementation or verification work should be derived from the cancelled attachment design.

## Independently valid overlay-positioning context

The attachment proposal was separate from the following overlay-positioning behavior:

- The caption panel is draggable by a dedicated header, not by caption content.
- Persist one normalized position for each display identifier in local preferences.
- Clamp stored coordinates into the current display visible frame whenever the overlay appears or the screen layout changes.
- Maintain accessibility semantics for caption content. Header controls require explicit VoiceOver labels and keyboard access.
- Outside active capture, hide the entire panel immediately. Pause, stop, draining, processing, source loss, deletion, and reset keep it hidden.
