# Agent Local Voice IO Design

## Context

WUDAX already has a global `WudaXAgent` and an isolated `AgentSessionContext` for each active trip. Voice IO should attach to that active in-trip agent instead of creating a separate assistant. The first implementation uses iOS local system capabilities: speech recognition requests `requiresOnDeviceRecognition`, and speech output uses `AVSpeechSynthesizer`.

## Design

Voice has three user-facing switches:

- Voice input: enables microphone dictation into the current in-session Agent.
- Spoken replies: reads normal Agent answers aloud.
- Proactive voice: lets future proactive AI alerts speak when generated.

The voice state lives on `WudaXAgent` so Settings, the in-session Agent sheet, and future proactive systems share one source of truth. The service layer owns permissions, audio session setup, speech recognition, and speech synthesis. It reports readable status back to SwiftUI.

## UI

The in-session Agent sheet gets a compact voice control strip above the text input: microphone button, spoken replies toggle, proactive voice toggle, and a short status line. Settings gets a voice group for global enable/disable and permission entry. Visual language stays quiet and functional: paper surfaces, SF Symbols, no decorative AI treatment.

## Failure Handling

If speech recognition is denied, unavailable, or cannot run on device, the UI keeps text input available and shows a concrete status. If TTS is off, Agent messages stay text-only. Proactive speaking only fires when both spoken replies and proactive voice are enabled.

## Test Scope

Pure behavior tests cover default preferences, per-role speaking decisions, status copy, and recognized text routing into the Agent. Device microphone behavior is verified by build because simulator/unit tests cannot grant live mic permissions.
