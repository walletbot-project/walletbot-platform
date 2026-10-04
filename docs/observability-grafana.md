# Grafana Cloud Observability Setup

**Instance:** <https://fearlesspillar2602.grafana.net> (org access required)

| Dashboard | |
| --- | --- |
| Accounts created by auth method | <https://fearlesspillar2602.grafana.net/d/geb465q/user-accounts-created-by-auth-method?var-Scope=production> |

The link keeps `var-Scope=production` because the scope actually selects the
data; the time range and panel state are left off on purpose so it opens on the
dashboard's own defaults rather than someone's saved window.


## Goal

Send WalletBot business metrics to Grafana Cloud through OTLP HTTP.
`telemetryMetrics` is only a short-lived outbox: it stores, retries, and cleans
exports, while Grafana/Mimir is the dashboard source.

## Convex Environment Variables

In Grafana Cloud:

1. Open the Grafana Cloud stack.
2. Go to `Connections` / `Add new connection`.
3. Search for `OpenTelemetry`.
4. Generate a token and copy the OTLP values from the tile.

Configure Convex:

```sh
OTEL_SERVICE_NAME=walletbot-backend
WALLETBOT_ENV=production
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=production,service.namespace=walletbot,service.version=1.0.0
OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp-gateway-<REGION>.grafana.net/otlp
OTEL_EXPORTER_OTLP_HEADERS=Authorization=Basic <TOKEN>
```

Notes:

- Use the exact endpoint shown by Grafana. The host can vary by region or stack
  age.
- With `OTEL_EXPORTER_OTLP_ENDPOINT`, the backend appends `/v1/metrics` for
  metrics and `/v1/logs` for events.
- The custom exporter sends OTLP/HTTP JSON, so
  `OTEL_EXPORTER_OTLP_PROTOCOL` is not required.
- If Grafana gives the header as `Authorization=Basic%20<TOKEN>`, it is valid:
  the backend normalizes `%20` to a space before sending.
- `deployment.environment` is attached to all exported OTLP logs and metrics as
  a resource attribute. Prefer setting it explicitly in
  `OTEL_RESOURCE_ATTRIBUTES`; otherwise the exporter falls back to
  `WALLETBOT_ENV`, `APP_ENV`, `NODE_ENV`, or `CONVEX_DEPLOYMENT`.
- A full signal-specific endpoint is also supported:

```sh
OTEL_EXPORTER_OTLP_METRICS_ENDPOINT=https://otlp-gateway-<REGION>.grafana.net/otlp/v1/metrics
```

### Preview (PR staging) deployments

Every PR preview (`create-staging-web`/`create-staging-mobile` labels,
`.github/workflows/preview-deploy.yml`) is a brand-new, empty Convex
deployment — it has none of production's env vars, so the exporter always
no-ops with `OTEL_EXPORTER_OTLP_ENDPOINT not configured` unless configured.
The `web` job's "Set backend preview OTLP export env vars" step sets this
automatically, pointed at the **same Grafana Cloud stack as production** (no
second stack to provision) via two dedicated GitHub Actions repo secrets:

- `OTEL_EXPORTER_OTLP_ENDPOINT_PREVIEW`
- `OTEL_EXPORTER_OTLP_HEADERS_PREVIEW`

These are separate from any production credential — same split as
`JWT_PRIVATE_KEY_PREVIEW`/`JWKS_PREVIEW` already use, so a leaked/misused
preview credential can't be used against production. In Grafana Cloud,
create a second OTLP access policy/token scoped to metrics write only (same
`Connections` → `OpenTelemetry` flow as the production setup above), and add
its endpoint/headers as those two secrets.

The step also sets `OTEL_RESOURCE_ATTRIBUTES` with
`deployment.environment=preview`, so preview data lands as its own series —
filter it out of production dashboards/PromQL with
`deployment_environment="production"` (or filter it in, to look at a
specific preview). If the secrets aren't set yet, the step warns and skips
rather than failing the staging deploy.

## Expected Metrics

Grafana/Mimir often normalizes OTLP metric names to Prometheus-style names, so
dots may appear as underscores.

- `business_financial_accounts_created_count`
- `business_user_accounts_created_count`
- `business_movements_created_count`
- `business_transfers_created_count`
- `business_users_registered_total`
- `business_user_accounts_signed_in_count`
- `agent_sessions_started_count`
- `agent_session_cost_usd`
- `agent_interaction_cost_usd`
- `agent_user_monthly_cost_usd`
- `agent_interactions_completed_count`
- `agent_session_cost_bucket_count`

Useful labels:

- `created_by`
- `ingest_path`
- `auth_method`
- `client_platform`
- `movement_type`
- `cross_currency`
- `model`
- `mode`
- `cost_source`
- `user_hash`
- `month`
- `interaction_type`
- `start_kind`
- `cost_bucket`
- `deployment_environment`
- `service_namespace`
- `service_name`

## Starter PromQL

> **`increase()` lies at low volume.** These counters are cumulative and only
> get a sample when an event actually happens. `increase(v[w])` is
> `rate(v[w]) * w`, and `rate()` extrapolates to the edges of the window, so a
> handful of events clustered inside a much wider window gets projected across
> all of it — three movements reported as `40.9` — and the result is fractional
> rather than a count. Worse, `increase()` needs at least two samples in the
> window, so sparse series return **no data at all** instead of a number.
>
> Count the samples instead: `count_over_time(v[$__range])`, which is what the
> panels in `docs/dashboards/` do. Every event produces exactly one exported
> row, and every row becomes one OTLP data point stamped with its own
> `receivedAt`, so counting samples is counting events — exact, integer, and
> genuinely scoped to the picked range, so 24h answers for 24h and 6h answers
> for 6h. Per bucket over time, the same function against `[$__interval]`.
>
> This holds only while one event is one sample. Rows exported in a single HTTP
> request share a `receivedAt`, so same-series events emitted inside one
> mutation would collapse into one data point. Today nothing does that:
> movements are recorded one mutation per movement and sessions one per open.
> A future bulk path that emits several of the same counter at once would need
> distinct timestamps, or this undercounts.
>
> Two alternatives, each with a catch: `max_over_time(v[w]) - min_over_time(v[w])`
> is exact and window-scoped but misses the increment that produced the first
> sample in the window; `last_over_time(v[$__range])` reads the running total,
> which is exact but answers "how many ever", not "how many in this window".
>
> The queries below keep `increase()` because they are written for a busy
> deployment, where samples are dense enough that the extrapolation is
> negligible. On dev, or on any low-traffic series, prefer `count_over_time`.

Movements created per minute:

```promql
sum(rate(business_movements_created_count[5m]))
```

Movements by type:

```promql
sum by (movement_type) (increase(business_movements_created_count[1d]))
```

Cross-currency transfers:

```promql
sum by (cross_currency) (increase(business_transfers_created_count[1d]))
```

Financial accounts by source:

```promql
sum by (created_by) (increase(business_financial_accounts_created_count[1d]))
```

User accounts by auth method:

```promql
sum by (auth_method) (increase(business_user_accounts_created_count[1d]))
```

Writes by ingestion path:

```promql
sum by (ingest_path) (increase(business_movements_created_count[1d]))
```

Registered users total:

```promql
last_over_time(business_users_registered_total[24h])
```

Sign-ins by auth method and client:

```promql
sum by (auth_method, client_platform) (increase(business_user_accounts_signed_in_count[1d]))
```

Agent sessions opened, new vs resumed:

```promql
sum by (start_kind) (count_over_time(agent_sessions_started_count_total[$__range]))
```

The counter is emitted where a session begins (the client's session
repository), not where its token is minted: a mint also happens on every
reconnect and on the voice screen's speculative prefetch, so mints are not
sessions. `start_kind="new"` is a session that did not exist a moment before;
`start_kind="resumed"` is the same conversation picked up again through a live
resume handle. Only the native client emits it today — web has no telemetry
client yet, so web sessions are missing from this counter.

Sessions that never reported a cost (opened but produced no usage metadata):

```promql
sum(count_over_time(agent_sessions_started_count_total[$__range]))
  - sum(count_over_time(agent_session_cost_bucket_count[$__range]))
```

Every open is counted, resumed ones included: each is a connection episode that
should end with a cost report. The difference can go slightly negative at the
edges of a window, where a session's cost lands inside it and its open fell
outside.

Agent session cost p95:

```promql
quantile_over_time(0.95, agent_session_cost_usd[1d])
```

Monthly AI cost by user:

```promql
sum by (user_hash, month) (last_over_time(agent_user_monthly_cost_usd[7h]))
```

Agent interactions by type:

```promql
sum by (interaction_type, mode) (increase(agent_interactions_completed_count[1d]))
```

Agent sessions by cost bucket:

```promql
sum by (cost_bucket) (increase(agent_session_cost_bucket_count[1d]))
```

## Scheduled Business Gauges

`business.users.registered_total` is emitted every 6 hours by the Convex cron
`record registered users total`. It counts Better Auth users and exports a
gauge with the latest total registered accounts.

`agent.user.monthly_cost_usd` is emitted every 6 hours by the Convex cron
`record agent monthly usage`. It reads the current `agentUsageMonthly` rollup
and exports one gauge for each of the top 20 `user_hash + month + model + mode`
rows **per account scope** by monthly estimated cost (at most 40 rows).
The `account_scope` label distinguishes `local` from `remote`.

To force a refresh while testing, run the internal action from the Convex CLI:

```sh
pnpm -C packages/backend exec convex run telemetry/actions:recordRegisteredUsersTotalNow
```

To force the monthly AI cost snapshot:

```sh
pnpm -C packages/backend exec convex run telemetry/actions:recordAgentMonthlyUsageNow
```

To force a specific UTC month:

```sh
pnpm -C packages/backend exec convex run telemetry/actions:recordAgentMonthlyUsageNow '{"month":"2026-08"}'
```

Use `--prod` when forcing the production deployment:

```sh
pnpm -C packages/backend exec convex run --prod telemetry/actions:recordRegisteredUsersTotalNow
```

## Outbox Policy

`telemetryMetrics` remains a temporary buffer:

- business writes do not depend on Grafana availability;
- failed exports are retried every 15 minutes, up to 6 attempts;
- pending exports are retried every 5 minutes;
- exported metrics are deleted after 24 hours;
- dashboards should read from Grafana, not Convex.

If volume grows, move the buffer/export pipeline to Grafana Alloy or another
collector.

## Troubleshooting

If `/telemetry/metrics` returns `{"ok":true,"accepted":1}` but nothing appears
in Grafana, check the latest `telemetryMetrics` row in Convex:

- `exportStatus = pending`: wait for `exportPendingMetrics` or the 5-minute
  cron.
- `exportStatus = exported`: the payload reached Grafana; search for the
  Prometheus-normalized metric name with underscores.
- `exportStatus = failed`: inspect `lastExportError`.

Common failures:

- `status=401`: invalid `OTEL_EXPORTER_OTLP_HEADERS` or expired token.
- `status=404`: wrong OTLP endpoint or duplicated/missing path.
- `status=400` / `status=415`: Grafana rejected the OTLP payload format; use
  the response body included in `lastExportError`.
- `invalid temporality and type combination`: Grafana rejected a counter that
  was not sent as a cumulative monotonic OTLP `Sum`. The exporter keeps
  cumulative state in `telemetryMetricSeries`.
- `OTEL_EXPORTER_OTLP_ENDPOINT not configured`: env vars are not set in the
  Convex deployment running the action. On a PR preview, see "Preview (PR
  staging) deployments" above — most likely the
  `OTEL_EXPORTER_OTLP_ENDPOINT_PREVIEW`/`OTEL_EXPORTER_OTLP_HEADERS_PREVIEW`
  repo secrets aren't set yet.

The exporter also writes a structured `console.warn("telemetry export failed",
...)` without headers or tokens.

For manual tests, omit `timestamp` or use the current epoch milliseconds.
Old timestamps may export successfully but will not appear in Grafana's default
time range.

## Local account identities and AI usage (WAL-196)

`appUsers` records local accounts observed requesting an AI token. Each account
gets a random UUID (`localAccountId`) persisted with its native account entry,
separate from the on-device database ID. Existing accounts get that UUID once
on load. The stable `appUserId` is `local:<UUID>`; it is not an authenticated
`userId` and contains no name or financial data.

The parent is `device:<SHA-256(device:deviceId)>`. Despite its name, the existing
`ClientInfo.deviceId` is a random per-installation UUID stored under
`native_device_id` in secure storage, not a hardware identifier. It already
travels with live-token requests, so we reuse it instead of introducing another
ID or unifying it with telemetry's independent `telemetry_installation_id`.
That older telemetry ID continues to travel in telemetry envelopes but does
not determine account identity or grouping. The `unknown` fallback is rejected.

Two different local accounts created on one installation have different
`appUserId`s and the same `parentId`. Accounts originating on another installation
have a different parent. This represents a common installation of origin, not
proof of a common person or ownership. The parent is immutable after the first
successful registration: restoring an account elsewhere does not rewrite its
origin. Clearing secure storage or reinstalling may lose IDs (some platforms
retain secure storage across reinstalls); an unregistered restored account's
origin can only be the installation from which it first registers.

Registration happens in `/v1/live/token`, after the existing rate limit and
before minting the provider token, and is idempotent on reconnect. It is not
performed when a local account is created offline. Speculative token prefetch
may register an account even if a conversation is never started. Bookkeeping
failure does not block AI use; a later token request retries registration.
Metrics for missing/unregistered identities remain in ordinary telemetry but
do not enter the monthly rollup. Earlier lost costs are explicitly not recovered.

Anonymous interaction samples carry a separate `appUserId`. Only a registered
local identity may enter the rollup, and its parent is read from `appUsers`,
never trusted from a metric body. Authenticated requests always use the
server-verified user and ignore any supplied local identity. Native sessions
capture their local identity when created; late metrics after account switching
do not borrow another account's identity or bearer token. The registry provides
no authentication and no public listing, linking or deletion endpoints.

Samples and rollups carry explicit `actorType=local`, `actorKey`, `appUserId`, and
`parentId`. Local deduplication and monthly keys include the individual account,
not just its parent; siblings can reuse a sample ID without colliding. Remote
keys, hashes and authenticated queries stay unchanged, including historical
rows without actor fields. USD continues to be computed in the backend from
tokens. No financial accounts, transactions, categories, tags, filters, widgets,
memories or conversations are created by this identity/metrics path.

`appUsers` is an observation registry, not a synchronized inventory of active
accounts. Removing a local account does not remove its historical identity or
costs, and creating a new account generates a new UUID. There is no reactivation
flow. The schema separates stable `appUserId`, account type and optional
authenticated `userId`: a later promotion can link the same row while retaining
its origin. A local registration cannot downgrade a linked registered row.
Promotion, verification of that link, and merging historical costs are future
features; this PR does not implement them or register every Better Auth user.

Samples are retained for 90 days by the existing cleanup, so sample deduplication
is limited to that retention window. Monthly rollups and identity registry rows
currently have no automatic expiration. The raw telemetry buffer retains its
existing installation ID for up to 90 days (14 days for failed exports). No
historical anonymous backfill is performed.

Grafana receives only the existing 24-hex `user_hash` (the local account's hash),
`parent_hash` for its installation of origin, and `account_scope=local|remote`.
Raw user/account/device IDs are never metric labels. The account table shows the
parent hash so sibling accounts are recognizable. Both panels preserve `$Scope`
and `$model` and use a 25-hour lookback compatible with PR #284. Queries collapse
rank changes per account/model/mode before summing. Snapshots contain the top 20
rows **per scope**, at most 40 rows; they are not complete billing totals and a
single actor's model/mode breakdown may be partially represented.

Automated coverage includes sibling grouping, immutable origin, registration
before token mint, reconnect idempotency, missing identities, authenticated
isolation, old remote retries, month/model separation, OTLP pseudonyms, offline
UUID persistence and account-switch telemetry. To validate live, use AI with two
local accounts from the same installation, confirm separate samples and a shared
parent, force `telemetry/actions:recordAgentMonthlyUsageNow` in development, and
inspect both local accounts in Grafana. Live deployment validation remains to
be performed after deploying the branch.
