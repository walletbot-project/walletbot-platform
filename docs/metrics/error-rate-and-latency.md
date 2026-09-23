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
- **Convex Log Streams** (Pro plan, **$25/developer/month**) stream every
  function execution to Datadog/Axiom/PostHog/a custom webhook, and the event
  already includes `execution_time_ms`, `status: success|failure`,
  `error_message`, `function.path`, `request_id`, DB/storage/network I/O, and
  retry counts — i.e., exactly backend error-rate + latency-by-function, with
  **zero application code changes**, because Convex is already computing this
  for every call. Delivery is best-effort (buffered, can drop under load) —
  fine for a dashboard, not for billing. The free built-in **Health** page
  only shows deployment-wide failure % and cache hit rate, no per-function
  breakdown, so it doesn't answer "which function" on its own.
  [Docs](https://docs.convex.dev/production/integrations/log-streams/).

## Options

| # | Approach | What it covers | Extra DB writes | Engineering cost | Cash cost |
|---|---|---|---|---|---|
| A | Hand-rolled: extend `telemetryMetrics` with an error counter + bucketed-counter latency (reusing `cost_bucket_count`'s pattern), called explicitly from the ~10 places that matter (sync push/pull catch blocks, agent tool-call catch blocks) — **not** a blanket wrapper over all 98 functions | Whatever we instrument, at our label granularity | 1-2 extra rows per instrumented call (same order as today's business metrics) | Low-medium: no wrapper needed, no OTLP histogram engineering, but *does* need an error-code prerequisite at each site we touch | $0 |
| B | Convex Log Streams → Datadog/Axiom (or a small webhook forwarder reshaping into OTLP for Grafana) | Every function, error rate + p50/p95/p99 latency, automatically, deployment-wide | 0 (platform-level, not app data) | Low if we accept a second dashboard (Datadog/Axiom's own); medium if we insist on one pane of glass in Grafana (needs a forwarder) | $25/dev/month |
| C | Blanket `customQuery`/`customMutation`/`customAction` wrapper instrumenting all ~98 handlers, with true histogram export built into the OTLP exporter | Everything, uniformly | Highest — every single call gets extra writes | High: new wrapper pattern + migrate 98 handlers + build histogram bucket math the exporter doesn't have today | $0 |
| D | `@convex-dev/aggregate` (already used in `aggregates.ts` for `outflowsByAccount`/`inflowsByAccount`/`transactionsByTag`) keyed by `duration_ms` per function+window, queried with `.at(rank)` for exact percentiles | Exact p50/p95/p99 for whatever we insert into it, queryable from an internal dashboard/query — no Grafana export required | 1 write per sampled call | Medium — no export/outbox overhead, but percentiles live in Convex, not Grafana, so it doesn't fold into the existing "one Grafana dashboard" workflow | $0 |

## Recommendation

Do **not** try to instrument all 98 functions uniformly right now (Option C):
there's no wrapper today, errors aren't coded, and the exporter can't emit
real histograms — that's three prerequisites stacked on top of each other for
a spike whose deliverable is a direction, not a rewrite. Instead:

1. **Errors, targeted (Option A).** Add one new counter,
   `system.errors.count`, called explicitly at the handful of catch sites that
   actually answer an open question in the ticket — sync `push`/`pull` and
   agent tool-call failures. Before that, give those specific throw sites a
   small closed error code (a shared string union, not `ConvexError` — no
   precedent for it here and it'd be the only place using it) so the label
   stays low-cardinality instead of being free text. This directly answers
   "is Sync healthy?", which today it's impossible to answer without asking a
   user to reproduce the issue and read `debugPrint` output off their device.
2. **Backend latency: trial Convex Log Streams (Option B)** rather than build
   bucket-counter latency by hand for every function. It's $25/month for
   something we'd otherwise spend real engineering time approximating, it
   requires no code changes, and it already gives per-function p50/p95/p99 and
   error rate together. If routing it into Grafana (single pane of glass)
   turns out to need more forwarder glue than it's worth, fall back to
   Datadog/Axiom's own free dashboard as the "ops" view and keep Grafana for
   business metrics — two panes is an acceptable MVP tradeoff (we already
   accept a similar one for R-011).
3. **Client latency, native only for now.** Redirect the `Stopwatch` values
   `gemini_voice_expense_command.dart` already computes
   (`setup_complete`) into `trackMetric(..., type: 'histogram', unit: 'ms')`,
   and add one new start/end timer pair for time-to-first-response. Web needs
   its own telemetry client built first — track that as a separate ticket, it
   shouldn't block this spike's POC.
4. **Keep the bucketed-counter pattern** (`agent.session.cost_bucket_count`
   precedent) for any latency we *do* choose to hand-roll (e.g. the client
   metrics above, which never touch Convex Log Streams since that's
   backend-only) — it needs no exporter changes and is already proven in
   production.

## Proposed metrics

All new metric names follow the existing `<domain>.<subject>.<verb>_<unit>`
convention and would be added to `MetricName`/`metricCatalog` like any
existing metric.

| Name | Type | Unit | Labels | Source |
|---|---|---|---|---|
| `sync.errors.count` | counter | count | `direction` (`push`\|`pull`), `reason` (`client_outdated`\|`cursor_mismatch`\|`auth_failure`\|`validation`\|`unknown`), `platform` | backend |
| `agent.tool.errors.count` | counter | count | `tool_name` (bounded — existing tool registry), `reason` (`invalid_args`\|`not_found`\|`provider_error`\|`unknown`) | backend |
| `voice.connect.setup_complete_bucket_count` | counter | count | `bucket` (`0-250`\|`250-500`\|`500-1000`\|`1000-2500`\|`2500-5000`\|`5000+`), `platform`, `resumed` | native (later: web) |
| `agent.response.first_token_bucket_count` | counter | count | `bucket` (same shape as above), `mode` (`voice`\|`text`), `platform` | native (later: web) |

(If Option B is adopted, backend function latency/error-rate does **not**
need a `telemetryMetrics` entry at all — it comes from Log Streams directly.)

### Starter PromQL

Sync error rate by reason (last 5 min):

```promql
sum by (direction, reason) (increase(sync_errors_count[5m]))
```

Sync push/pull "is it healthy" single-stat (errors vs. attempts — pair with a
`sync.attempts.count` counter, or use Log Streams'
`convex.function.path="v1/sync/mutations:push"` if Option B is in place):

```promql
sum(rate(sync_errors_count{reason!="cursor_mismatch"}[15m]))
```

Agent tool error rate by tool:

```promql
sum by (tool_name, reason) (increase(agent_tool_errors_count[1d]))
```

Voice connect time distribution (bucketed, not a true percentile — see
limitation above):

```promql
sum by (bucket) (increase(voice_connect_setup_complete_bucket_count[1d]))
```

If Log Streams land in a Prometheus-compatible destination, per-function
p95 looks like the standard Convex/Datadog pattern:

```promql
histogram_quantile(0.95, sum by (le, function_path) (
  rate(convex_function_execution_time_ms_bucket[5m])
))
```

(exact metric name depends on the chosen forwarder/integration — confirm once
Option B is trialed.)

## Answering the ticket's open questions directly

- **Traces (DB calls, external API calls, not just total time)?** Not with
  our hand-rolled outbox — that would need real distributed tracing
  (spans/OTLP traces), which is a different signal from metrics and a bigger
  lift. Convex Log Streams' function-execution event *does* already break out
  DB/storage/network I/O per call, which gets us partway there without
  building tracing ourselves. Recommend revisiting real traces only if Log
  Streams' breakdown proves insufficient.
- **Discriminate by endpoint?** Yes, `function.path` is intrinsic to Log
  Streams (Option B); for the hand-rolled counters above, `direction`/
  `tool_name` already scope by call site.
- **Is Sync healthy?** Unknown today, and it can't become known without at
  least the `sync.errors.count` counter above — currently a permanent bug and
  a Wi-Fi blip are indistinguishable both to us and to the user.

## Prerequisites / follow-up work (not yet created as Linear tickets)

1. Small closed error-code enum at the sync push/pull throw sites (~10
   places) and agent tool-call catch sites — prerequisite for #2.
2. `sync.errors.count` + `agent.tool.errors.count` counters, wired at those
   sites, plus catalog/validator entries.
3. Trial Convex Log Streams on a dev deployment; decide Grafana-forwarder vs.
   second-dashboard based on how much glue the forwarder actually needs.
4. Redirect native's existing connect-phase `Stopwatch` into
   `trackMetric` (`voice.connect.setup_complete_bucket_count`); add a
   time-to-first-response timer.
5. Build a web telemetry client (parity with native) — prerequisite for any
   web-side latency metric.

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
