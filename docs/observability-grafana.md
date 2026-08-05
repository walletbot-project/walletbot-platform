# Grafana Cloud Observability Setup

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

Useful labels:

- `created_by`
- `ingest_path`
- `auth_method`
- `movement_type`
- `cross_currency`
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
  Convex deployment running the action.

The exporter also writes a structured `console.warn("telemetry export failed",
...)` without headers or tokens.

For manual tests, omit `timestamp` or use the current epoch milliseconds.
Old timestamps may export successfully but will not appear in Grafana's default
time range.
