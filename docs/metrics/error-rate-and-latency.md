# Spike: Error Rate & Response-Time Metrics (WAL-203)

Grafana today only shows **business** metrics (accounts, movements, agent cost —
see [`observability-grafana.md`](../observability-grafana.md)). This spike
investigates how to add the classic **operational** signals — error rate and
latency p50/p95/p99 — and recommends a path forward.

## Current state

- `telemetryMetrics` (`packages/backend/convex/schema/telemetry.ts`) is a
  short-lived outbox: every metric is one row, exported to Grafana Cloud via a
  custom OTLP/HTTP exporter (`telemetry/actions.ts`), then deleted after 24h.
  Counters are merged into a cumulative value through a companion
  `telemetryMetricSeries` table (one row per unique
  `name+source+unit+appVersion+platform+attributes` key,
  `telemetry/mutations.ts:reserveMetricExports`); gauges just export their
  latest value. **Every metric write costs at least one extra document
  insert, plus a read+patch of its series row on export** — this is the
  baseline overhead any new per-call metric inherits.
- `MetricType` already includes `'histogram'` and `unit: 'ms'` in the type
  system (`telemetry/types.ts`), but **the OTLP exporter never implements it**:
  `toOtlpMetricsPayload` (`telemetry/actions.ts:216-255`) only has branches for
  `gauge` and `sum` (counter). Adding a metric literally named as a histogram
  today would silently export as a plain counter. There is a working
  precedent for a *poor-man's histogram* though: `agent.session.cost_bucket_count`
  (`telemetry/metrics.ts:243-280`) buckets a continuous value (cost) into a
  fixed label (`cost_bucket: '0.05-0.10'`, etc.) and increments a counter — a
  bar-chart-shaped distribution, not a true cumulative Prometheus histogram
  (`histogram_quantile()` needs cumulative `le`-bucketed counters, which this
  isn't). We reuse this exact pattern below for latency.
- There is **no function wrapper / choke point** anywhere in the backend.
  Every `query`/`mutation`/`action` (~98 definitions) is created directly from
  `_generated/server` and calls `requireAuth` manually as its first line
  (`users/helpers.ts:51-55`, throws a plain `Error('Unauthenticated')`, never
  `ConvexError`). `convex-helpers/server/customFunctions` is not used at all.
  This means "wrap every query/mutation/action" is not a one-file change — it
  either means introducing a wrapper and migrating ~98 handlers, or
  instrumenting a handful of call sites explicitly.
- **Errors are 100% unstructured**: ~147 `throw new Error('free text')` sites,
  zero `ConvexError` usage anywhere. There is no error-code field to turn into
  a low-cardinality label today — that has to be introduced first, at least at
  the call sites we want to measure.
- **Sync (`v1/sync/queries.ts:pull`, `v1/sync/mutations.ts:push`) has no
  telemetry wired in at all.** Its failure shapes are inconsistent:
  `client_outdated` and `cursor_mismatch` are returned as data
  (`{ ok: false, error: ... }`); everything else (~10 distinct validation
  cases — bad currency change, tag self-parent, missing account/category,
  transfer validation, join-row mismatches — plus auth failure) is a thrown,
  uncoded `Error`. On the native client
  (`apps/native/lib/sync/sync_engine.dart`), `client_outdated` halts sync
  permanently and `cursor_mismatch` retries the round (both handled, both
  expected); everything else falls into one generic catch-all that
  `debugPrint`s locally, sets `SyncStatus.error`, and retries forever with
  exponential backoff — **a permanent validation bug and a transient network
  blip look identical, and neither is visible outside the device.** So: **we
  genuinely don't know today whether sync is healthy** — there's no signal
  besides a user reporting the pill stuck on "error".
- **Client latency has no credential problem to solve** — clients already
  POST to the public `/telemetry/metrics` endpoint
  (`telemetry/http.ts:376-415`), which never touches Grafana credentials (the
  backend owns the OTLP export). Native already computes the exact timings we
  want and just doesn't send them: `gemini_voice_expense_command.dart` runs a
  `Stopwatch` through `_logConnectionPhase()` (line 779) at `token_resolved` /
  `setup_complete` (line 677) / `context_seeded`, but only persists it to a
  local Drift session log (`_persistProtocolEvent`), never to
  `TelemetryClient.trackMetric`. Time-to-first-response has no existing timer
  (would start at `sendText()`/`endAudioStream()`, end at the first
  `outputTranscription` or audio chunk in `_handleServerContent`). **Web has
  no telemetry client at all** (`apps/web/src` has zero references to
  `telemetry`) — before web can report anything, it needs the client that
  native already has (`apps/native/lib/telemetry/telemetry_client.dart`)
  ported over. That's its own task, not something this spike's POC should
  absorb.
- **Convex Log Streams** (Pro plan, **$25/developer/month**) would stream
  every function execution to Datadog/Axiom/PostHog/a custom webhook, with an
  event that already includes `execution_time_ms`, `status: success|failure`,
  `error_message`, `function.path`, `request_id`, and a DB/storage/network I/O
  breakdown per call — i.e., free per-function traces, essentially. **We're
  not paying for Pro**, so this is ruled out; noted here only because it's the
  reason a per-function *breakdown* (not just a total) is expensive to get any
  other way — see "Traces without Log Streams" below. The free built-in
  **Health** page only shows deployment-wide failure % and cache hit rate, no
  per-function breakdown; the free **Logs** page in the dashboard shows
  execution time and status per call in real time as you watch it, but
  nothing is retained, aggregated, or exportable — it answers "what's
  happening right now if I'm staring at the screen," not "what's our p95".
  [Docs](https://docs.convex.dev/production/integrations/log-streams/).

## Options

| # | Approach | What it covers | Extra DB writes | Engineering cost | Cash cost |
|---|---|---|---|---|---|
| A | Hand-rolled: extend `telemetryMetrics` with an error counter + bucketed-counter **total** latency (reusing `cost_bucket_count`'s pattern), called explicitly from a chosen set of call sites | Whatever we instrument, at our label granularity — **total** duration per call, not a DB/external-API breakdown | 1-2 extra rows per instrumented call (same order as today's business metrics) | Low-medium: no OTLP histogram engineering needed (bucketed counters reuse the existing counter path), but errors *do* need a coded-reason prerequisite at each site we touch | $0 |
| B | ~~Convex Log Streams → Datadog/Axiom~~ | Every function, error rate + p50/p95/p99 latency + I/O breakdown, automatically | 0 | — | **$25/dev/month — ruled out, not pursuing** |
| C | Blanket `customQuery`/`customMutation`/`customAction` wrapper instrumenting all ~98 handlers | Everything, uniformly, total duration only (still no DB/API breakdown without hand-rolled spans — see E) | Highest — every single call gets extra writes | High: new wrapper pattern + migrate 98 handlers | $0 |
| D | `@convex-dev/aggregate` (already used in `aggregates.ts` for `outflowsByAccount`/`inflowsByAccount`/`transactionsByTag`) keyed by `duration_ms` per function+window, queried with `.at(rank)` for exact percentiles | Exact p50/p95/p99 for whatever we insert into it, queryable from an internal dashboard/query — no Grafana export required | 1 write per sampled call | Medium — no export/outbox overhead, but percentiles live in Convex, not Grafana, so it doesn't fold into the existing "one Grafana dashboard" workflow | $0 |
| E | Hand-rolled minimal spans: wrap only the specific sub-operations we suspect are slow (the Gemini Live call, the exchange-rate fetch, the WhatsApp webhook round-trip, a handful of known-heavy DB reads) with manual start/end timers, batch-export as OTLP traces through a **new** exporter added next to the existing logs/metrics ones in `telemetry/actions.ts`, into Grafana Tempo | DB-call/external-API-level breakdown, but only for the sites we chose to wrap — never automatic like Log Streams | 1 extra row per wrapped sub-operation (only where we added a timer) | Medium-high: new outbox table + OTLP traces payload shape (span id/parent id/trace id) + manual wrapping at each site of interest, no help from the platform | $0 — Grafana Cloud's free tier includes 50GB traces/month, 14-day retention ([source](https://grafana.com/docs/grafana-cloud/platform/pricing-and-usage/usage-limits/)) |

## Recommendation

We're not paying for Convex Pro, so Option B is off the table, and Option C
(instrument all 98 functions uniformly) is too much lift for a first
iteration. First iteration is **total latency only** — no DB/external-API
breakdown yet:

1. **Errors, targeted (Option A).** Two counters, `sync.errors.count` and
   `agent.tool.errors.count`, recorded explicitly at the handful of sites
   that answer an open question in the ticket — sync `push`/`pull` and agent
   tool-call failures. Those sites carry a small closed error code so the
   label stays low-cardinality instead of being free text. This directly
   answers "is Sync healthy?", which today it's impossible to answer without
   asking a user to reproduce the issue and read `debugPrint` output off
   their device. A failure that throws inside a Convex transaction rolls back
   every write in it, telemetry included, so errors are recorded from
   *outside* the failing transaction — see "Emitters and coverage".
2. **Backend total latency, also Option A.** Time the same call sites we're
   already adding error counters to (sync `push`, agent turn processing)
   end-to-end and bucket the elapsed ms into
   `system.function.duration_bucket_count` the same way
   `agent.session.cost_bucket_count` already buckets cost. This is a handful
   of call sites, not all 98 functions, and needs no exporter changes at all
   (it's a counter, like everything else in the outbox today). It answers
   "how slow is a sync round / an agent turn," which is most of what the
   ticket actually needs for v1 — it does **not** tell us whether a slow call
   was slow in the DB, in a `fetch` to Gemini, or in our own code, and that's
   an explicit, accepted gap for this iteration. **Clock:** inside a query or
   mutation, `Date.now()` is frozen at the moment the function starts, so
   subtracting two readings always gives 0 (the first version of `push` did
   exactly that). `performance.now()` does advance inside mutations, so
   `push` uses it ([Convex runtimes](https://docs.convex.dev/functions/runtimes)).
   In actions (`agent_turn`), `Date.now()` advances normally.
3. **Client latency, native only for now.** Redirect the `Stopwatch` values
   `gemini_voice_expense_command.dart` already computes
   (`setup_complete`) into a bucketed counter, and add one new start/end
   timer pair for time-to-first-response. Web needs
   its own telemetry client built first — track that as a separate ticket, it
   shouldn't block this spike's POC.
4. **Keep the bucketed-counter pattern** (`agent.session.cost_bucket_count`
   precedent) for every latency metric above — it needs no exporter changes
   and is already proven in production.

### Traces, eventually, without paying for Log Streams

Log Streams would have given us this for free (per-call DB/storage/network
I/O breakdown, no code changes). Without it, the only way to see *why* a call
was slow — not just that it was — is to hand-roll minimal spans (Option E)
around the specific sub-operations we come to suspect, once total-latency
metrics from this iteration point at a slow call site:

- Reuse the outbox pattern that already exists for events/metrics
  (`telemetry/actions.ts`): a `telemetrySpans` table, a batch exporter posting
  OTLP `resourceSpans` to Grafana Tempo's OTLP endpoint (same Grafana Cloud
  stack, different signal — `/v1/traces` instead of `/v1/metrics`), same
  retry/outbox/cleanup cron shape as `exportPendingMetrics`.
- Instrument narrowly, not broadly: wrap the 2-3 external calls we already
  suspect are the tail (the Gemini Live round-trip, the exchange-rate fetch,
  the WhatsApp webhook turn) plus any DB read the total-latency metrics above
  flag as consistently slow. This is deliberately the opposite of automatic
  instrumentation — every span is a line we chose to add, so cardinality and
  cost stay bounded and visible.
- Grafana Cloud's **free tier includes 50GB of traces/month with 14-day
  retention** ([usage limits](https://grafana.com/docs/grafana-cloud/platform/pricing-and-usage/usage-limits/)),
  so this path doesn't reintroduce a cash cost — the cost is entirely
  engineering time to build a second exporter and thread trace/span ids
  through the call chain (a `traceId` would need to travel from the HTTP
  request or client call down through any nested `ctx.runAction`/`runQuery`
  calls, which nothing in the codebase does today).
- Treat this as explicitly out of scope for v1: only worth building once the
  total-latency counters above show us we actually have a "why is this slow"
  problem, not a "how slow is this" problem.

## Proposed metrics

All new metric names follow the existing `<domain>.<subject>.<verb>_<unit>`
convention and are registered in `MetricName`/`metricCatalog` like any
existing metric.

| Name | Type | Unit | Labels | Emitter |
|---|---|---|---|---|
| `sync.errors.count` | counter | count | `direction` (`push`\|`pull`), `reason` (`client_outdated`\|`cursor_mismatch`\|`auth_failure`\|`validation`\|`unknown`), `platform` | backend for `push`, native for `pull` |
| `agent.tool.errors.count` | counter | count | `tool_name` (bounded — existing tool registry), `reason` (`invalid_args`\|`not_found`\|`provider_error`\|`unknown`) | backend |
| `system.function.duration_bucket_count` | counter | count | `function` (`sync_push`\|`sync_pull`\|`agent_turn` — the handful we instrument, not all 98), `bucket` (`0-100`\|`100-250`\|`250-500`\|`500-1000`\|`1000-2500`\|`2500-5000`\|`5000+`), `status` (`ok`\|`rejected`\|`error`) | backend for `sync_push`/`agent_turn`, native for `sync_pull` |
| `voice.connect.setup_complete_bucket_count` | counter | count | `bucket` (`0-250`\|`250-500`\|`500-1000`\|`1000-2500`\|`2500-5000`\|`5000+`), `platform`, `resumed` | native (later: web) |
| `agent.response.first_token_bucket_count` | counter | count | `bucket` (same shape as above), `mode` (`voice`\|`text`), `platform` | backend, derived from `agent.response.first_token_ms` at ingest (WAL-216); native builds from before WAL-216 still send it directly |
| `agent.response.first_token_ms` (WAL-216) | gauge | ms | `mode` (`voice`\|`text`), `platform` | native and web: the raw time to first response, one per turn |
| `sync.push.client_failures.count` (WAL-216) | counter | count | `reason` (`auth_failure`\|`network`\|`unknown`), `platform` | native: push calls that **threw** before the backend could record an outcome |
| `agent.tool.calls.count` (WAL-216) | counter | count | `tool_name` | backend: one per tool call, the denominator of the tool error rate |
| `system.latency.quantile_ms` (WAL-216) | gauge | ms | `operation` (`sync_push`\|`agent_first_response`), `batch_size` or `mode` (or `all`), `quantile` (`0.5`\|`0.95`\|`0.99`), `window` (`24h`) | backend, hourly cron |
| `system.latency.samples_count` (WAL-216) | gauge | count | same as above, without `quantile` | backend, hourly cron |

All of them are total-duration/count signals — none of them break a call down
into DB time vs. external-API time vs. our own code. That breakdown is
explicitly deferred (see "Traces, eventually" above).

`status` on `system.function.duration_bucket_count`:

- `ok` — the call did its job.
- `rejected` — a refusal returned as data, with no writes: `client_outdated`
  or `cursor_mismatch`. Not a failure of the backend. `cursor_mismatch` in
  particular is **recoverable**: the client drains pull and retries the same
  batch, so it measures contention, not breakage.
- `error` — an exception.

Every `sync_push` call records exactly one duration sample, so the count of
`sync_push` samples is the push **attempt count**, and the error rate needs
no separate attempts counter.

## Emitters and coverage

**One emitter per observed operation.** Counting the same event from two
places and relying on a `metric_source` filter to dedupe is how panels end up
double-counting, so each operation has a single owner:

| Operation | Errors | Duration | Owner and why |
|---|---|---|---|
| Sync push (apply one batch) | `sync.errors.count{direction="push"}` | `sync_push` | **Backend.** It applies the batch, and sees rejections returned as data that an HTTP status would never show. |
| Sync pull | `sync.errors.count{direction="pull"}` | `sync_pull` | **Native.** `pull` is a Convex query and cannot write. The duration covers the network download **and** the local Drift apply of every page, not backend time alone. |
| Agent tool call (WhatsApp) | `agent.tool.errors.count`, over `agent.tool.calls.count` | — | **Backend.** `execute` records calls that return; `agent/runner.ts` records calls that throw (their rollback discards whatever `execute` wrote). Each call is counted exactly once. |
| Agent turn (WhatsApp) | — | `agent_turn` | **Backend.** Model + tools loop only, not queue wait or reply send. |
| Time to first agent response | — | `agent.response.first_token_ms` → derived `agent.response.first_token_bucket_count` + percentile sample | **Client (native and web).** One raw sample per turn; the backend derives the bucket counter, so a client never sends both. `mode` separates text from voice. |
| Voice connect | — | `voice.connect.setup_complete_bucket_count` | **Client (native and web).** |
| Push calls that threw on the client | `sync.push.client_failures.count` | — | **Native.** A *separate* metric: the backend stays the only emitter of push outcomes (`sync.errors.count{direction="push"}` and the `sync_push` duration). A push that **returned** `ok: false` is never counted here. |

**Recording errors outside the failing transaction.** A Convex mutation that
throws rolls back *all* its writes, a telemetry row included, so "catch →
record metric → rethrow" records nothing. The fix depends on where the
outer layer is:

- **Push.** `v1/sync/mutations.ts:push` keeps auth, the version floor and the
  CAS, and applies the batch (counter bump, upserts, tombstones) through
  `ctx.runMutation(internal.v1.sync.internal.applyPushBatch)`. A nested
  `runMutation` is a sub-transaction: if it throws, only *its* writes roll
  back and the caller can catch the error
  ([docs](https://docs.convex.dev/api/interfaces/server.GenericMutationCtx#runmutation)).
  `push` then records the error and returns
  `{ ok: false, error: 'push_failed', reason }` instead of rethrowing. No
  business write from a failed batch commits, only the telemetry. Validation
  throws are a `ConvexError` with `kind: 'sync_validation'`, because only a
  `ConvexError`'s data survives the `runMutation` boundary. Covered by
  `convex/sync/pushTelemetry.test.ts`.
  *Contract:* `push_failed` is a new, additive `ok: false` variant. Native
  binaries from before it treat any unknown `ok: false` as a failed round
  and retry with backoff, which is exactly what they did for the throw, so
  no `minSupportedVersion` bump is needed.
- **Agent tools.** `agent/tools.ts:execute` still records `fail()` results
  itself (those return normally, so they commit). Throws are recorded by its
  caller, the `agent/runner.ts` action, via
  `internal.telemetry.mutations.recordAgentToolErrorInternal`, best effort.
- **Agent turn.** Already outside any transaction (an action calling
  `ctx.runMutation`), so it records directly.

**Coverage gaps from WAL-203, and what WAL-216 decided** (each one resolved
or an explicit decision):

- **Unauthenticated push — recorded on the client.** `requireAuth` still
  throws before `push` can record anything, and stays a throw: turning it
  into a returned value would change how clients detect an expired session.
  Native records it as `sync.push.client_failures.count{reason="auth_failure"}`
  (`sync_engine.dart:_sendChunk`). *Caveat, not yet verified:* the
  classification compares the error message to `'Unauthenticated'`, and
  `requireAuth` throws a plain `Error`. If production redacts plain-error
  messages, prod `auth_failure` lands in `unknown`, for push and for the
  existing pull classification alike (checklist row 11).
- **Push failures the backend never sees — recorded on the client**, in the
  same separate metric: `network` is the client's own transport errors
  (`OperationTimeoutError`, `ConnectionLostError` from `lib/convex/`), anything
  else is `unknown`. Native's default `connectTimeout` is unset, so an offline
  push waits for the socket instead of failing; `network` therefore mostly
  means the operation timeout after the push was sent.
- **Reason for thrown tool errors — resolved.** `execute` rethrows malformed
  arguments (zod `.parse` failures and unparseable `argsJson`) as a
  `ConvexError` with `kind: 'agent_tool_error'`, `reason: 'invalid_args'`
  (`agent/helpers.ts`), so the rollback is unchanged and the reason survives
  the `runMutation` boundary. Any other throw is still `unknown`, which now
  means "a bug or an outage", not "anything".
- **Tool error rate — resolved.** `agent.tool.calls.count` is the
  denominator.
- **Pull errors in Grafana — still not validated** (checklist row 2). Needs a
  device; tracked as pending evidence, not new code.
- **WhatsApp-only paths — still not validated on preview** (rows 3, 6, 14).
  Tertiary priority, unchanged.
- **Web telemetry client — resolved.** `apps/web/src/lib/telemetry.ts` (parity
  with native's `TelemetryClient`), wired for voice connect and time to first
  response in `hooks/use-voice.ts`. Web has no local sync engine, so the sync
  metrics stay native-only by construction.

### Starter PromQL

**Names.** Every counter lands in Mimir with a `_total` suffix once OTLP is
normalized to Prometheus names — `system.function.duration_bucket_count` →
`system_function_duration_bucket_count_total` (observed in Grafana Cloud on
2026-09-30).

**Scope.** Every query filters on `deployment_environment="$Scope"`
(`production`, `development-3`, or `preview` for every PR preview — see
[`promql.md`](./promql.md#scope)). Without it, dev and preview traffic
pollutes production numbers.

**Function.** These counters are sparse, one sample per event, so
`increase()` extrapolates: it inflates, returns fractions, or shows
"No data" when a window has fewer than two samples — exactly the events you
fire to validate a panel ([`promql.md`](./promql.md#increase-miente-acá)).
Counts use `count_over_time`, which counts samples, and is exact as long as
each event is one exported row with its own `receivedAt`. That holds today:
backend metrics are one insert per event, and native `trackMetric` sends one
metric per request. `[$__range]` makes the dashboard time picker decide the
window; replace it with a literal (`[1h]`) when querying outside Grafana.

Sync errors by direction and reason:

```promql
sum by (direction, reason) (count_over_time(sync_errors_count_total{deployment_environment="$Scope"}[$__range]))
```

Push error rate — exceptions over attempts. Rejections (`cursor_mismatch`,
`client_outdated`) are excluded on purpose; `or vector(0)` turns "no errors"
into 0 instead of an empty result:

```promql
(sum(count_over_time(system_function_duration_bucket_count_total{deployment_environment="$Scope", function="sync_push", status="error"}[$__range])) or vector(0))
/ sum(count_over_time(system_function_duration_bucket_count_total{deployment_environment="$Scope", function="sync_push"}[$__range]))
```

Push outcomes (ok / rejected / error), for the same window:

```promql
sum by (status) (count_over_time(system_function_duration_bucket_count_total{deployment_environment="$Scope", function="sync_push"}[$__range]))
```

Agent tool errors by tool:

```promql
sum by (tool_name, reason) (count_over_time(agent_tool_errors_count_total{deployment_environment="$Scope"}[$__range]))
```

Latency distribution per instrumented function (bucketed, not a true
percentile):

```promql
sum by (function, bucket) (count_over_time(system_function_duration_bucket_count_total{deployment_environment="$Scope"}[$__range]))
```

Push calls that threw on the client (separate from push outcomes above):

```promql
sum by (reason, platform) (count_over_time(sync_push_client_failures_count_total{deployment_environment="$Scope"}[$__range]))
```

Tool error rate per tool (`or (... * 0)` keeps tools with calls and no
errors in the result):

```promql
(sum by (tool_name) (count_over_time(agent_tool_errors_count_total{deployment_environment="$Scope"}[$__range])) or (sum by (tool_name) (count_over_time(agent_tool_calls_count_total{deployment_environment="$Scope"}[$__range])) * 0))
/ sum by (tool_name) (count_over_time(agent_tool_calls_count_total{deployment_environment="$Scope"}[$__range]))
```

p50/p95/p99 with the sample count beside them (gauges, so the latest hourly
snapshot, read with `last_over_time` over a lookback longer than the cron
period). **The Prometheus name of the `ms` gauge is a hypothesis until
checklist row 12 confirms it:** standard OTLP translation appends the unit
(`ms` → `_milliseconds`), the way `business.users.registered_total` gained
`_count`:

```promql
max by (batch_size, quantile) (last_over_time(system_latency_quantile_ms_milliseconds{deployment_environment="$Scope", operation="sync_push", window="24h"}[2h]))
max by (batch_size) (last_over_time(system_latency_samples_count{deployment_environment="$Scope", operation="sync_push", window="24h"}[2h]))
```

Voice connect and time to first response:

```promql
sum by (bucket, resumed) (count_over_time(voice_connect_setup_complete_bucket_count_total{deployment_environment="$Scope"}[$__range]))
```

```promql
sum by (mode, bucket) (count_over_time(agent_response_first_token_bucket_count_total{deployment_environment="$Scope"}[$__range]))
```

### Grafana validation checklist

To be run with the `walletbot-metrics-doctor` skill
(`.agents/skills/walletbot-metrics-doctor/`) against the PR preview backend.
The query script evaluates instant queries, so `[$__range]` is replaced by
an explicit window covering the trigger. **Nothing below counts as validated
until its evidence column holds an observed result**; code review alone
doesn't count.

Environment for every row: PR #296 preview backend and the staging APK built
from the same commit. The preview deployment name changes between deploys
(the sticky "Mobile staging APK built" comment on the PR names the current
one), so record it next to each piece of evidence. `deployment_environment`
is `preview` for every PR preview, so check sample timestamps against the
trigger time, not just presence.

| # | Metric | How to trigger | Query (window = since trigger) | Expected | Evidence |
|---|---|---|---|---|---|
| 1 | Sync errors (push) | Convex dashboard function runner on the preview: `v1/sync/mutations:push` with "Act as a user" (`subject` = your user id, `issuer` = `https://<deployment>.convex.site/native-auth`). (a) `expectedServerSeq` ≠ current counter → `cursor_mismatch`; (b) `appVersion: "0.2.0"` → `client_outdated`; (c) current counter + a movement whose `currency` differs from its account → `validation`. Two real devices don't reproduce (a) reliably: native pulls right before every push, so a mismatch needs a write to land in that gap | `sum by (direction, reason, platform) (count_over_time(sync_errors_count_total{deployment_environment="preview"}[2h]))` | one `direction="push"` sample per run with the matching `reason`, `metric_source="backend"`; (c) also leaves the counter unchanged and no movement written | ✅ 2026-10-03, `unique-rabbit-836`, window `[2h]`: `client_outdated` 1, `validation` 1, `cursor_mismatch` 2 (one without a `platform` label — most likely a run with `platform: ""`, whose empty label is dropped; not confirmed). Rollback after (c): `syncCounters.value` unchanged in the dashboard (confirmed); absence of the test movement not checked — covered by `pushTelemetry.test.ts` |
| 2 | Sync errors (pull) | Sign the device out server-side (or let the session expire) while it syncs → `auth_failure`; airplane mode mid-pull → `unknown` | same query, `direction="pull"` | ≥1 sample with the matching reason, `metric_source="native"` | **Not tested** in this round |
| 3 | Tool errors | WhatsApp only — not reachable from the preview | `sum by (tool_name, reason) (count_over_time(agent_tool_errors_count_total{deployment_environment="preview"}[1h]))` | — | **Not verifiable on preview** |
| 4 | `sync_push` duration | Edits on the APK plus the row 1 runs | `sum by (status, bucket) (count_over_time(system_function_duration_bucket_count_total{deployment_environment="preview", function="sync_push"}[2h]))` | one sample per call; status matches the outcome; not every sample in `0-100` | ✅ 2026-10-03, `unique-rabbit-836`, window `[2h]`: `ok` 5 (4 in `0-100`, **1 in `100-250`** — impossible with the old frozen clock, which always measured 0), `rejected` 3 (= 2 `cursor_mismatch` + 1 `client_outdated`), `error` 1 (= the `validation` run) |
| 5 | `sync_pull` duration | Open the app / pull to refresh | same, `function="sync_pull"` | ≥1 sample per sync round, `metric_source="native"` | ✅ 2026-10-03, `unique-rabbit-836`, window `[2h]`: 11 `ok` samples (`100-250` 2, `250-500` 8, `500-1000` 1), `app_version="1.0.0+1"`. Every build reports that version (`AppConfig.appVersion` is a hardcoded constant — WAL-215), so the exact APK commit can't be told apart from the data |
| 6 | `agent_turn` duration | WhatsApp only | same, `function="agent_turn"` | — | **Not verifiable on preview** |
| 7 | Voice connect | Start a voice session on the APK | `sum by (bucket, resumed) (count_over_time(voice_connect_setup_complete_bucket_count_total{deployment_environment="preview"}[2h]))` | 1 sample per connect, `resumed="false"` on a fresh one | ✅ 2026-10-03, `unique-rabbit-836`, window `[2h]`: 1 sample, `500-1000`, `resumed="false"` |
| 8 | First response, text | Send a typed message to the agent | `sum by (mode, bucket) (count_over_time(agent_response_first_token_bucket_count_total{deployment_environment="preview"}[2h]))` | 1 `mode="text"` sample per message | ✅ 2026-10-03, `unique-rabbit-836`, window `[2h]`: 1 `mode="text"`, `2500-5000` |
| 9 | First response, voice | Speak a turn | same query | 1 `mode="voice"` sample per turn | ✅ 2026-10-03, `unique-rabbit-836`, window `[2h]`: 1 `mode="voice"`, `2500-5000` |

| 10 | Push client failures | APK on the WAL-216 preview: airplane mode while a push is in flight (≥ the 30s operation timeout) → `network`; revoke the session server-side, then edit → `auth_failure` | `sum by (reason, platform) (count_over_time(sync_push_client_failures_count_total{deployment_environment="preview"}[2h]))` | 1 sample per failed push call with the matching `reason`, `metric_source="native"`; none for a push that returned `ok: false` | **Pending** |
| 11 | `auth_failure` classification | Same as row 10, auth case | same | `reason="auth_failure"`, not `unknown` — confirms the `'Unauthenticated'` message survives on the deployment | **Pending** |
| 12 | Latency gauges | Edits on the APK (WAL-216 preview), then `pnpm -C packages/backend exec convex run telemetry/mutations:recordLatencyPercentiles` instead of waiting for the hourly cron | `--series-days 1 '{__name__=~"system_latency.*"}'`, then the panel queries | the exact `quantile` series name (fix the dashboard and this doc if it isn't `system_latency_quantile_ms_milliseconds`); `samples_count` = applied pushes | **Pending** |
| 13 | First response percentiles | Text and voice turns while signed in, then force the snapshot as in row 12 | `max by (mode, quantile) (last_over_time(system_latency_quantile_ms_milliseconds{deployment_environment="preview", operation="agent_first_response"}[2h]))` | `mode="text"` / `"voice"` / `"all"` rows; still exactly one `agent_response_first_token_bucket_count_total` sample per turn | **Pending** |
| 14 | Tool calls | WhatsApp only | `sum by (tool_name) (count_over_time(agent_tool_calls_count_total{deployment_environment="preview"}[1h]))` | — | **Not verifiable on preview** |
| 15 | Web first response and connect | A web voice session on the WAL-216 preview | rows 7–9 queries with `platform="web"` | samples with `metric_source="web"` | **Pending** |

Attribution: `deployment_environment="preview"` is shared by every PR
preview, but these metrics only exist on this branch, and before
2026-10-03 no `sync_errors_count_total` series existed at all. Avoid
`timestamp(last_over_time(...))` to date a sample: it returns the
evaluation time, not the sample's.

Before reading an empty result as "not emitted", confirm the series name
with `query.py --series-days 14 '{__name__=~"<prefix>.*"}'` — an instant
query can be empty while the series exists.

Note these bucketed counters are a distribution shape, not a true cumulative
Prometheus histogram — `histogram_quantile()` doesn't apply to them. If an
exact p95 is needed before the Option E traces work lands, use Option D
(`@convex-dev/aggregate` keyed by `duration_ms`, queried with `.at(rank)`)
instead, which gives an exact percentile from inside Convex without going
through Grafana at all. See "Path to p50/p95/p99" below for how to get there
without redoing what's already implemented.

## Answering the ticket's open questions directly

- **Traces (DB calls, external API calls, not just total time)?** Not in this
  iteration. We're not paying for Log Streams, which is the only way Convex
  gives that breakdown for free/automatically. Getting it any other way means
  hand-rolling spans (Option E, see above) around the specific sub-operations
  we suspect are slow, exported to Grafana Tempo's free tier (50GB/month).
  That's real engineering work (new outbox table, new OTLP payload shape,
  trace/span id propagation through nested `ctx.run*` calls — none of which
  exists today), so v1 ships **total** latency per instrumented call only,
  and we build spans later, targeted at whatever the total-latency numbers
  point at.
- **Discriminate by endpoint?** Yes, at the granularity we choose to
  instrument: the `function`/`direction`/`tool_name` labels above scope every
  metric by call site, same principle Log Streams' `function.path` would have
  given us for free — we just have to name each site by hand instead of
  getting all ~98 automatically.
- **Is Sync healthy?** Partially answerable now. Push and pull each record
  one duration sample per attempt with an `ok`/`rejected`/`error` status, so
  "X% of pushes failed" is a query (see "Starter PromQL"), with the coverage
  gaps listed in "Emitters and coverage". Not yet answered: whether sync
  *converges correctly* after failures — see "Next iteration".

## Path to p50/p95/p99 (option 1 built in WAL-216)

The ticket that opened this spike explicitly asked for p50/p95/p99 latency
and an error *rate*. What shipped in this iteration (Option A,
bucketed counters) deliberately does not provide either — this section
documents why, and how to iterate from what exists into a version that does,
without discarding it.

**Why the current implementation can't produce real percentiles.**
`system.function.duration_bucket_count` and the other `*_bucket_count`
metrics are the same "poor-man's histogram" trick as
`agent.session.cost_bucket_count`: pick a bucket label from the raw value,
then increment a plain Prometheus counter. `histogram_quantile()` requires a
true cumulative histogram — several series sharing an `le` ("less than or
equal") label, where each bucket's count includes every lower bucket. Ours
are **exclusive** ranges (`'100-250'` counts only that range), so
`histogram_quantile()` either errors or returns nonsense against this data.
You can eyeball "most `sync_pull`s land in 100–250ms" from the resulting bar
chart, but there is no mathematically real p95 hiding in it.

**Error rate.** For sync, the duration samples double as the attempt count
(one per call, with a status), so push and pull already have a rate.
`agent.tool.errors.count` still has no denominator: there is no "tool calls
attempted" counter, so tool errors are a trend on absolute volume only.

**Two iteration paths, from the exact call sites already instrumented today**
(`v1/sync/mutations.ts:push`, `whatsapp/nodeActions.ts:runAgentTurn`,
`agent/tools.ts:execute`) — the raw `durationMs`/error is already computed at
each of these before it gets reduced to a bucket label or a plain counter
increment, so nothing already recorded needs to be thrown away to pursue
either path:

1. **`@convex-dev/aggregate` (Option D), additive.** Insert `durationMs` into
   an aggregate keyed by `function` (and optionally a time window) at the
   same call sites, *alongside* the existing bucketed counter — the bucketed
   counters keep feeding today's distribution-shape panels unchanged. Add a
   cron (same shape as the existing `business.users.registered_total` /
   `agent.user.monthly_cost_usd` scheduled gauges) that periodically reads
   `.at(rank)` from the aggregate and exports the result as a **gauge**
   metric (e.g. `system.function.duration_p95_ms{function="sync_pull"}`)
   through the OTLP pipeline that already works. This gets a real p95 into
   Grafana as a periodic snapshot (matching the existing 5–15 min export
   cadence) rather than a live-queried histogram, which is enough for an ops
   dashboard. Purely additive: new component, new cron, one new line at each
   of the 3 existing call sites — nothing already shipped changes.
2. **A real OTLP histogram, not additive.** Would replace the bucketed
   counters for these metrics rather than run beside them. Requires
   implementing the histogram branch `toOtlpMetricsPayload`
   (`telemetry/actions.ts`) doesn't have today — `MetricType` already
   includes `'histogram'` in the type system, but a metric typed that way
   currently silently exports as a plain counter. Also requires switching
   from exclusive-range buckets to real cumulative `le` boundaries, which is
   a different accumulation model than `telemetryMetricSeries`'s
   independent-counter-per-attribute-combination shape (closer to a single
   document holding a bucket-count array that gets read-modified-written).
   Real, separate engineering effort — not a follow-up task, a small project.

**Recommendation if/when this becomes a priority:** Path 1, plus a tool-call
attempts counter for a true tool error rate (sync already has one). Both are
additive to what's merged in this PR; Path 2 is a deliberate,
separate scope decision, not an extension of Option A.

### What WAL-216 built (Path 1)

- **Source.** A `latencySamples` table (raw `durationMs`, `recordedAt`) and a
  `latencyByOperation` `DirectAggregate`, namespaced
  `${operation}:${segment}` and keyed by duration, so `.at(rank)` is a
  percentile. Every sample goes in twice: under its own segment and under
  `all` (`telemetry/latency.ts`).
- **Segments.** `sync_push` by **batch size** (rows in the batch, counted the
  way native sizes a chunk: `0-1`, `2-10`, `11-40`, `41-80`, `81+`; native
  caps a chunk at 80). `agent_first_response` by `mode` (`text`, `voice`).
- **What is sampled.** `sync_push`: only applied batches (`status: ok`).
  Rejections and errors never applied a batch, and they already have their
  own counters. First response: only **authenticated** requests, since the
  endpoint also accepts anonymous metrics (R-011) and an anonymous caller must
  not be able to move the p99. A signed-out local account therefore feeds the
  bucket counter but not the percentiles.
- **Writes off the hot path.** The aggregate is shared by every user, so the
  sample is written by a scheduled mutation
  (`telemetry/mutations:recordLatencySample`), never inside the push
  transaction: unrelated users' pushes can't conflict on telemetry.
- **Window.** Rolling 24h. `delete expired latency samples` runs every 15
  minutes (and continues itself while a batch comes back full), so a
  snapshot can include up to 15 extra minutes.
- **Export.** `record latency percentiles` runs hourly: nearest-rank p50, p95
  and p99 as `system.latency.quantile_ms`, plus `system.latency.samples_count`
  for every segment. The count is exported even when it is 0, and the
  percentiles are skipped when it is, so "no traffic" and "no data" stay
  distinguishable. Panels: "Latencia (p50/p95/p99)" in the main dashboard.
- **Not changed.** The bucketed counters keep feeding the distribution
  panels. Time to first response is now sent raw by clients
  (`agent.response.first_token_ms`), and its bucket counter is derived at
  ingest, so each turn is still exactly one bucket sample.

## Prerequisites / follow-up work (not yet created as Linear tickets)

1. ✅ **Done.** Small closed error-code enum at the sync push/pull throw
   sites (`SyncValidationError`) and agent tool-call catch sites (a `reason`
   field on `fail()`/`unresolved()`, stripped before the result reaches the
   model).
2. ✅ **Done.** `sync.errors.count` + `agent.tool.errors.count` counters,
   wired at those sites, plus catalog/validator entries. Errors that throw
   are recorded outside the failing transaction (see "Emitters and
   coverage"); the first version recorded them inside it, where the rollback
   discarded them. An earlier draft of this doc called both "confirmed
   exporting"; a series lookup on 2026-10-03 (14-day window, which covers
   that test) found **no `sync_errors_count_total` or
   `agent_tool_errors_count_total` series at all** — only the duration,
   voice-connect and first-response series exist, all in `preview`. Neither
   error counter has been observed in Grafana yet; the "Grafana validation
   checklist" is the source of truth. WhatsApp-only paths remain unverified.
3. ✅ **Done.** `system.function.duration_bucket_count`: times sync `push`
   (backend, mutation, with `performance.now()` — `Date.now()` is frozen
   inside a mutation and always measured 0), and — because `pull` is a Convex **query**
   and structurally cannot write telemetry itself (no `ctx.db`/scheduler) —
   `sync_pull`'s duration is instead reported from the native client
   (`sync_engine.dart`), source `'native'` instead of `'backend'`, and
   includes the download plus the local apply. Also times
   `agent_turn` (the model+tools loop only, not queue/gate time). Total
   latency only, no DB/API breakdown, as scoped.
4. ✅ **Done.** Redirected native's existing connect-phase `Stopwatch` into
   `voice.connect.setup_complete_bucket_count`; added a
   time-to-first-response timer (`agent.response.first_token_bucket_count`).
5. ✅ **Done (WAL-216).** Web telemetry client (`apps/web/src/lib/telemetry.ts`),
   wired for voice connect and time to first response.
6. **Deferred, not this iteration:** hand-rolled OTLP traces (Option E) —
   new `telemetrySpans` outbox + exporter, targeted at whatever #3 points at
   as slow. Revisit once total-latency data exists to point at something.
7. ✅ **Done (WAL-216).** Real p50/p95/p99 (Path 1) and a tool error rate
   (`agent.tool.calls.count`) — see "What WAL-216 built".

Two things surfaced only after implementing and testing against a real
Grafana Cloud stack, not knowable at spike time: every counter above exports
with a `_total` suffix (standard OTel→Prometheus convention, see "Starter
PromQL"), and these are sparse one-shot pushes, not scraped series. The
first draft of this doc concluded that `increase()` just needed a wide
window; that was wrong — on sparse series `increase()` extrapolates and
miscounts at any window, so counts use `count_over_time` instead (see
[`promql.md`](./promql.md)).

## Next iteration

Goals for the report, all building on what this PR records:

1. **Backend error rate for applying sync batches**, with successes,
   rejections and exceptions each counted correctly. This PR gets the
   counting right for push; the remaining gap is the unauthenticated case
   and clean dashboard panels.
2. **p50/p95/p99** for backend batch application (`sync_push`) and for time
   to first agent response, stating the window and sample count next to
   every percentile, and taking **batch size** into account — an 80-row
   batch and a 1-row batch aren't the same operation, so batch size needs to
   become a label (bucketed) or a separate dimension in the percentile
   source. See "Path to p50/p95/p99".
3. **Sync correctness and recovery tests** — that sync converges after
   `cursor_mismatch`, retries and failed batches — alongside its timings and
   errors.

Voice connect timing stays, but isn't a report goal. WhatsApp coverage is
tertiary. Distributed traces aren't required for any of the above.

**Status after WAL-216:**

1. Push error rate and outcome panels are in the main dashboard ("Salud
   operativa"), with the queries from "Starter PromQL". Checked against the
   WAL-203 preview data on 2026-10-03, window `[7d]`, scope `preview`: rate
   `0.1` (1 `error` / 10 attempts), outcomes `ok` 6, `rejected` 3, `error` 1.
   This shows the queries work, not that the dashboard was imported.
2. p50/p95/p99 built (see "What WAL-216 built"). Grafana evidence pending
   (checklist rows 12–13).
3. Sync correctness and recovery tests:
   - Backend (`convex/sync/convergence.test.ts`): applies after a
     `cursor_mismatch` and drain; a batch re-sent after a lost ack converges
     without duplicates; a bad batch fails the same way on every retry and
     leaves nothing; a corrected batch applies at the same cursor.
   - Native (`test/sync/sync_engine_convergence_test.dart`): drives the real
     `SyncEngine` through `cursor_mismatch`, a returned `push_failed`, a
     thrown push (`auth_failure`, `unknown`, `network`) and the 5-round
     mismatch limit.
   - **Finding, not fixed (needs a decision):** after 5 consecutive
     `cursor_mismatch` rounds, `_runOnce` takes the success path. It
     reports `synced`, writes the heartbeat and schedules no retry, while the
     rows are still dirty. They are pushed on the next trigger (a local
     write, a counter advance, a reconnect, a manual sync). The native test
     pins this behaviour as it is.

## Related risks

Touches existing entries in [`riesgos.md`](../riesgos.md): R-011 (unauth'd
`/telemetry/metrics` — new error/latency metrics stay behind the same
catalog+validator gate), R-024 (label cardinality discipline — the codes
above are deliberately small closed sets), and R-027 (which already names
"registrar un contador interno" as the next step once health/traces metrics
exist — `sync.errors.count`/`agent.tool.errors.count` are that next step).
No new risk entry needed at the spike stage; revisit once something here is
actually implemented. WAL-216 review: R-011 is unchanged, and percentiles
only take authenticated samples so the anonymous path can't skew them.
R-024 is unchanged: every new label is a closed set, and no user identifier
is exported. R-026 is updated: web now has a `TelemetryClient`.
