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
| **Phone Number ID (live)** | **`1324548857400869`** |
| **Phone number (live)** | **`+54 9 11 2399-1858`** — self-supplied, `CONNECTED`, `CLOUD_API` |
| Phone Number ID (test) | `1290033147525120` — `+1 555-440-3681`, inbound-only, cannot send (see Part 7) |
| System User | `walletbot-api` (`61593205330048`), role Admin, token never expires |
| Two-step PIN | set during registration; stored locally at `~/.wa_pin` |
| Second WABA | `1098896139326514` ("Test WhatsApp Business Account") — `+1 555-668-8660`, `PENDING`/`NOT_VERIFIED`, **unusable**, and at its phone-number limit |

The portfolio's `+1 555` test-number quota (two) is fully spent, which is why
"Solicitar número de prueba" does nothing — there is nothing left to grant. That
stopped mattering once a real number was added: **`+54 9 11 2399-1858` is the
number that works.** The 555 number is kept because it still receives inbound
and is a useful second conversation for testing; it just cannot reply.

Adding a real number is what finally removed three limits at once: the ≤5
recipient allow-list, the `131037` display-name wall, and the non-migratable
dead end of a 555 number.

### Convex environment variables

Set on **both** `dev:proficient-finch-671` and prod:

| Variable | Value | Consumer |
| --- | --- | --- |
| `WHATSAPP_ACCESS_TOKEN` | System user token | Chat SDK (auto-detected) |
| `WHATSAPP_TOKEN` | Same token | Our own code |
| `WHATSAPP_PHONE_NUMBER_ID` | `1324548857400869` | Both |
| `WHATSAPP_WABA_ID` | `1042220975475427` | Our own code |
| `WHATSAPP_APP_ID` | `2576911202751949` | Our own code |
| `WHATSAPP_VERIFY_TOKEN` | 32-byte random hex | Webhook handshake |
| `WHATSAPP_GRAPH_VERSION` | `v23.0` | Our own code |
| `WHATSAPP_APP_SECRET` | 32-char app secret | Webhook signature verification (R-020) |
| `WHATSAPP_BUSINESS_NUMBER` | `5491123991858` | `wa.me` deep link in the account-linking flow |

All nine are set on both `dev:proficient-finch-671` and prod.

`WHATSAPP_BUSINESS_NUMBER` is the **dialable** number without the `+`, not the
`wa_id` — `wa.me` wants what a human would dial. For this number the two happen
to coincide; for many Argentine numbers they do not, so do not derive one from
the other (Part 6). It is the only optional variable here: with it unset,
`createLinkCode` still returns a code and simply omits the deep link, and
`linkStatus` reports `available: false` so a client can hide the entry point.

`WHATSAPP_ACCESS_TOKEN` and `WHATSAPP_TOKEN` deliberately hold the same value:
Chat SDK auto-detects the former (see Part 9), our own helpers read the former.
If you rotate the token, **rotate both, on both deployments** — see R-023.

`WHATSAPP_APP_SECRET` comes from App Dashboard → Settings → Basic → App Secret →
"Mostrar", which requires re-entering your Facebook password and is therefore the
one value that cannot be scripted. It is a **deploy prerequisite**: the webhook
fails closed without it (`500`, nothing enqueued), because without it there is no
way to tell Meta from an attacker and the payload feeds straight into the agent.
Note it doubles as half of the app access token (`{app-id}|{app-secret}`) used to
configure webhooks by API — see Part 11.

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

### 5b. Adding a real (non-555) phone number

The path that actually works. Do this instead of fighting a test number.

**Prerequisite:** the number must not be tied to an existing WhatsApp account.
If it has WhatsApp today, delete that account first (app → Settings → Account →
Delete my account). It also becomes unusable in the regular WhatsApp app
afterwards, so use a spare line, not a personal one.

1. WhatsApp Manager → **Números de teléfono** → *Agregar número de teléfono*.
   Confirm you are on the right WABA first — the selector defaults to whichever
   WABA it feels like, and the Test WABA will reject you with *"This WhatsApp
   account has reached its phone number limit"*.
2. Set the display name, then verify by SMS or voice. For Argentine numbers, if
   the SMS never arrives, use the **voice call** option.
3. Ownership verification gives you `code_verification_status: VERIFIED`, but the
   number is still `status: PENDING` and `platform_type: NOT_APPLICABLE`. **It
   cannot send yet.** Registration is a separate step:

```bash
curl -X POST "https://graph.facebook.com/v23.0/<NEW_PHONE_NUMBER_ID>/register" \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"messaging_product":"whatsapp","pin":"<6 digits>"}'
```

   Keep that PIN — it is the two-step verification PIN, required for any future
   re-registration.

4. Confirm `status: CONNECTED` and `platform_type: CLOUD_API`, then point the
   backend at it:

```bash
npx convex env set        WHATSAPP_PHONE_NUMBER_ID <NEW_PHONE_NUMBER_ID>
npx convex env set --prod WHATSAPP_PHONE_NUMBER_ID <NEW_PHONE_NUMBER_ID>
```

No new asset assignment is needed if the number joins a WABA the system user
already controls, and no webhook change is needed either — the app is subscribed
at the **WABA** level, so a new number under it is covered automatically.

A new number has **no 24-hour window with anyone**, including people who
messaged your old number. Message the new number first, then it can reply.

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
| `131037` | Display name not approved | See the warning below — affects `555` numbers |
| `131047` | Outside 24h window | Send an approved template |
| `131026` | Recipient can't receive (no WhatsApp / wrong ID) | Check `wa_id` — often the Part 6 bug |
| `132000` | Template param count mismatch | Match the approved template exactly |
| `133010` | Number not registered | Call the `register` endpoint |
| `100` | Invalid parameter | Usually a wrong `phone_number_id` |
| `190` | Token expired/invalid | Rotate; a system user token set to "Never" shouldn't hit this |

### `name_status` does not mean the display name is approved

> ⚠️ **Hit on 2026-08-17, after sends had been working.** `+1 555-440-3681`
> reported every green light — `status: CONNECTED`, `code_verification_status:
> VERIFIED`, `quality_rating: GREEN`, `name_status: AVAILABLE_WITHOUT_REVIEW`,
> `new_name_status: NONE` — and WhatsApp Manager showed it as *Conectado* with
> *Alta* quality. Every send still failed:
>
> ```
> 131037 — WhatsApp provided number needs display name approval before message can be sent
> ```
>
> **`AVAILABLE_WITHOUT_REVIEW` means the name *string* is available to claim
> without review. It does not mean the display name has been approved.** There is
> no API field that reports "this 555 number may send"; we read that status as an
> all-clear and it was not one.
>
> Meta requires every `+1 555` test number to have an *approved* display name
> before sending. What makes it genuinely hard to diagnose is that **it starts
> failing after sends have been working.** The exact history on this number:
>
> | When | Sends | Result |
> | --- | --- | --- |
> | 2026-08-16 | 2 | delivered (confirmed on a handset and in Meta's analytics) |
> | 2026-08-17 13:00 | 1 | delivered (`analytics` half-hour bucket: `sent: 1, delivered: 1`) |
> | 2026-08-17 13:08 onward | all | `131037`, every time |
>
> Three successful sends, then a hard stop, with no state change visible in any
> API field. **We could not determine the trigger.** What we ruled out:
>
> - **Not the app subscription.** The failure began minutes after
>   `POST /{waba-id}/subscribed_apps`, which looked causal. Tested by
>   unsubscribing and sending again: still `131037`. Coincidence.
> - **Not our code.** The error reproduces from a bare `curl`.
> - **Not a visible status change.** `name_status`, `new_name_status`, `status`,
>   `code_verification_status`, `quality_rating`, `account_mode` and every other
>   field Meta exposes on a phone number read identically before and after.
> - **No audit trail available.** `GET /{waba-id}/activities` returns `{"data":[]}`,
>   and WABA-level review fields require Business Solution Provider permission.
>
> A plausible-but-unproven reading is that Meta allows a small number of sends
> before enforcing the approval. Operationally it does not matter: the fix is the
> same either way. Just do not expect a working 555 number to keep working, and
> do not treat early successful sends as evidence the number is properly set up.
>
> Also note `POST /{phone-number-id}` with `new_display_name` set to the *current*
> name returns `{"success": true}` while changing nothing — `new_name_status`
> stays `NONE` and no review is triggered. It is not a way to request approval.
> WhatsApp Manager refuses an unchanged name too, so there is no way to
> "resubmit" the name you already have. Submitting a *different* name via the API
> does register (`new_name_status` moves off `NONE`) but does not apply, and does
> not unblock sending.
>
> **How we resolved it: we stopped trying.** We added a self-supplied number
> (`+54 9 11 2399-1858`), registered it for Cloud API, and it sent immediately.
> Total time from decision to working: minutes. Time spent fighting the 555
> number beforehand: hours. **If a 555 number wedges like this, add a real number
> rather than debugging it.** The 555 number remains stuck and is now used only
> for inbound testing.
>
> **Fix:** WhatsApp Manager → Números de teléfono → hover the **Nombre** column →
> pencil icon → set a display name → submit. Review takes minutes to 48 hours.
> The edit control is revealed on CSS `:hover`, so it cannot be automated through
> DOM events.

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
hand-rolled WhatsApp integration later.

### Decision: not adopted (2026-08-17)

Hand-rolled in Convex instead — see Part 12. The deciding factor was not the
Redis dependency but the **lock semantics**. Chat SDK offers
`onLockConflict: 'drop' | 'force'`: drop the incoming message, or force-release
and let two handlers run concurrently on one thread. The behaviour we need is
neither — queue the message and fold it into the next turn — so we would have
been fighting the framework on the one thing this feature is entirely about.
Revisit if a second platform lands.

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

**Outbound messaging** (2026-08-16). A message sent via
`POST /1290033147525120/messages` with the `walletbot-api` system user token was
received on a real handset, inside an open 24-hour window. Credentials, asset
wiring, and the number are all good.

**The webhook is live** (2026-08-17). `WHATSAPP_APP_SECRET` is set on both
deployments, the callback URL is registered and `active: true`, and the app is
subscribed to the WABA. Meta only marks a subscription active *after*
successfully calling the `GET` handshake, so our handler has been validated by
Meta itself.

```
callback_url: https://proficient-finch-671.convex.site/v1/whatsapp/webhook
active:       true
fields:       [messages]
```

**The queue and the agent loop** (2026-08-17). A signed synthetic payload with
three messages produced three inbound rows sharing one `claimedByRunId`, a
single outbound reply listing all three, and a conversation returned to `idle`.
Coalescing verified against the real database. See Part 12 for the test recipes.

**Real inbound, end to end** (2026-08-17). A message sent from an actual handset
was received, HMAC-verified against **Meta's own signature**, enqueued, claimed,
processed, and the conversation released to `idle`. The reply then failed with
`131037` and was recorded in `whatsappOutboundMessages` with its error code —
visibly, rather than vanishing, which is precisely what R-021's mitigation
exists for.

**Working end to end** (2026-08-17). On `+54 9 11 2399-1858`: a real message from
a handset was received, verified, queued, answered by the agent, and the reply
reached `status: read` in `whatsappOutboundMessages` — the full
`sent → delivered → read` lifecycle, applied by status webhooks through
`applyStatusUpdates`. Nothing in the loop is silent any more.

**The agent works, end to end** (2026-08-17). The stub is gone. A linked
conversation now reaches a real Gemini tool-calling loop that reads and writes
the user's finances through `convex/agent/`. Verified against the dev database:

```
"que cuentas tengo?"
  → 2 rounds, 1 tool call
  → "¡Hola! Tenés estas cuentas: Test, MercadoPago, ICBC, Cash, vale…"

"anota 1234,50 de cafe en la cuenta Test, ayer a la tarde"
  → 4 rounds, 3 tool calls (listAccounts, createCategory, addExpense)
  → row written: amount 123450n cents, ARS, timeStatus "approximation",
    dateConfirmed true, seq 58, date = 2026-08-16 16:00 Buenos Aires
  → balance moved to -1234.50; summarizeByCategory for that single day
    returned it, proving the inclusive end-of-day range
```

Both were then removed and the balance confirmed back at 0. Two things this
exercise settled that reading the SDK could not:

1. **Gemini 3 requires thought signatures.** Rebuilding the model's turn from
   `response.functionCalls` drops the sibling `thoughtSignature` on each part
   and the next request fails with `400 … Function call is missing a
   thought_signature`. The model's `candidates[0].content` has to be pushed
   back verbatim. Confirmed against the live API, not inferred from docs.
2. **The free tier is 5 requests per minute**, and one turn costs two to four.
   Three consecutive turns exhaust it and Gemini answers `429
   RESOURCE_EXHAUSTED`. `runAgent` treats that (and 5xx/overload) as
   recoverable and replies "estoy saturado, probá en un minuto" rather than
   going silent — but **a paid key is a prerequisite for real use**, not a
   nice-to-have.

**Replayed turns no longer double-write** (2026-08-17). R-019 made an
idempotency guard a precondition for giving the agent write tools. Two calls
with the same `writeKey` return the same id with `duplicate: true`, and the
account balance moves once. See Part 13.

### Watch out: Meta itself will message your number

The first inbound the live number received was **not** from a human. Meta's own
onboarding bot (`16465894168`) sent a *"Continue setting up your account"*
notification, our agent dutifully treated it as a user turn, generated a reply,
and delivered it.

Harmless with a stub, wasteful with an LLM, and confusing once the agent has
tools — a system notification is not a user asking for something. **Before the
real agent ships, filter inbound by sender**: ignore or route separately anything
that is not a linked, known user. `whatsappConversations.userId` is the natural
place to gate this.

### Configure webhooks by API, not by dashboard

The App Dashboard's webhook panel is a React SPA that resists automation and
hides state. Everything it does is available on the Graph API using an **app
access token** (`{app-id}|{app-secret}`), which is deterministic and
inspectable:

```bash
APP_TOKEN="2576911202751949|$WHATSAPP_APP_SECRET"

# set callback URL + verify token + subscribed fields
curl -X POST "https://graph.facebook.com/v23.0/2576911202751949/subscriptions" \
  -d "object=whatsapp_business_account" \
  -d "callback_url=https://<deployment>.convex.site/v1/whatsapp/webhook" \
  -d "verify_token=$WHATSAPP_VERIFY_TOKEN" \
  -d "fields=messages" \
  -d "access_token=$APP_TOKEN"

# read it back — `active: true` proves the handshake succeeded
curl -s "https://graph.facebook.com/v23.0/2576911202751949/subscriptions?access_token=$APP_TOKEN"
```

Switching the callback between dev and prod is one call, which matters given
Meta allows only one per app.

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

### Tracked in the risk register

Eight entries in `docs/riesgos.md` came out of this work. They are the durable
version of the warnings above:

| ID | Risk | Prob. | Impact |
| --- | --- | --- | --- |
| **R-019** | At-least-once turns duplicate **side effects** once the agent can write — **mitigated 2026-08-17** | Media | Alto |
| **R-020** | The webhook is a public, unauthenticated ingress into the agent | Baja | Crítico |
| **R-021** | The 24h window drops outbound silently | Alta | Medio |
| **R-022** | `wa_id` is not "E.164 without the `+`" | Media | Medio |
| **R-023** | Never-expiring token shared across dev and prod | Baja | Alto |
| **R-024** | The link code is a bearer credential | Baja | Alto |
| **R-025** | The agent writes finances **without prior confirmation** | Media | Medio |
| **R-026** | The user's timezone is inferred from their country code | Media | Bajo |

**R-019 had a hard precondition, and it was met.** The turn claims a batch,
replies, *then* marks it processed; if the action dies in between, the reaper
requeues and the batch runs twice. While the agent only emitted text that cost a
duplicate message — but the moment it got a tool that writes to `transactions`,
the same window would have duplicated the *financial record*. The register
required an idempotency key before any write tool shipped, and
`agent/idempotency.ts` is it: deterministic entity ids derived from the claimed
row ids, so a retry is a no-op. See Part 13 § Replay safety.

**R-025 is the one to watch now.** Voice shows the user the detected movement
before saving; WhatsApp does not. The agent interprets a text message and writes
in the same turn, so a misread amount is already in the database — and the
confirmation the user reads is the model's sentence, not the database's. The
mitigation is partial: write tools return persisted values rather than an echo
of their arguments, so the confirmation is at least built from real data.

### Suggested next steps

1. ~~Decide how a `wa_id` maps to a Wallet Bot `userId`~~ — **done
   (2026-08-17)**: a short-lived link code minted from an authenticated session
   and sent by the user over WhatsApp, with the native UI in the user/accounts
   menu. See Part 12 § Identity. Web parity is still open.
2. ~~Replace the stub `generateReply` with the real agent~~ — **done
   (2026-08-17)**. `convex/agent/` holds a server-side executor for 29 of the 38
   tools, and `runAgent` drives the Gemini tool-calling loop. Writes go through
   `nextSeq`, so they sync to the phone. The nine dashboard/saved-filter tools
   are deliberately out of scope — see Part 13 § Tool surface. **Add a paid
   Gemini key before real use**: the free tier allows 5 requests/min and one
   turn costs two to four.
3. ~~Implement the R-019 idempotency key **before** the agent gets write
   tools~~ — **done (2026-08-17)**, in the same change. `agent/idempotency.ts`
   derives each created entity's id from the claimed row ids by SHA-256, so a
   replay reuses the id and the create returns `{ok: true, duplicate: true}`
   instead of inserting again. Part 13 § Replay safety.
4. ~~Filter inbound by sender~~ — **done**: the identity gate in `runAgentTurn`
   means an unlinked sender, Meta's own bot included, never reaches the agent.
   It still costs one cheap turn and one fixed-copy reply.
5. Create at least one approved template if the agent should ever initiate
   rather than only reply. Not needed for linking — that flow is deliberately
   user-initiated (Part 12 § Identity).
6. Decide the dev/prod callback split — one Meta app per environment, or accept
   that only one receives messages. Both deployments currently point at the same
   number and the same WABA.
7. **Add a payment method** to the WABA (`No se encontró ningún método de pago`).
   User-initiated service conversations have a free allowance, so testing is
   fine, but templates and volume are not.
8. **Complete business verification** (`No verificado`). Not needed to start;
   it caps the number at **250 unique recipients / 24h**.
9. Consider subscribing to the `phone_number_name_update` webhook field — it
   reports display-name approval, which is the signal we had no visibility into
   during the `131037` incident. We currently subscribe to `messages` only.
10. **Store the user's timezone in `userSettings`** and have the native app
   write it. The agent currently infers it from the sender's country code
   (R-026), which is wrong for travellers and for DST countries. The app
   already knows the real zone.
11. Handle inbound **media**. Audio, images and documents are recognised but
   not downloaded: the agent is told "the user sent a `<type>` message, which I
   cannot open yet" so it can say so rather than ignore them. Voice notes are
   the obvious next channel — the transcription path already exists for the
   live agent.
12. Consider a "this is what I saved" turn summary built from the ids the
   executor actually wrote, rather than from the model's own sentence (R-025).

---

## Part 12 — The implementation

What actually exists in the backend, and how to test it.

### Files

| File | Role |
| --- | --- |
| `convex/schema/whatsapp.ts` | `whatsappConversations` (the lock), `whatsappInboundMessages` (the queue), `whatsappOutboundMessages` (delivery log), `whatsappLinkCodes` (identity) |
| `convex/whatsapp/http.ts` | `registerWhatsappRoutes` — `GET` handshake, `POST` events |
| `convex/whatsapp/utils.ts` | HMAC verification, defensive payload parsing |
| `convex/whatsapp/internal.ts` | `enqueueInbound`, `claimOrRelease`, `finishBatch`, `recordOutbound`, `applyStatusUpdates`, `handOffTurn`, `releaseStuckTurns`, `tryLink`, `purgeExpiredLinkCodes`, `recentHistory` |
| `convex/whatsapp/helpers.ts` | `sendText`, `windowIsOpen`, `chunkBody` |
| `convex/whatsapp/linking.ts` | Pure link-code logic: generation, normalisation, extraction, reply copy, deep link |
| `convex/whatsapp/nodeActions.ts` | `runAgentTurn` — the drain loop, the identity gate, and the call into the agent |
| `convex/agent/runner.ts` | `runAgent` — the Gemini tool-calling loop; `runForUser` for testing without a phone |
| `convex/agent/tools.ts` | `execute` — the server-side tool executor, one internal mutation per call |
| `convex/agent/resolve.ts` | `idOrName` → entity, mirroring the native resolver |
| `convex/agent/time.ts` | Offset-aware date parsing, so "hoy" means the user's today |
| `convex/agent/idempotency.ts` | Deterministic entity ids, so a replayed turn writes nothing twice (R-019) |
| `convex/agent/prompt.ts` | The text-channel system instruction |
| `convex/agent/toolset.ts` | Which tools the text agent may call |
| `convex/agent/schema.ts` | Shared tool-schema → Google `FunctionDeclaration` adapter (also used by voice) |
| `convex/v1/whatsapp/mutations.ts` | `createLinkCode`, `unlink` — the authenticated half of linking |
| `convex/v1/whatsapp/queries.ts` | `linkStatus` — which numbers are connected |

Registered in `schema.ts`, `http.ts`, and `crons.ts` (reaper every 5 minutes, link-code purge hourly).

### How the coalescing works

```
Meta ──POST──► httpAction ─────────────────────────────► 200 OK (~ms, no LLM)
                  │ verify signature over the RAW body
                  ▼
            enqueueInbound   ◄── ONE TRANSACTION
                  │ dedupe on wamid; insert as pending
                  │ if status == idle → processing + schedule turn
                  │ else            → nothing; the live turn drains it
                  ▼
            runAgentTurn (loops)
                  │ claimOrRelease(runId)
                  │   fenced?   → stop (someone else owns this)
                  │   released? → stop (queue empty, lock idle)
                  │   batch?    → agent over ALL of it, send, finish
                  └── loop: messages that arrived during the LLM call
```

**Why there is no lock server.** Convex mutations are serializable transactions,
so "is a turn running?" and "start a turn" happen atomically. Two webhooks
landing at the same instant cannot both start a worker.

**Why claim and release are one mutation.** Splitting them reopens the classic
lost-wakeup: a message arriving between "queue looks empty" and "set idle" finds
the conversation still `processing`, declines to start a turn, and waits forever
for a worker that already exited. Deciding both inside one transaction removes
the window entirely.

**Why `runId` exists.** If a turn's action dies, the reaper releases the lock. A
zombie that resumes later carries a stale `runId`, fails `claimOrRelease`, and
cannot touch state a newer turn now owns.

**Why `handOffTurn` exists.** Convex actions have an execution limit. After 20
loops a busy conversation mints a fresh `runId` and schedules a new action rather
than being killed while still holding the lock.

### Identity: linking a `wa_id` to an account

A `wa_id` proves nothing. The webhook is public and unauthenticated, so anyone
who knows the business number can send it a message claiming to be anyone. That
makes `whatsappConversations.userId` the authorization boundary for the entire
feature — not a convenience field.

`runAgentTurn` gates on it. A conversation with no `userId` never reaches the
model, a tool, or any account data; the only thing it can do is present a link
code and get a fixed reply.

**The flow is user-initiated on purpose.**

```
app (authenticated)                WhatsApp                    backend
────────────────────               ────────                    ───────
createLinkCode ──────────────────────────────────────────► mint code (10 min, single use)
   ◄── code + wa.me deep link
   user taps the deep link
        │
        └─► WhatsApp opens with the code prefilled
              user taps send ─────────────────────────────► webhook (inbound)
                                                              enqueue → turn
                                                              userId == null
                                                              → tryLink(candidates)
              ◄──────────────── "✅ vinculado" ──────────── set userId, consume code
```

Nothing here is business-initiated, and that is deliberate. A message Wallet Bot
sends first would be an out-of-window, template-only send — the failure mode in
Part 7, where Meta returns `200` and a `wamid` and silently discards it. Because
the user taps send, they open the 24-hour service window themselves and every
reply is free-form and deliverable. It also means the flow needs no approved
template, so it works today, on a WABA with zero templates.

The `wa.me` deep link is what makes that ergonomic: it opens WhatsApp with the
code already typed, so "user-initiated" costs one tap instead of asking someone
to copy a code between apps. Note it takes the **dialable** number
(`WHATSAPP_BUSINESS_NUMBER`), not the `wa_id` — see Part 6.

**Design notes worth keeping.**

- The code is stored in plain text. Hashing looks safer but buys nothing: 8
  characters over a 32-symbol alphabet is ~1.1e12 preimages, exhaustible in far
  less than the code's 10-minute life. The real controls are the TTL, single
  use, and the attempt limit.
- Codes always contain at least one digit and at least one letter, and
  extraction requires the same. Without that rule a message like `VINCULAR`
  parses as a code — Crockford aliasing maps `I`→`1` and `U`→`V` — and burns one
  of a legitimate user's five attempts.
- Uniqueness is enforced when minting, not assumed from randomness, so the
  `by_code` lookup can use `.unique()` and a collision can never resolve one
  user's code to another user's account.
- Five wrong codes → 15-minute block, answered with **silence**. Replying would
  turn the limit into a free oracle. Re-sending your own already-used code, or
  an expired one, is not counted — that is what a confused user does.
- Replies are **one language, never two**. There is no account yet and so no
  stored locale, so `replyLanguageFor` picks from the sender's country code
  against a hard-coded table. Spanish-speaking Latin America plus Spain get
  Spanish; everything else gets English. Two consequences are intentional:
  **Brazil gets English** (Latin America, but the dividing line is Spanish, not
  geography), and **the Dominican Republic and Puerto Rico get English**
  because their numbers are +1 and cannot be told apart from any other NANP
  number without an area-code table. Once linked, the agent follows the user's
  own words instead and the table stops mattering.
- `unlink` revokes pending codes. Otherwise a code minted just before
  unlinking stays live and could silently re-link the number.

**Native UI (2026-08-17).** Reachable from the user/accounts menu
(`screens/home.dart`), which pushes `screens/whatsapp_link.dart`. State lives in
`whatsapp/whatsapp_link_controller.dart`.

Two things about it are worth knowing before changing it:

- **It caches nothing**, unlike `DefaultCurrencyController`. That controller
  caches because a default currency is needed offline to prefill a form; link
  state is only read on a screen that cannot act without the network, and a
  cached code would be a stale credential. Offline shows an error with a retry
  rather than a plausible-looking empty list.
- **`isRemote` gates every call.** A local-only account has no backend user, so
  the screen explains that instead of offering a button that would fail. The
  test asserts no query is issued at all, so the gate cannot rot into a purely
  visual one.

The controller depends on a two-method `WhatsappLinkApi` rather than
`ConvexClient` directly. `ConvexClient` has a private constructor and an
`instance` getter that throws under `flutter test`, so it cannot be faked;
narrowing the dependency is what makes the parsing and state machine testable.
`ConvexLinkApi` is the one production implementation.

**Still missing:** the web UI — nothing in `apps/web` calls these functions, so
linking is native-only for now. There is also no notification to the user when
their account gets linked to a new number (R-024).

### Testing without Meta

The pure link logic has no Convex or Node dependencies, so it runs directly:

```bash
# 38 assertions incl. 20k generated codes round-tripping through the display form
node --experimental-strip-types /path/to/link-test.ts
```

The `GET` handshake:

```bash
# expect the challenge echoed back
curl -s "https://<deployment>.convex.site/v1/whatsapp/webhook\
?hub.mode=subscribe&hub.verify_token=$WHATSAPP_VERIFY_TOKEN&hub.challenge=ping123"

# expect 403
curl -s -o /dev/null -w '%{http_code}\n' "https://<deployment>.convex.site/v1/whatsapp/webhook\
?hub.mode=subscribe&hub.verify_token=wrong&hub.challenge=x"
```

A rejected handshake logs `whatsapp webhook verification rejected`. If you see
that while configuring the callback URL for real, the verify token you supplied
does not match `WHATSAPP_VERIFY_TOKEN`.

A signed synthetic delivery — this is the one that exercises the whole pipeline.
Write the payload to a file so the HMAC covers the exact bytes sent:

```bash
S=$(npx convex env get WHATSAPP_APP_SECRET)   # from packages/backend
TS=$(date +%s)
cat > /tmp/wh.json <<JSON
{"object":"whatsapp_business_account","entry":[{"id":"1042220975475427","changes":[{"field":"messages","value":{
"messaging_product":"whatsapp",
"metadata":{"display_phone_number":"+54 9 11 2399-1858","phone_number_id":"1324548857400869"},
"contacts":[{"profile":{"name":"Test"},"wa_id":"<YOUR_WA_ID>"}],
"messages":[
{"from":"<YOUR_WA_ID>","id":"wamid.TEST-$TS-1","timestamp":"$TS","type":"text","text":{"body":"hola"}},
{"from":"<YOUR_WA_ID>","id":"wamid.TEST-$TS-2","timestamp":"$TS","type":"text","text":{"body":"segundo"}},
{"from":"<YOUR_WA_ID>","id":"wamid.TEST-$TS-3","timestamp":"$TS","type":"text","text":{"body":"tercero"}}]}}]}]}
JSON

SIG=$(openssl dgst -sha256 -hmac "$S" -hex < /tmp/wh.json | awk '{print $NF}')
curl -s -X POST "https://<deployment>.convex.site/v1/whatsapp/webhook" \
  -H 'Content-Type: application/json' -H "X-Hub-Signature-256: sha256=$SIG" \
  --data-binary @/tmp/wh.json
```

Then inspect the result:

```bash
npx convex data whatsappConversations      # status should be back to idle
npx convex data whatsappInboundMessages    # 3 rows, ONE shared claimedByRunId
npx convex data whatsappOutboundMessages   # exactly ONE reply
```

`wamid`s must be unique per run or dedupe correctly skips them — hence `$TS`.

**Two caveats on synthetic tests.** A forged payload resets *our* tracked 24-hour
window but not Meta's, so `windowIsOpen` passes while the real send may still be
discarded; check `whatsappOutboundMessages.status`. And the recipient must be on
the test number's allow-list or the send fails with `131030`.

### Testing with Meta

Message the business number from a real handset. That is the only path that
exercises Meta's signature generation, the real service window, and delivery
statuses. Watch the Convex logs for the turn and `whatsappOutboundMessages` for
the status transitions.

---

## Part 13 — The agent

### Why none of the voice agent transferred

The voice agent mints a short-lived Gemini token (`live/createToken.ts`) and the
**phone** talks to Gemini, executing tools against its own Drift database. That
shape has no server in the middle by design — native has to work offline.

A WhatsApp message has no device attached. The model call, the tool execution
and the reply all have to happen inside one Convex action, against Convex's
copy of the data. So the prompt and the tool *schemas* were reusable; the
executor was not, and `apps/native/lib/voice/tool_executors.dart` had to be
written a third time in TypeScript.

That leaves three executors over one contract
(`packages/shared/src/tools/definitions.ts`): the Dart one, the `v1/*`
mutations the app's forms call, and `convex/agent/tools.ts`. The duplication is
real and deliberate — each has a different authorization story and a different
database — but it means **a change to money semantics has to be made in all
three**, and `agent/tools.ts` flags inline wherever it diverges from `v1/*`.

### The loop

```
runAgentTurn  (whatsapp/nodeActions.ts)
  ├─ claim batch ─────────────────────── coalesced messages, one turn
  ├─ identity gate ──────────────────── unlinked → link flow, never the model
  ├─ recentHistory ──────────────────── last 20 messages, 24h, both directions
  └─ runAgent  (agent/runner.ts)
       ├─ generateContent(model, contents, tools)
       ├─ functionCall parts?  ── no ──▶ reply text
       │        │ yes
       │        ▼
       ├─ push candidates[0].content VERBATIM   ← thought signatures
       ├─ execute each call  ──▶ agent/tools.ts (one internal mutation each)
       └─ push functionResponse parts, loop (max 8 rounds / 24 calls)
```

### Tool surface: 29 of 38

Everything about money is there: accounts, categories, tags, transaction reads
and writes, and the two summaries.

**The nine dashboard and saved-filter tools are deliberately not exposed.**
`createDashboardWidget` has to place a tile on a grid, and that packing lives
in Dart (`components/dashboard/dashboard_layout.dart`) with no server-side
equivalent; a WhatsApp user also cannot see the result. Porting the packer for
a surface nobody can look at is work with no payoff, so the prompt tells the
agent to send the user to the app instead. `agent/toolset.ts` is the single
list, shared by the model's declarations and the executor's dispatch, so the
model can never call something the executor cannot handle.

### "Hoy" has to mean the user's today

Convex runs in UTC. The naive implementation files an expense reported at 22:30
in Buenos Aires under *tomorrow*, and in a finance app the calendar day is the
axis everything is read along.

`agent/time.ts` therefore takes an explicit UTC offset and computes everything
with `Date.UTC`/`getUTC*` on a shifted instant, never reading the ambient
timezone — the result is identical wherever the action runs. The offset comes
from the sender's country code (`utcOffsetMinutesFor`), the same hard-coded
table shape as the reply language, because a WhatsApp conversation carries no
locale and the account stores no timezone. That inference is wrong for
travellers and for DST countries; it is tracked as R-026, whose real fix is
storing the timezone in `userSettings` from the native app.

One trap worth naming: `Date.parse('2026-08-17T14:30')` resolves a **zoneless**
datetime against the host timezone, so an offset correction on top of it
double-applies. The parser handles that form field by field instead. Two of the
44 date assertions exist purely because that bug shipped and was caught.

### Replay safety

A WhatsApp turn is at-least-once (R-019): if the action dies between sending
and `finishBatch`, the reaper re-queues the batch and the agent runs again on
the same input. With read-only tools that cost a repeated reply; with write
tools it would cost a second expense.

`agent/idempotency.ts` makes the *identity* of what the agent creates a
function of the turn rather than of chance:

```
turnKey  = sorted claimed row ids        (the reaper re-queues rows, not recreates them)
writeKey = turnKey | toolName | nth      (nth counts calls of that tool, not all calls)
id       = SHA-256(writeKey) → UUID-shaped, version 8
```

A replay lands on the same id and the existing "already exists" check turns the
insert into a no-op. Counting per tool name — not globally — keeps the mapping
stable when a replay happens to interleave a different number of reads. In
`addBalanceAdjustment` the guard runs *before* the balance is read, or the
replay would see the already-adjusted balance and write a second zero-delta
adjustment.

The duplicate *reply* is not mitigated, deliberately: it is visible and
harmless, unlike a duplicate movement.

### Configuration

| Variable | Default | Why you'd change it |
| --- | --- | --- |
| `GEMINI_API_KEY` | — | Required. The free tier's 5 req/min is not enough for real use. |
| `GEMINI_TEXT_MODEL` | `gemini-3-flash-preview` | Roll the model forward without a deploy when Google retires a preview. |

Thinking level is pinned to `LOW`. Gemini 3 defaults to `HIGH`, which is not
worth it for "anotá $5.000 de café" when the user is watching two grey ticks.

### Testing without a phone

`runForUser` is an internal action, so `userId` is trusted and it can never be
reached from a client:

```bash
npx convex run agent/runner:runForUser \
  '{"userId":"<convex user id>","text":"gasté 500 en café"}'
```

To exercise the executor without spending model quota — useful, given the rate
limit — call a tool directly:

```bash
npx convex run agent/tools:execute '{
  "userId":"<id>", "name":"getAccountBalance",
  "argsJson":"{\"idOrName\":\"Efectivo\"}",
  "nowMs":1786993584624, "utcOffsetMinutes":-180
}'
```

Date handling has 44 assertions in a standalone script (there is no test runner
in `packages/backend` yet), run under four different host timezones to prove it
does not read the ambient zone:

```bash
TZ=Asia/Tokyo node --experimental-strip-types agent-time-test.ts
```

## Sources

- [Get Started — WhatsApp Cloud API](https://developers.facebook.com/docs/whatsapp/cloud-api/get-started/)
- [Business phone numbers](https://developers.facebook.com/documentation/business-messaging/whatsapp/business-phone-numbers/phone-numbers)
- [WhatsApp Business Accounts](https://developers.facebook.com/documentation/business-messaging/whatsapp/whatsapp-business-accounts)
- [Embedded Signup overview](https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/overview/) — the "two 555 numbers" limit
- [Webhooks overview](https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/overview)
- [Subscribed Apps API](https://developers.facebook.com/documentation/business-messaging/whatsapp/reference/whatsapp-business-account/subscribed-apps-api)
- [Chat SDK — WhatsApp adapter](https://chat-sdk.dev/adapters/official/whatsapp)
- Brazil/Mexico/Argentina `wa_id` divergence: [Gupshup](https://support.gupshup.io/hc/en-us/articles/4413210201625-Why-do-we-see-differences-between-the-actual-dial-numbers-and-the-one-registered-on-WhatsApp-for-region-Brazil-Mexico), [Chatwoot](https://www.chatwoot.com/hc/user-guide/articles/1758697086-inconsistencies-for-whats_app-numbers-in-brazil-mexico-and-argentina)
