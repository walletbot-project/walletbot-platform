# WhatsApp Business Platform

How Meta's WhatsApp platform is put together, what we set up for Wallet Bot, and
the traps that cost us time. Written to be read start to finish once, then used
as a reference.

Meta's platform is genuinely confusing — not because any single piece is hard,
but because five different objects live in three different dashboards, several
of them can share the same name, and the error messages rarely point at the
thing that is actually wrong. Part 1 exists to fix that.

---

## Part 1 — The mental model

### The five objects

Everything in WhatsApp Business is one of these five things. Most confusion
comes from mixing them up.

| # | Object | What it is | Where it lives |
| --- | --- | --- | --- |
| 1 | **Business Portfolio** | The company. Owns everything else. Formerly "Business Manager". | `business.facebook.com/settings` |
| 2 | **Meta App** | The API client. Holds credentials, permissions, webhooks. | `developers.facebook.com/apps` |
| 3 | **WABA** (WhatsApp Business Account) | The messaging account. Owns phone numbers and message templates. | Both dashboards |
| 4 | **Business Phone Number** | The number that sends and receives. Identified in the API by a **Phone Number ID**, never by the digits. | Inside a WABA |
| 5 | **System User** | A robot account that owns the permanent API token. | `business.facebook.com/settings` |

Relationships:

```
Business Portfolio
├── Meta App              ← the API client (app id)
├── WABA                  ← the messaging account (waba id)
│   ├── Phone Number      ← phone_number_id, the thing you POST to
│   └── Message Templates
├── System User           ← holds the permanent token
└── Facebook Page         ← unrelated to WhatsApp, but shares the name
```

**The critical, non-obvious part:** the App and the WABA are siblings, not
parent and child. Neither contains the other. They are wired together by
*asset assignments* granted to a System User. If that wiring is missing,
everything looks correctly configured and nothing works. This is exactly what
bit us — see Part 10.

### Assets vs roles

Meta separates *what you can access* from *what you can do with it*.

- **Asset** — a thing (an App, a WABA, a Page, an ad account).
- **Assignment** — granting a user or system user access to one asset, at some
  permission level.

A System User with zero assignments is valid, exists, and is completely inert.
Meta will not warn you about this. It surfaces later as an unrelated-looking
error in a different dialog.

### Glossary

| Term | Meaning |
| --- | --- |
| **Cloud API** | Meta-hosted WhatsApp API. What we use. No servers to run. |
| **On-Premises API** | Self-hosted, deprecated. Ignore it. |
| **Graph API** | Meta's general REST API. WhatsApp calls are Graph API calls. |
| **phone_number_id** | Numeric ID of a business phone number. Used in every send call. Not the phone number. |
| **wa_id** | WhatsApp's canonical ID for a *recipient*. Usually the phone number without `+`, but **not always** — see Part 6. |
| **WABA ID** | Numeric ID of the WhatsApp Business Account. |
| **Service window** | The 24-hour period after a user messages you, during which you may send free-form messages. |
| **Template** | A pre-approved message. The only way to message someone outside the service window. |
| **555 number** | A Meta-issued test number, `+1 555-xxx-xxxx`. Free, limited, non-migratable. |
| **Embedded Signup** | OAuth flow letting *your customers* connect *their* WhatsApp. Not needed when messaging from your own number. |

---

## Part 2 — The three dashboards

Meta splits WhatsApp administration across three UIs with overlapping and
inconsistent functionality. Knowing which one owns what saves a lot of clicking.

### 1. App Dashboard — `developers.facebook.com/apps/<app-id>`

The developer-facing view. Owns:

- **App Secret** (Settings → Basic) — needed to verify webhook signatures.
- **Webhook configuration** (WhatsApp → Configuration) — callback URL, verify
  token, and which event fields to subscribe to.
- **API Setup** — the onboarding panel showing phone numbers, a temporary
  token, and the recipient allow-list.
- App Mode: **Development** vs **Live**.

> The "Getting Started / Pruébalo" panel here is unreliable. It renders an
> empty curl sample (`v25.0//messages`, `Bearer `) whenever the app has no WABA
> wired to it, and the "Request test number" button fails silently when the
> portfolio's test-number quota is already spent. Do not use it to diagnose.
> Use the Graph API directly.

### 2. Business Settings — `business.facebook.com/settings`

The administrative view. Owns:

- **System Users** and their tokens.
- **Asset assignments** — the App↔WABA↔System User wiring.
- **WABA management** — phone numbers, display names, verification status.
- **Business verification.**

This is where real problems get fixed. Most WhatsApp setup failures are asset
assignment failures, and this is the only place to see and repair them.

### 3. WhatsApp Manager — `business.facebook.com/wa/manage`

The messaging operations view. Owns:

- Message templates (create, edit, submit for approval, see rejections).
- Phone number quality rating and messaging limits.
- Conversation and cost analytics.

### 4. Graph API Explorer — `developers.facebook.com/tools/explorer`

Not a dashboard, but the fastest way to answer "what does Meta actually think
is configured?" — which is frequently different from what the UI shows.

---

## Part 3 — Access tokens

Four kinds exist. Picking the wrong one wastes hours.

| Token | Lifetime | Use |
| --- | --- | --- |
| **Temporary token** (API Setup panel) | 24 hours | Throwaway manual testing only. |
| **User access token** | ~2 hours | Never for servers. Dies with the session. |
| **System User token** | 60 days or **never** | ✅ **What production uses.** |
| **App access token** | Permanent | App-level admin ops. Cannot send messages. |

**Always use a System User token with expiry "Nunca" (Never) for a backend.**

Required permissions for a messaging bot:

- `whatsapp_business_messaging` — send and receive messages.
- `whatsapp_business_management` — manage numbers, templates, and subscriptions.

A System User token only works if that system user has been assigned **both**
the App (with *Administrar app* / Manage app) **and** the WABA (with full
control). Missing either produces "No hay permisos disponibles" at token
generation time — an error that names neither the App nor the assignment.

---

## Part 4 — Wallet Bot's setup

Established 2026-08-16.

### Identifiers

| Item | Value |
| --- | --- |
| Business Portfolio | `2124859685088995` ("Wallet Bot") |
| Meta App | `2576911202751949` ("Wallet Bot") |
| WABA | `1042220975475427` ("Wallet Bot") — `account_review_status: APPROVED` |
| Phone Number ID | `1290033147525120` |
| Phone number | `+1 555-440-3681` (Meta **test** number) |
| System User | `walletbot-api` (`61593205330048`), role Admin, token never expires |
| Second WABA | `1098896139326514` ("Test WhatsApp Business Account") — number `+1 555-668-8660`, unverified, **unusable** |

Both numbers are `+1 555` test numbers, which means **the portfolio's test
number quota (two) is fully spent.** That is why "Solicitar número de prueba"
does nothing — there is nothing left to grant.

### Convex environment variables

Set on **both** `dev:proficient-finch-671` and prod:

| Variable | Value | Consumer |
| --- | --- | --- |
| `WHATSAPP_ACCESS_TOKEN` | System user token | Chat SDK (auto-detected) |
| `WHATSAPP_TOKEN` | Same token | Our own code |
| `WHATSAPP_PHONE_NUMBER_ID` | `1290033147525120` | Both |
| `WHATSAPP_WABA_ID` | `1042220975475427` | Our own code |
| `WHATSAPP_APP_ID` | `2576911202751949` | Our own code |
| `WHATSAPP_VERIFY_TOKEN` | 32-byte random hex | Webhook handshake |
| `WHATSAPP_GRAPH_VERSION` | `v23.0` | Our own code |
| `WHATSAPP_APP_SECRET` | ⚠️ **NOT SET** | Webhook signature verification |

`WHATSAPP_ACCESS_TOKEN` and `WHATSAPP_TOKEN` deliberately hold the same value:
Chat SDK auto-detects the former, our own helpers can use either. If you rotate
the token, **rotate both**.

> ⚠️ **`WHATSAPP_APP_SECRET` is still missing and is a blocker for receiving
> messages.** Get it from App Dashboard → Settings → Basic → App Secret →
> "Mostrar" (requires re-entering your Facebook password, which is why it could
> not be automated). Then:
>
> ```bash
> cd packages/backend
> npx convex env set        WHATSAPP_APP_SECRET '<secret>'
> npx convex env set --prod WHATSAPP_APP_SECRET '<secret>'
> ```
>
> Without it you cannot verify `X-Hub-Signature-256`, which means anyone who
> learns the webhook URL can inject fabricated messages straight into the AI
> agent. Do not ship the webhook without it.

### Webhook URL

```
https://proficient-finch-671.convex.site/v1/whatsapp/webhook
```

The `/v1` prefix follows `docs/client-api-versioning.md`. Prod uses its own
`.convex.site` host — configure whichever one that deployment should receive.
**Meta allows exactly one callback URL per app**, so dev and prod cannot both
be subscribed to the same app at once. See Part 11.

---

## Part 5 — Setup runbook

To repeat this from scratch, or to onboard a real production number.

### 1. Create the System User

`business.facebook.com/settings` → Usuarios → Usuarios del sistema → Agregar.

- Name: alphanumeric with hyphens; some characters are silently rejected.
- Role: **Admin**.

### 2. Assign the App

Cuentas → **Apps** → select the app → **Asignar personas** → pick the system
user → **Administrar app** (full access) → Asignar.

> Do not use the system user's own "Asignar activos" dialog for this. Its asset
> type selector defaults to *Páginas de Facebook*, and if your Page shares a
> name with your WABA you will silently assign the wrong object. Assign from
> the asset's own page instead — the dialog is then unambiguous.

### 3. Assign the WABA

Cuentas → **Cuentas de WhatsApp** → select the WABA → **Asignar personas** →
pick the system user → **Todo** (full control) → Asignar.

Verify both landed before continuing:

```bash
# should list two assets, not one, and neither should be a Facebook Page
open "https://business.facebook.com/latest/settings/system_users?business_id=<biz>&selected_user_id=<sysuser>"
```

### 4. Generate the token

System user → **Generar token** → select the app → caducidad **Nunca** →
check `whatsapp_business_messaging` and `whatsapp_business_management` →
Generar token. Copy it immediately; it is shown once.

If the permissions list is empty and says *"No hay permisos disponibles"*,
step 2 did not take. Go back and fix the app assignment.

### 5. Verify from the API

```bash
curl -s "https://graph.facebook.com/v23.0/<WABA_ID>/phone_numbers\
?fields=id,display_phone_number,verified_name,code_verification_status,status,platform_type" \
  -H "Authorization: Bearer $TOKEN"
```

You want `status: CONNECTED`, `code_verification_status: VERIFIED`, and
`platform_type: CLOUD_API`. The `id` is your `phone_number_id`.

### 6. Send a test message

```bash
curl -s -X POST "https://graph.facebook.com/v23.0/<PHONE_NUMBER_ID>/messages" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"messaging_product":"whatsapp","to":"<E164_NO_PLUS>","type":"text",
       "text":{"body":"test"}}'
```

A `messages[0].id` (a `wamid.…`) means **queued, not delivered.** Delivery is
only observable through status webhooks.

---

## Part 6 — Phone numbers and the `wa_id` trap

This section is the one most likely to cause silent data corruption. Read it
before writing any code that stores a contact.

### The rule

> **Never construct, normalize, or guess a WhatsApp ID. Store exactly the
> `wa_id` Meta returns, and match on that.**

### Why

WhatsApp IDs are *not* simply "E.164 without the plus". For several countries
the WhatsApp ID differs from the dialable number, because WhatsApp froze IDs
before or after national numbering changes.

| Country | Dial format | WhatsApp ID | Note |
| --- | --- | --- | --- |
| 🇦🇷 Argentina (+54) | `+54 11 2589-1334` | `5491125891334` | Mobile IDs insert **`9`** after `54`. The local `15` trunk prefix is dropped. |
| 🇲🇽 Mexico (+52) | `+52 55 1234-5678` | `5215512345678` *or* `525512345678` | Historically required a **`1`** after `52`. WhatsApp dropped the requirement around 2020, so **both forms exist in the wild** depending on when the account registered. |
| 🇧🇷 Brazil (+55) | `+55 11 98765-4321` | `5511987654321` *or* `551187654321` | ANATEL added a 9th mobile digit in 2010+. Numbers registered on WhatsApp before that keep 8-digit IDs. Mostly affects area codes **outside** 11–19, 21, 22, 24, 27, 28. |

We observed this directly during setup:

```
input:  541125891334      (12 digits, no 9)
wa_id:  5491125891334     (13 digits, 9 inserted by Meta)
```

Meta accepted the message and normalized the number itself. **The value you
sent is not the value that identifies the user.**

### Consequences if you ignore this

1. **Duplicate contacts.** Outbound creates `541125891334`, the inbound webhook
   arrives as `5491125891334`, and you now have two records for one human.
2. **Failed lookups.** An inbound message can't be matched to its conversation,
   so the AI agent loses all context and answers as a stranger.
3. **Broken idempotency.** Dedupe keyed on your normalization silently stops
   deduping.
4. **Test-number allow-list mismatches.** In development mode the allow-list
   matches on the form *you registered*, which may not be the `wa_id`. This
   produces error `131030` for a number that is demonstrably on the list.

### What to implement

- Store two fields: `waId` (canonical, from Meta — the **only** match key) and
  `phoneE164` (what the human typed, for display).
- Populate `waId` from `contacts[0].wa_id` on send responses, and from
  `messages[0].from` / `contacts[0].wa_id` on inbound webhooks.
- Index on `waId`.
- If you must accept typed input, treat your normalization as a *lookup hint*
  only, never as an identity. Resolve it against Meta and persist the answer.
- Never `assert(sent === received)` on phone numbers.

Beyond these three countries, the safe assumption is that **any** country may
diverge. The rule above costs nothing and is immune to the whole class.

---

## Part 7 — Messaging rules

### The 24-hour service window

When a user messages you, a 24-hour window opens. Inside it you may send
free-form messages of any type. Outside it, **only pre-approved templates**.
The documented error for attempting free-form outside the window is:

```
131047 — Re-engagement message
```

> ⚠️ **Verified 2026-08-16: you may not get that error at all.**
>
> We sent three free-form messages to a number with no open window. All three
> returned `200` with a valid `wamid` and **no error field whatsoever**. All
> three were silently discarded — never delivered, and never surfaced in
> analytics. The moment the recipient messaged the business number first, the
> byte-identical API call arrived instantly.
>
> **Consequence: the POST response tells you nothing about deliverability.** A
> `wamid` means "accepted into the queue", not "will be delivered", and not even
> "passed the window check". Treat every send as unverified until a status
> webhook says `delivered`. This is the single most misleading behavior of the
> platform, and it is why status webhooks are a hard requirement rather than a
> nice-to-have.

For an AI agent this is the defining constraint restated: **the user must speak
first, every time the window lapses.** There is no way to open a conversation
with free-form text, and failing to do so is silent.

For an AI agent this is the defining constraint: the agent can converse freely
while the user is engaged, but it **cannot** initiate or resume a conversation
without an approved template. Any proactive notification (a budget alert, a
weekly summary) needs a template written and approved in advance.

Wallet Bot currently has **zero templates** (`message_templates` returns `[]`),
so today the bot can only reply inside an open window.

### Test numbers vs production

| | 555 test number | Real number |
| --- | --- | --- |
| Cost | Free | Per-conversation pricing |
| Recipients | **Allow-list only, max 5** | Anyone |
| Business verification | Not required | Required |
| Migratable | ❌ Never | ✅ |
| Quota | 2 per portfolio | 2 → 20+ after verification |

The allow-list is managed in App Dashboard → WhatsApp → API Setup → "To" →
Manage phone number list. Sending to anything else returns `131030`.

### Common errors

| Code | Meaning | Fix |
| --- | --- | --- |
| `131030` | Recipient not in allow-list | Add to allow-list, or go to production |
| `131047` | Outside 24h window | Send an approved template |
| `131026` | Recipient can't receive (no WhatsApp / wrong ID) | Check `wa_id` — often the Part 6 bug |
| `132000` | Template param count mismatch | Match the approved template exactly |
| `133010` | Number not registered | Call the `register` endpoint |
| `100` | Invalid parameter | Usually a wrong `phone_number_id` |
| `190` | Token expired/invalid | Rotate; a system user token set to "Never" shouldn't hit this |

### Quality rating

Meta rates each number Green / Yellow / Red based on user blocks and reports.
A Red rating drops your messaging tier and can suspend the number. An AI agent
that messages too eagerly, or misreads intent and spams, is a direct threat to
the number's health — this is a product constraint, not just a technical one.

---

## Part 8 — Receiving messages

### Two-step handshake

**Step 1 — Verification (`GET`).** When you save the callback URL, Meta sends:

```
GET /v1/whatsapp/webhook?hub.mode=subscribe
                        &hub.verify_token=<your WHATSAPP_VERIFY_TOKEN>
                        &hub.challenge=<random>
```

Compare `hub.verify_token` against `WHATSAPP_VERIFY_TOKEN` and echo
`hub.challenge` back as plain text with `200`. Anything else and Meta refuses
to save the URL.

**Step 2 — Events (`POST`).** Every event POSTs a JSON envelope carrying
`X-Hub-Signature-256: sha256=<hex>`.

### Signature verification is mandatory

The signature is `HMAC-SHA256(raw_body, WHATSAPP_APP_SECRET)`. Three rules:

1. Verify against the **raw body**, before any JSON parsing. Re-serializing
   changes the bytes and the HMAC will never match.
2. Use a **timing-safe** comparison.
3. Reject with `403` on mismatch.

Per `CLAUDE.md` — *THE CLIENT IS NOT TRUSTABLE* — an unverified webhook is an
unauthenticated public endpoint that writes straight into the AI agent's
context. Treat it as a security boundary.

### Subscribing the app

Configuring the callback URL is not enough; the app must also be subscribed to
the WABA:

```bash
curl -X POST "https://graph.facebook.com/v23.0/<WABA_ID>/subscribed_apps" \
  -H "Authorization: Bearer $TOKEN"

# verify
curl -s "https://graph.facebook.com/v23.0/<WABA_ID>/subscribed_apps" \
  -H "Authorization: Bearer $TOKEN"
```

**Currently `subscribed_apps` returns `[]`** — nothing is subscribed, so no
inbound messages will arrive yet.

### Delivery semantics

- Meta retries failed deliveries with backoff. **Handlers must be idempotent** —
  dedupe on `messages[0].id` (the `wamid`).
- Respond `200` fast. Do the real work asynchronously (a Convex scheduled
  function or workflow); slow handlers get retried and duplicated.
- Events arrive **out of order**. A `read` status can precede its `delivered`.
- Subscribe only to the fields you need. `messages` covers inbound plus status
  updates.

---

## Part 9 — Chat SDK by Vercel

[Chat SDK](https://chat-sdk.dev) (`chat`, v4.38.0) is a TypeScript toolkit for
multi-platform bots, with an official WhatsApp adapter. Worth evaluating
because it removes most of Part 8's boilerplate.

### Packages

```bash
pnpm add chat @chat-adapter/whatsapp
pnpm add @chat-adapter/state-redis   # or state-pg / state-ioredis / state-memory
```

### Environment variables

The adapter auto-detects exactly these four names:

| Variable | Notes |
| --- | --- |
| `WHATSAPP_ACCESS_TOKEN` | ✅ set — **note the name**, not `WHATSAPP_TOKEN` |
| `WHATSAPP_APP_SECRET` | ❌ **not set** — the adapter *throws at construction* without it |
| `WHATSAPP_PHONE_NUMBER_ID` | ✅ set |
| `WHATSAPP_VERIFY_TOKEN` | ✅ set |

All four can also be passed explicitly to `createWhatsAppAdapter({...})`.
`apiVersion` defaults to **`v21.0`** — the SDK does *not* read
`WHATSAPP_GRAPH_VERSION`, so pass `apiVersion: 'v23.0'` if you want parity with
our own helpers.

### Shape

```typescript
import { Chat } from 'chat'
import { createWhatsAppAdapter } from '@chat-adapter/whatsapp'
import { createRedisState } from '@chat-adapter/state-redis'

const bot = new Chat({
    userName: 'walletbot',
    adapters: { whatsapp: createWhatsAppAdapter({ apiVersion: 'v23.0' }) },
    state: createRedisState(),
    dedupeTtlMs: 600_000,
})

bot.onDirectMessage(async (thread, message) => {
    await thread.subscribe()
    const result = await agent.stream({ prompt: message.text })
    await thread.post(result.fullStream)   // streams, with edit-based updates
})
```

Webhook wiring is a `Request → Response` function, which matches both Next.js
route handlers and Convex `httpAction`:

```typescript
export async function GET(request: Request)  { return bot.webhooks.whatsapp(request) }
export async function POST(request: Request) { return bot.webhooks.whatsapp(request) }
```

### What it gives us

- Webhook signature verification and the `GET` handshake, handled.
- Normalized thread/message model, so the same agent code could later serve
  Telegram, Slack, or Discord.
- Streaming AI responses via post-and-edit, with `fullStream` support from the
  AI SDK.
- Message dedupe and distributed locking (important — Meta retries).
- Interactive cards and buttons via JSX.
- Automatic chunking at WhatsApp's 4096-char message limit (1024 for captions).

### What it costs us — read before adopting

1. **It requires an external state store.** A state adapter is mandatory:
   Redis, ioredis, Postgres, or Memory. There is **no Convex state adapter**.
   Memory state does not survive a serverless cold start, so a real deployment
   means standing up Redis or Postgres purely for the bot — a new dependency
   and a new failure mode for a stack that currently has neither.
2. **It assumes a long-lived Node HTTP server.** Convex's default runtime is not
   Node; it would need `'use node'`, and the `'use node'` rules in `CLAUDE.md`
   (actions only, import-chain restrictions) apply to everything it touches.
3. **It owns conversation state.** Threads, subscriptions, and locks live in
   *its* store, not in Convex. That splits the source of truth for a
   conversation across two systems.
4. **Adapter limitations:** replies are outbound-only (inbound quote-replies
   don't surface what was quoted); one media per message; the typing indicator
   only works after the bot has received a message.

### Recommendation

For a WhatsApp-only agent living in Convex, **implementing the webhook directly
is probably the smaller system**: it is roughly one `httpAction` for the
handshake plus HMAC verification, one send helper, and a scheduled function for
the agent turn — with all state already in Convex, where the rest of Wallet Bot
lives.

Chat SDK earns its dependencies when you want **more than one platform**. If
Telegram or Slack is on the roadmap, adopt it early rather than porting a
hand-rolled WhatsApp integration later. Worth an explicit decision before
writing the handler.

---

## Part 10 — What went wrong, and why

The full debugging story, because the failure mode is non-obvious and will
recur.

### Symptoms

- "Solicitar número de prueba" did nothing — no spinner, no error.
- The onboarding panel said *"No hay números de teléfono disponibles para esta
  app"*, and rendered a broken curl sample: `v25.0//messages` with an empty
  phone-number-ID and an empty `Bearer`.
- A WABA with a `Conectado` number existed and was visibly unusable.
- Token generation failed with *"No hay permisos disponibles"*.

### Root causes — three independent problems

**1. The test-number quota was already spent.** A portfolio may claim **two**
`+1 555` numbers. Both were taken (`+1 555-668-8660` and `+1 555-440-3681`).
The button had nothing to grant and failed silently.

**2. The app was never wired to a WABA.** The onboarding panel reads numbers
reachable *by the app*, and nothing connected them.

**3. The name collision.** The Business Portfolio, the Facebook Page, the Meta
App, and the WABA were **all named "Wallet Bot"**. The system user's "Asignar
activos" dialog defaults to the *Páginas de Facebook* asset type, so an
assignment that looked correct actually granted the **Facebook Page** — an
object with no relationship to WhatsApp whatsoever. The result: a system user
with exactly one asset, the wrong one, and a token wizard reporting
"No hay permisos disponibles" without ever mentioning apps or assignments.

### The fix

Assign from each asset's own settings page (Cuentas → Apps, Cuentas → Cuentas
de WhatsApp) rather than from the system user's asset dialog. The asset is then
unambiguous.

### Learnings

- **Diagnose with the Graph API, not the dashboard.** Three API calls
  established ground truth in seconds after the UI had misled us for a while.
- **Meta's errors name the symptom, not the cause.** "No permissions available"
  meant "an unrelated asset assignment silently went to the wrong object".
- **Do not reuse one name across objects.** Name things
  `walletbot-app`, `walletbot-waba`, `walletbot-page`. This single habit would
  have prevented the whole incident.
- **"Accepted" ≠ "delivered", and Meta will not tell you.** Confirmed the hard
  way: three sends returned `200` + a valid `wamid` with no error and were all
  silently dropped, because no 24-hour window was open. The same call succeeded
  instantly once the user messaged first. Never infer delivery from a send
  response; only a status webhook proves it.
- **Verify assignments after making them.** The UI shows stale state; reload
  and re-read before concluding a step worked.

---

## Part 11 — Open items and warnings

### Verified working

**Outbound messaging is confirmed end to end** (2026-08-16). A message sent via
`POST /1290033147525120/messages` with the `walletbot-api` system user token was
received on a real handset, inside an open 24-hour window. The credentials, the
asset wiring, and the number are all good.

### Blockers before receiving messages

1. **`WHATSAPP_APP_SECRET` is not set.** Required by any webhook
   implementation, hand-rolled or Chat SDK. See Part 4.
2. **No app subscribed to the WABA.** `subscribed_apps` is `[]` (Part 8).
3. **No webhook handler exists.** Nothing is implemented at
   `/v1/whatsapp/webhook` yet.

### Warnings

- **One callback URL per app.** Dev and prod cannot both be subscribed
  simultaneously. Either use a second Meta app for dev, or accept that only one
  environment receives messages at a time. Decide this before wiring prod.
- **The token never expires.** Convenient, and permanent exposure if leaked. It
  is in Convex env vars on both deployments and in `~/.wa_token` locally.
  Rotate via System User → **Revocar tokens**; remember to update **both**
  `WHATSAPP_ACCESS_TOKEN` and `WHATSAPP_TOKEN` on **both** deployments.
- **Dev and prod share one phone number.** A test message from dev is
  indistinguishable from prod at the recipient. Use a separate number per
  environment once on production numbers.
- **Business verification is incomplete** (`No verificado`). Fine for test
  numbers; required before a real number goes live.
- **The test number cannot become a production number.** 555 numbers are not
  migratable. Production means adding your own number, which needs verification
  and a payment method.
- **`account_review_status: APPROVED`** applies to the WABA, not the business.
  They are separate reviews.

### Suggested next steps

1. Set `WHATSAPP_APP_SECRET` (unblocks everything else).
2. Decide Chat SDK vs a hand-rolled Convex handler (Part 9).
3. Implement `GET`/`POST /v1/whatsapp/webhook` with signature verification.
4. `POST /<WABA_ID>/subscribed_apps`.
5. Add the contact model with `waId` as the match key (Part 6).
6. Add your own number to the recipient allow-list for testing.
7. Create at least one approved template if the agent should ever initiate.
8. Consider a Convex workflow for the agent turn, per `CLAUDE.md` — inbound
   handling must ack fast and process asynchronously.

---

## Sources

- [Get Started — WhatsApp Cloud API](https://developers.facebook.com/docs/whatsapp/cloud-api/get-started/)
- [Business phone numbers](https://developers.facebook.com/documentation/business-messaging/whatsapp/business-phone-numbers/phone-numbers)
- [WhatsApp Business Accounts](https://developers.facebook.com/documentation/business-messaging/whatsapp/whatsapp-business-accounts)
- [Embedded Signup overview](https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/overview/) — the "two 555 numbers" limit
- [Webhooks overview](https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/overview)
- [Subscribed Apps API](https://developers.facebook.com/documentation/business-messaging/whatsapp/reference/whatsapp-business-account/subscribed-apps-api)
- [Chat SDK — WhatsApp adapter](https://chat-sdk.dev/adapters/official/whatsapp)
- Brazil/Mexico/Argentina `wa_id` divergence: [Gupshup](https://support.gupshup.io/hc/en-us/articles/4413210201625-Why-do-we-see-differences-between-the-actual-dial-numbers-and-the-one-registered-on-WhatsApp-for-region-Brazil-Mexico), [Chatwoot](https://www.chatwoot.com/hc/user-guide/articles/1758697086-inconsistencies-for-whats_app-numbers-in-brazil-mexico-and-argentina)
