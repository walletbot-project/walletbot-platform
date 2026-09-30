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

1. **Errors, targeted (Option A).** Add one new counter,
   `system.errors.count`, called explicitly at the handful of catch sites that
   actually answer an open question in the ticket — sync `push`/`pull` and
   agent tool-call failures. Before that, give those specific throw sites a
   small closed error code (a shared string union, not `ConvexError` — no
   precedent for it here and it'd be the only place using it) so the label
   stays low-cardinality instead of being free text. This directly answers
   "is Sync healthy?", which today it's impossible to answer without asking a
   user to reproduce the issue and read `debugPrint` output off their device.
2. **Backend total latency, also Option A.** Time the same call sites we're
   already adding error counters to (sync `push`/`pull`, agent turn
   processing) end-to-end — one `Date.now()` at entry, one at the
   `try`/`catch`/`finally` exit — and bucket the elapsed ms into
   `system.function.duration_bucket_count` the same way
   `agent.session.cost_bucket_count` already buckets cost. This is a handful
   of call sites, not all 98 functions, and needs no exporter changes at all
   (it's a counter, like everything else in the outbox today). It answers
   "how slow is a sync round / an agent turn," which is most of what the
   ticket actually needs for v1 — it does **not** tell us whether a slow call
   was slow in the DB, in a `fetch` to Gemini, or in our own code, and that's
   an explicit, accepted gap for this iteration.
3. **Client latency, native only for now.** Redirect the `Stopwatch` values
   `gemini_voice_expense_command.dart` already computes
   (`setup_complete`) into `trackMetric(..., type: 'histogram', unit: 'ms')`,
   and add one new start/end timer pair for time-to-first-response. Web needs
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
convention and would be added to `MetricName`/`metricCatalog` like any
existing metric.

| Name | Type | Unit | Labels | Source |
|---|---|---|---|---|
| `sync.errors.count` | counter | count | `direction` (`push`\|`pull`), `reason` (`client_outdated`\|`cursor_mismatch`\|`auth_failure`\|`validation`\|`unknown`), `platform` | backend |
| `agent.tool.errors.count` | counter | count | `tool_name` (bounded — existing tool registry), `reason` (`invalid_args`\|`not_found`\|`provider_error`\|`unknown`) | backend |
| `system.function.duration_bucket_count` | counter | count | `function` (`sync_push`\|`sync_pull`\|`agent_turn` — the handful we instrument, not all 98), `bucket` (`0-100`\|`100-250`\|`250-500`\|`500-1000`\|`1000-2500`\|`2500-5000`\|`5000+`), `status` (`ok`\|`error`) | backend |
| `voice.connect.setup_complete_bucket_count` | counter | count | `bucket` (`0-250`\|`250-500`\|`500-1000`\|`1000-2500`\|`2500-5000`\|`5000+`), `platform`, `resumed` | native (later: web) |
| `agent.response.first_token_bucket_count` | counter | count | `bucket` (same shape as above), `mode` (`voice`\|`text`), `platform` | native (later: web) |

All four are total-duration/count signals — none of them break a call down
into DB time vs. external-API time vs. our own code. That breakdown is
explicitly deferred (see "Traces, eventually" above).

### Starter PromQL

**Confirmed against real Grafana Cloud/Mimir data (2026-09-30):** every
counter listed above lands with a `_total` suffix once OTLP normalizes it to
a Prometheus name — e.g. `system.function.duration_bucket_count` becomes
`system_function_duration_bucket_count_total`, not just
`system_function_duration_bucket_count`. This is standard OTel→Prometheus
convention for monotonic sums, not something specific to our exporter — it
almost certainly applies to every pre-existing business counter in
`docs/observability-grafana.md` too (that doc's PromQL predates this
verification and should be spot-checked against a real panel). The queries
below already include the suffix. Also confirmed: these are one-shot,
non-continuously-scraped pushes (one OTLP POST per event, not a periodic
scrape), so `increase()`/`rate()` need a wide window (`[1d]`, not `[5m]` or
`[1h]`) to reliably catch two samples — a short window reliably shows "No
data" even when the metric exists and exported fine.

Sync error rate by reason (last day):

```promql
sum by (direction, reason) (increase(sync_errors_count_total[1d]))
```

Sync push/pull "is it healthy" single-stat (errors vs. attempts — would need
a companion `sync.attempts.count` counter alongside `sync.errors.count` to
turn this into a rate rather than a raw error count):

```promql
sum(increase(sync_errors_count_total{reason!="cursor_mismatch"}[1d]))
```

Agent tool error rate by tool:

```promql
sum by (tool_name, reason) (increase(agent_tool_errors_count_total[1d]))
```

Voice connect time distribution (bucketed, not a true percentile — see
limitation above):

```promql
sum by (bucket) (increase(voice_connect_setup_complete_bucket_count_total[1d]))
```

Backend total-latency distribution per instrumented function, and its error
overlay:

```promql
sum by (function, bucket) (increase(system_function_duration_bucket_count_total[1d]))
```

```promql
sum by (function) (increase(system_function_duration_bucket_count_total{status="error"}[1d]))
/ sum by (function) (increase(system_function_duration_bucket_count_total[1d]))
```

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
- **Is Sync healthy?** Partially answerable now — `sync.errors.count` is
  implemented and confirmed exporting end-to-end (Grafana Cloud, 2026-09-30).
  Still a **count**, not a **rate**: without a `sync.attempts.count`
  denominator (not built, see "Prerequisites" below), you can see error
  volume trending but not "X% of syncs are failing."

## Path to p50/p95/p99 (not yet built)

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

**Why error counts aren't yet an error rate.** `sync.errors.count` and
`agent.tool.errors.count` have no attempts/total-calls denominator counter.
Rate = errors / attempts; without the denominator you only get a trend on
absolute volume.

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

**Recommendation if/when this becomes a priority:** Path 1, plus a
`*.attempts.count` counter at the same call sites for a true error rate.
Both are additive to what's merged in this PR; Path 2 is a deliberate,
separate scope decision, not an extension of Option A.

## Prerequisites / follow-up work (not yet created as Linear tickets)

1. ✅ **Done.** Small closed error-code enum at the sync push/pull throw
   sites (`SyncValidationError`) and agent tool-call catch sites (a `reason`
   field on `fail()`/`unresolved()`, stripped before the result reaches the
   model).
2. ✅ **Done.** `sync.errors.count` + `agent.tool.errors.count` counters,
   wired at those sites, plus catalog/validator entries. Confirmed exporting
   end-to-end against a real Grafana Cloud stack (2026-09-30) for the paths
   reachable outside WhatsApp; `agent.tool.errors.count` and the
   `agent_turn` case of item 3 remain untested in practice since they're
   WhatsApp-only and not reachable from an ephemeral PR preview.
3. ✅ **Done.** `system.function.duration_bucket_count`: times sync `push`
   (backend, mutation) end-to-end, and — because `pull` is a Convex **query**
   and structurally cannot write telemetry itself (no `ctx.db`/scheduler) —
   `sync_pull`'s duration is instead reported from the native client
   (`sync_engine.dart`), source `'native'` instead of `'backend'`. Also times
   `agent_turn` (the model+tools loop only, not queue/gate time). Total
   latency only, no DB/API breakdown, as scoped.
4. ✅ **Done.** Redirected native's existing connect-phase `Stopwatch` into
   `voice.connect.setup_complete_bucket_count`; added a
   time-to-first-response timer (`agent.response.first_token_bucket_count`).
5. Build a web telemetry client (parity with native) — prerequisite for any
   web-side latency metric. Not started.
6. **Deferred, not this iteration:** hand-rolled OTLP traces (Option E) —
   new `telemetrySpans` outbox + exporter, targeted at whatever #3 points at
   as slow. Revisit once total-latency data exists to point at something.
7. **Real p50/p95/p99 + a true error rate** — see "Path to p50/p95/p99"
   above. Not started; the ticket asked for this and Option A doesn't
   provide it, so treat it as its own scope decision rather than assuming
   it falls out of what's already shipped.

Two things surfaced only after implementing and testing against a real
Grafana Cloud stack, not knowable at spike time: every counter above exports
with a `_total` suffix (standard OTel→Prometheus convention, see "Starter
PromQL"), and these are sparse one-shot pushes, not scraped series, so
`increase()`/`rate()` need a wide window (`[1d]`, not `[5m]`) to reliably see
two samples.

I haven't created these in Linear yet — want me to file them once you've
reviewed the recommendation, or adjust scope first?

## Related risks

Touches existing entries in [`riesgos.md`](../riesgos.md): R-011 (unauth'd
`/telemetry/metrics` — new error/latency metrics stay behind the same
catalog+validator gate), R-024 (label cardinality discipline — the codes
above are deliberately small closed sets), and R-027 (which already names
"registrar un contador interno" as the next step once health/traces metrics
exist — `sync.errors.count`/`agent.tool.errors.count` are that next step).
No new risk entry needed at the spike stage; revisit once something here is
actually implemented.
