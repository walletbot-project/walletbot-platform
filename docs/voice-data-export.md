# Voice and chat data export

WalletBot exports voice and chat history as self-contained, versioned JSON.
There is currently no export UI; callers use `VoiceSessionRepository`.

## Export entry points

```dart
// JSON for one session.
final json = await repository.exportSessionJson(sessionId);

// File for one session: voice-session-<sessionId>.json
final file = await repository.exportSessionFile(sessionId);

// JSON or file containing every locally retained session.
final historyJson = await repository.exportAllSessionsJson();
final historyFile = await repository.exportAllSessionsFile();
```

Unless a directory is supplied, files are written to the app support
directory under `exports/`. Before reading, the repository flushes pending
local writes so the artifact includes all events recorded up to that point.

## Contents

A session export uses format `walletbot.voice-session`, version `1`. A full
history export uses `walletbot.voice-history`, version `1`.

Each session includes its ID, Gemini model, lifecycle status, start/update/end
timestamps, whether it ended explicitly, resumption metadata, and remote-sync
state. Events are ordered by their monotonic `sequence` and include:

- event ID and UTC timestamp;
- event type, direction, and modality;
- semantic payload and the available raw protocol message;
- remote-sync state;
- PCM input/output audio when present.

Audio is embedded losslessly as base64 with its MIME type and original byte
length:

```json
{
  "binary": {
    "mimeType": "audio/pcm;rate=24000",
    "byteLength": 4800,
    "encoding": "base64",
    "data": "..."
  }
}
```

The complete export can therefore be large and sensitive: it may contain user
speech, agent audio, message text, tool arguments/results, raw protocol data,
and Gemini resumption handles. It should be handled as private account data.

The export is generated from the local Drift database. Remote Convex storage
contains the semantic/protocol history and audio metadata, but not PCM bytes;
this does not affect the completeness of the local export.

## Communication and server-side storage

Gemini audio does not pass through Convex. For remote accounts, the native app
obtains an authenticated ephemeral token from the backend and then communicates
directly with Gemini Live over WebSocket. Incoming and outgoing Live events are
recorded locally before any server replication is attempted.

For remote WalletBot accounts, the history then follows this flow:

```text
Gemini Live ↔ native app → local Drift outbox
                              ↓ batches of up to 50 events
                    voice/sessions:appendEvents
                              ↓ authenticated mutation
                  Convex voiceSessions + voiceSessionEvents
```

`VoiceSessionRemoteSync` schedules a batch approximately one second after a
local write. It sends the session snapshot and its unsynced events through the
authenticated Convex client. Failed batches remain in the local outbox and are
retried after five seconds; failures never block the Live conversation or the
local export.

The `appendEvents` mutation derives `userId` from the authenticated server
identity. It upserts the session by `(userId, sessionId)` and inserts each event
only if `(userId, eventId)` does not already exist, making retries idempotent.
After a successful mutation, the native rows are marked `remoteSynced`.

Convex stores data in two isolated tables:

- `voiceSessions`: ownership, model, lifecycle status, timestamps, and explicit
  end state;
- `voiceSessionEvents`: sequence, timestamp, type, direction, modality,
  semantic/raw JSON, and optional audio MIME type and byte length.

Before upload, `handle` and `newHandle` fields are redacted from raw protocol
JSON. PCM bytes and resumption handles remain only on the device. Local
WalletBot accounts do not upload voice history at all.

There is currently no server-side export endpoint. The implemented export is
produced from Drift because it is the authoritative and most complete copy,
including PCM audio. Convex provides durable remote history for remote accounts
but intentionally contains only the reduced audio metadata described above.
