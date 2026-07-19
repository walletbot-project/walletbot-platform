# Business Metrics

This feature adds a small business-metrics pipeline for WalletBot. It records
selected product events as counters, stores them in Convex, and exports them to
an OTLP metrics backend for Grafana dashboards.

## Goals

- Count business events that matter for product usage.
- Attribute creation flows to `form` or `agent`.
- Keep metrics best-effort so observability does not block user actions.
- Avoid local database schema changes in the native app.
- Keep metric labels low-cardinality and explicit.

## Metric Catalog

The current catalog is defined in `packages/backend/convex/telemetry/catalog.ts`.

### `business.user_accounts.created_count`

Counts user account creation.

Attributes:

- `auth_method`: `email_password`, `google`, `apple`, or `local`

Sources:

- Backend native auth routes for email/password and Google accounts.
- Native app for local-only accounts.

### `business.financial_accounts.created_count`

Counts wallet financial account creation, such as cash, bank, or card accounts.

Attributes:

- `created_by`: `form` or `agent`
- `ingest_path`: `direct_mutation` or `direct_client`

Sources:

- Backend Convex account mutation for web/direct Convex writes.
- Native app repository writes for offline-first native flows.

### `business.movements.created_count`

Counts expense, income, and balance-adjustment creation.

Attributes:

- `movement_type`: `expense`, `income`, or `balance_adjustment`
- `created_by`: `form` or `agent`
- `ingest_path`: `direct_mutation` or `direct_client`

Sources:

- Backend Convex transaction mutations for web/direct Convex writes.
- Native app repository writes for offline-first native flows.

### `business.transfers.created_count`

Counts transfer creation.

Attributes:

- `created_by`: `form` or `agent`
- `ingest_path`: `direct_mutation` or `direct_client`
- `cross_currency`: `true` or `false`

Sources:

- Backend Convex transaction mutation for web/direct Convex writes.
- Native app repository writes for offline-first native flows.

## Architecture

### Native

Native uses `TelemetryClient` for HTTP delivery and `BusinessMetrics` for typed
business-metric helpers.

`BusinessMetrics` is injected through the account-scoped `AppRepositories`
bundle, so repositories can record metrics at the same point where local writes
are confirmed.

Native emits creation metrics directly when the local operation succeeds. It
does not wait for sync and does not store metric provenance in Drift.

### Web

The web app does not send metrics directly. It passes creation attribution to
Convex mutations when the web agent creates movements.

Manual web forms omit `createdBy`, so backend mutations default to `form`.

### Backend

Backend mutations use helpers from `packages/backend/convex/telemetry/metrics.ts`.
Those helpers write rows to `telemetryMetrics` and schedule export work.

Metric helper failures are caught and logged with `console.warn`, so telemetry
does not fail the user-facing mutation.

Backend also exposes HTTP telemetry ingestion routes:

- `POST /telemetry/events`
- `POST /telemetry/metrics`

## Convex Storage

This feature adds Convex-only telemetry tables:

- `telemetryEvents`
- `telemetryMetrics`
- `telemetryMetricSeries`

There are no native Drift schema changes.

`telemetryMetricSeries` stores cumulative state needed to export monotonic OTLP
counter points.

## Export

Pending metric rows are exported through scheduled Convex actions. The exporter
uses OTLP metrics endpoints derived from:

- `OTEL_EXPORTER_OTLP_METRICS_ENDPOINT`, or
- `OTEL_EXPORTER_OTLP_ENDPOINT`

Optional headers are parsed from `OTEL_EXPORTER_OTLP_HEADERS`.

Failed exports are marked for retry. Exported metric rows are later cleaned up
by cron.

## Operational Notes

- Metrics are counters with unit `count`.
- Attribute values are validated against the catalog on HTTP ingestion.
- Metric delivery is best-effort on native and backend.
- Native stores a stable `telemetry_installation_id` in secure storage for
anonymous-safe telemetry payloads.
