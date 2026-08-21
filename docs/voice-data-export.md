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

Unless a directory is supplied, files are written to the app support directory
under `exports/`. Export reads are serialized with local writes and run inside
a database transaction, so session metadata and events form one deterministic
point-in-time snapshot. Writes requested after the export starts remain queued
for the next snapshot.

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

Gemini audio does not pass through Convex. Both clients obtain an authenticated
ephemeral token from the backend and then communicate directly with Gemini Live
over WebSocket. On native, incoming and outgoing Live events are recorded
locally before any server replication is attempted.

The client-facing contracts are explicitly V1:

- Convex action `v1/live/actions:requestLiveToken`;
- HTTP token endpoint `POST /v1/live/token`;
- Convex mutation `v1/voice/sessions:appendEvents`.

For remote WalletBot accounts, the history then follows this flow:

```text
Gemini Live ↔ native app → local Drift outbox
                              ↓ batches of up to 50 events
                  v1/voice/sessions:appendEvents
                              ↓ authenticated mutation
                  Convex voiceSessions + voiceSessionEvents
```

`VoiceSessionRemoteSync` starts as soon as a remote account is attached and
schedules a batch approximately one second after each local write. It sends the
session snapshot and its unsynced events through the authenticated Convex
client. A changed session with no pending events is sent with an empty event
array, so lifecycle-only updates cannot remain stranded in the outbox. Failed
batches remain local and are retried after five seconds; failures never block
the Live conversation or the local export.

The `appendEvents` mutation derives `userId` from the authenticated server
identity and rejects requests whose original account owner does not match that
user. This prevents an in-flight outbox request from crossing account boundaries
during an account switch. It upserts the session by `(userId, sessionId)` and
inserts each event only if `(userId, eventId)` does not already exist, making
retries idempotent. After a successful mutation, the native session is marked
`remoteSynced` only if its `updatedAt` still matches the uploaded snapshot.

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

## Web

The web app writes to the same two tables through the same V1 mutation
(`apps/web/src/lib/voice-history.ts`), so a browser conversation is durable
history and not just React state. The differences follow from the browser having
no local database:

- **The outbox is in memory.** Events queue and flush about a second after the
  last write, with the same 50-event batches and the same five-second retry. A
  tab closed inside that window loses at most the tail; native would still hold
  it in Drift.
- **Only the semantic log is uploaded.** Native additionally persists the raw
  protocol firehose (`server_message`, `client_message`) and one row per PCM
  chunk (`audio_input_chunk`, `audio_output_chunk`) — thousands of rows a minute,
  which SQLite absorbs and a browser round-trip does not. Web records lifecycle,
  transcript deltas, tool calls and results, mute changes, and the server's
  `usage_metadata` / `go_away` / `session_resumption_update` signals. Audio bytes
  never leave either client, so no audio is lost by this; the input/output byte
  accounting is.
- **A dropped socket writes status `ended`, not `suspended`.** Native can resume
  a session from its handle, so a dead socket leaves the session resumable; web
  cannot yet, so the conversation really is over.
- **There is no local export.** `exportSessionJson` and friends are Drift APIs.
  A web user's history lives only in Convex, which is exactly the reduced copy
  described above.

A web session row covers one conversation, not one visit to the assistant page.
The recorder belongs to `apps/web/src/components/layout/voice-provider.tsx`,
which is mounted above the router, so navigating away records
`screen_detached` and keeps the row open — the same boundary native gets from
holding the command in its factory. `endedExplicitly` is therefore true only
when the user actually ended the session; a socket that died writes `ended` with
it false, and signing out ends the row because the provider unmounts with the
account. Until 2026-08-21 the recorder was owned by the `/add` route and every
navigation closed the row with `endedExplicitly: true`, splitting one
conversation into a session per visit.

The `ownerId` a web batch asserts comes from `v1/users/queries:getMyId`, derived
server-side, so the account-boundary check above behaves identically for both
clients.

## Reading the history back

Neither client has one. `v1/voice/sessions.ts` exports only `appendEvents`, and
there is no query that lists sessions or pages their events, so nothing in
either app browses past conversations — native's export APIs are the only way
to get at the data, and they read Drift. A history browser would be a new
product surface, not parity work.
