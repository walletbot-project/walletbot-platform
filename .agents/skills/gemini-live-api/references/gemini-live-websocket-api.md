# Gemini Live API — WebSocket Specification

Reference for implementing a Gemini Live API client over raw WebSockets.
Compiled from official docs at https://ai.google.dev/api/live and
https://ai.google.dev/gemini-api/docs/live-api/get-started-websocket.

---

## 1. Connection

### Endpoints

| Variant | URL | Auth |
|---|---|---|
| Standard | `wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key={API_KEY}` | API key as query param |
| Constrained (ephemeral token) | `wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContentConstrained?access_token={TOKEN}` | Ephemeral token as query param or `Authorization: Token {TOKEN}` header |

### Ephemeral tokens

Created server-side via `AuthTokenService.CreateToken`. Fields:

| Field | Type | Default | Description |
|---|---|---|---|
| `uses` | integer | 1 | Max number of sessions the token can start |
| `expireTime` | ISO 8601 | now + 30 min | After this time, messages are rejected |
| `newSessionExpireTime` | ISO 8601 | now + 1 min | After this time, new sessions are rejected |
| `liveConnectConstraints` | object | — | Locks the token to a specific model + config (see below) |

When `liveConnectConstraints` is set, the token bakes in the full session config (model, system instruction, tools, generation config). The client's setup message is overridden by the token's constraints.

---

## 2. Message protocol

Every client message is a JSON object with **exactly one** top-level key.
Every server message is a JSON object with **exactly one** top-level key (except `usageMetadata` which may accompany others).

### Client message types

| Top-level key | When | Description |
|---|---|---|
| `config` | First message only | Session setup (model, config, tools, etc.) |
| `clientContent` | After setup | Conversational turns (text). **Interrupts** current model generation. |
| `realtimeInput` | After setup | Streaming audio/video/text. Does **not** interrupt. Can be sent continuously. |
| `toolResponse` | After receiving `toolCall` | Function call results |

### Server message types

| Top-level key | Description |
|---|---|
| `setupComplete` | Empty object. Signals the setup is done; safe to send audio/content. |
| `serverContent` | Model output (audio parts, text parts, interrupted flag, generation complete flag) |
| `toolCall` | Model is requesting function calls |
| `toolCallCancellation` | Model is cancelling previously requested function calls |
| `usageMetadata` | Token usage stats |

---

## 3. Setup (`config`)

Must be the **first** message sent after WebSocket `onopen`. Wait for `setupComplete` before sending anything else.

```json
{
  "config": {
    "model": "models/{model-id}",
    "responseModalities": ["AUDIO"],
    "systemInstruction": {
      "parts": [{ "text": "You are a helpful assistant." }]
    },
    "tools": [
      {
        "functionDeclarations": [
          {
            "name": "myFunction",
            "description": "Does something",
            "parameters": {
              "type": "OBJECT",
              "properties": {
                "arg1": { "type": "STRING", "description": "First argument" }
              },
              "required": ["arg1"]
            }
          }
        ]
      }
    ]
  }
}
```

### Config fields

| Field | Type | Description |
|---|---|---|
| `model` | string | **Required.** Format: `models/{model-id}` |
| `responseModalities` | string[] | `["AUDIO"]`, `["TEXT"]`, or both |
| `systemInstruction` | object | `{ parts: [{ text: "..." }] }` |
| `tools` | object[] | Array of tool groups, each with `functionDeclarations` |
| `temperature` | number | Sampling temperature |
| `topP` | number | Top-p sampling |
| `topK` | number | Top-k sampling |
| `maxOutputTokens` | number | Max tokens per response |
| `speechConfig` | object | Voice/speech configuration |
| `mediaResolution` | string | Resolution for media inputs |
| `realtimeInputConfig` | object | Controls automatic activity detection, turn-taking, etc. |
| `sessionResumption` | object | Enable session resumption across reconnections |
| `contextWindowCompression` | object | Context management settings |
| `inputAudioTranscription` | object | Enable transcription of voice input |
| `outputAudioTranscription` | object | Enable transcription of model audio output |

### Setup complete (server response)

```json
{ "setupComplete": {} }
```

No fields. Just an acknowledgment.

---

## 4. Audio streaming

### Format

| Direction | Encoding | Sample rate | Bit depth | Channels | Byte order |
|---|---|---|---|---|---|
| Input (mic to server) | Raw PCM | 16,000 Hz | 16-bit signed int | 1 (mono) | Little-endian |
| Output (server to speaker) | Raw PCM | 24,000 Hz | 16-bit signed int | 1 (mono) | Little-endian |

### Sending audio (`realtimeInput`)

Audio chunks are base64-encoded and sent continuously. The mimeType **must** include the sample rate.

```json
{
  "realtimeInput": {
    "audio": {
      "data": "<base64-encoded-16bit-PCM>",
      "mimeType": "audio/pcm;rate=16000"
    }
  }
}
```

Additional `realtimeInput` fields:

| Field | Type | Description |
|---|---|---|
| `audio` | Blob | Audio chunk (`{ data, mimeType }`) |
| `text` | string | Real-time text input (alternative to audio) |
| `video` | Blob | Real-time video input |
| `audioStreamEnd` | boolean | Signal that the audio stream has ended (e.g., mic off) |
| `activityStart` | object | Manual activity start marker (when auto-detection is disabled) |
| `activityEnd` | object | Manual activity end marker |

### Receiving audio (`serverContent`)

```json
{
  "serverContent": {
    "modelTurn": {
      "parts": [
        {
          "inlineData": {
            "data": "<base64-encoded-16bit-PCM-24kHz>",
            "mimeType": "audio/pcm;rate=24000"
          }
        }
      ]
    }
  }
}
```

The `parts` array may also contain text parts (`{ "text": "..." }`).

### Other `serverContent` fields

| Field | Type | Description |
|---|---|---|
| `modelTurn` | object | `{ parts: [...] }` — model-generated content |
| `interrupted` | boolean | `true` if client input interrupted the model mid-generation |
| `generationComplete` | boolean | `true` when the model is done generating for this turn |
| `inputTranscription` | object | `{ text: "..." }` — transcription of user's voice input |
| `outputTranscription` | object | `{ text: "..." }` — transcription of model's audio output |

Ordering note: transcriptions are sent independently with **no guaranteed ordering** relative to `serverContent` or each other.

---

## 5. Tool calling (function calling)

### Server sends `toolCall`

```json
{
  "toolCall": {
    "functionCalls": [
      {
        "id": "call_abc123",
        "name": "myFunction",
        "args": {
          "arg1": "value1"
        }
      }
    ]
  }
}
```

Multiple function calls may be batched in a single `toolCall` message.

### Client responds with `toolResponse`

Each `FunctionResponse` is matched to its `FunctionCall` by the `id` field.

```json
{
  "toolResponse": {
    "functionResponses": [
      {
        "id": "call_abc123",
        "name": "myFunction",
        "response": {
          "result": { "key": "value" }
        }
      }
    ]
  }
}
```

### Server cancels tool calls (`toolCallCancellation`)

```json
{
  "toolCallCancellation": {
    "ids": ["call_abc123"]
  }
}
```

When received, the client should:
1. Abort any in-flight execution for those call IDs
2. **Not** send `toolResponse` for cancelled IDs

---

## 6. Client content (text turns)

For sending non-realtime text input (e.g., typed messages). **This interrupts current model generation.**

```json
{
  "clientContent": {
    "turns": [
      {
        "role": "user",
        "parts": [{ "text": "Hello, how are you?" }]
      }
    ],
    "turnComplete": true
  }
}
```

Or shorthand with the SDK:
```
session.sendClientContent({ turns: "Hello", turnComplete: true })
```

---

## 7. Session resumption

Enable in the setup config:

```json
{
  "config": {
    "model": "models/...",
    "sessionResumption": {}
  }
}
```

The server periodically sends `SessionResumptionUpdate` messages with a `newHandle` token. To resume a disconnected session, pass the handle in the next connection's setup:

```json
{
  "config": {
    "model": "models/...",
    "sessionResumption": {
      "handle": "<previously-received-handle>"
    }
  }
}
```

---

## 8. Message ordering rules

1. `config` must be the **first and only first** message
2. Wait for `setupComplete` before sending anything else
3. `realtimeInput` can be sent **continuously** without interruption
4. `clientContent` **interrupts** current model generation
5. Each message must have **exactly one** top-level key
6. Audio/video/text streams within `realtimeInput` are concurrent — ordering across them is **not guaranteed**
7. Transcriptions (`inputTranscription`, `outputTranscription`) have **no guaranteed ordering** relative to content

---

## 9. Models (as of April 2025)

| Model ID | Notes |
|---|---|
| `gemini-3.1-flash-live-preview` | Latest live-capable model |
| `gemini-live-2.5-flash-preview` | Older live-capable model |
| `gemini-2.0-flash-live-preview-04-09` | Legacy |

Check https://ai.google.dev/gemini-api/docs/models for the current list.

---

## 10. Typical message flow

```
Client                                    Server
  |                                         |
  |--- config (setup) -------------------->|
  |                                         |
  |<-------------- setupComplete ----------|
  |                                         |
  |--- realtimeInput (audio chunk) ------->|
  |--- realtimeInput (audio chunk) ------->|
  |--- realtimeInput (audio chunk) ------->|
  |                                         |
  |<-------------- serverContent (audio) --|
  |<-------------- serverContent (audio) --|
  |                                         |
  |--- realtimeInput (audio chunk) ------->|  (user speaks, interrupts model)
  |                                         |
  |<-------------- serverContent           |
  |                    { interrupted: true }|
  |                                         |
  |<-------------- toolCall ---------------|
  |                                         |
  |--- toolResponse ---------------------->|
  |                                         |
  |<-------------- serverContent (audio) --|
  |<-------------- serverContent           |
  |              { generationComplete: true}|
  |                                         |
  |--- close ------------------------------>|
```
