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

## Expected Metrics

Grafana/Mimir often normalizes OTLP metric names to Prometheus-style names, so
dots may appear as underscores.

- `business_financial_accounts_created_count`
- `business_user_accounts_created_count`
- `business_movements_created_count`
- `business_transfers_created_count`
- `business_users_registered_total`
- `business_user_accounts_signed_in_count`
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
- `cost_bucket`
- `deployment_environment`
- `service_namespace`
- `service_name`

## Starter PromQL

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
last_over_time(business_users_registered_total[25h])
```

Sign-ins by auth method and client:

```promql
sum by (auth_method, client_platform) (increase(business_user_accounts_signed_in_count[1d]))
```

Agent session cost p95:

```promql
quantile_over_time(0.95, agent_session_cost_usd[1d])
```

Monthly AI cost by user:

```promql
sum by (user_hash, month) (last_over_time(agent_user_monthly_cost_usd[25h]))
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

Both gauges are emitted **once a day**, by the `daily telemetry maintenance`
cron (06:00 UTC), which schedules them as the first steps of its pass. Because
a gauge is a snapshot and there is now one snapshot a day, every panel reading
them has to wrap the selector in `last_over_time(...[25h])` — a raw selector
only resolves within Prometheus' 5-minute staleness window, so it would read as
"No data" for most of the day.

`business.users.registered_total` is emitted by the step running
`recordRegisteredUsersTotal`. It counts Better Auth users and exports a gauge
with the latest total registered accounts.

`agent.user.monthly_cost_usd` is emitted by the step running
`recordAgentMonthlyUsage`. It reads the current `agentUsageMonthly` rollup and
exports one gauge for each of the top 20 `user_hash + month + model + mode`
rows by monthly estimated cost.

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
- every insert schedules its own export, and an export that fills its batch of
  50 reschedules itself until the queue is empty;
- failed event exports are retried every 45 minutes and failed metric exports
  every 90 minutes, up to 6 attempts; a retry immediately drains recovered rows;
- rows still pending are swept by the same nightly pass;
- exported metrics are deleted after 90 days, failed ones after 14;
- dashboards should read from Grafana, not Convex.

If volume grows, move the buffer/export pipeline to Grafana Alloy or another
collector.

## Troubleshooting

If `/telemetry/metrics` returns `{"ok":true,"accepted":1}` but nothing appears
in Grafana, check the latest `telemetryMetrics` row in Convex:

- `exportStatus = pending`: run `exportPendingMetrics` by hand, or wait for the
  nightly maintenance pass.
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
  Convex deployment running the action.

The exporter also writes a structured `console.warn("telemetry export failed",
...)` without headers or tokens.

For manual tests, omit `timestamp` or use the current epoch milliseconds.
Old timestamps may export successfully but will not appear in Grafana's default
time range.
