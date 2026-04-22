---
name: gemini-live-api
description: Implement a Gemini Live API client over raw WebSockets. Use this skill when building real-time audio/video/text streaming with Google's Gemini Live API, handling bidirectional WebSocket sessions, tool calling over live connections, session resumption, or audio PCM streaming to/from Gemini.
---

# Gemini Live API

Build a real-time Gemini Live API client over raw WebSockets.

## When to Use

- Implementing a Gemini Live API WebSocket client
- Streaming audio (mic input / speaker output) to/from Gemini
- Handling tool/function calling inside a live session
- Managing session resumption across reconnections
- Sending real-time video or text alongside audio

## When Not to Use

- Standard Gemini REST/streaming calls (use the regular `generativeLanguage` REST API instead)
- Batch or non-realtime generation

## Key Facts

- **Audio in**: Raw PCM, 16 kHz, 16-bit signed, mono, little-endian; base64-encoded
- **Audio out**: Raw PCM, 24 kHz, 16-bit signed, mono, little-endian; base64-encoded
- First message must be `config`; wait for `setupComplete` before sending anything else
- `realtimeInput` does **not** interrupt model generation; `clientContent` **does**
- Tool call responses must match `id` from the `toolCall` message; do not respond to cancelled IDs

## Workflow

1. Open a WebSocket to the appropriate endpoint (standard API key, or constrained ephemeral token)
2. On `onopen`, send the `config` message (model, modalities, system instruction, tools)
3. Wait for `setupComplete`
4. Stream audio chunks via `realtimeInput.audio` (base64 PCM at 16 kHz)
5. Handle `serverContent` — decode base64 audio parts and play at 24 kHz
6. Handle `toolCall` — execute functions and respond with `toolResponse`; ignore cancelled IDs from `toolCallCancellation`
7. Use `clientContent` only for non-realtime text turns (interrupts the model)

## Reference

Full WebSocket protocol spec (endpoints, message schemas, audio format, tool calling, session resumption):
→ [gemini-live-websocket-api.md](./references/gemini-live-websocket-api.md)
