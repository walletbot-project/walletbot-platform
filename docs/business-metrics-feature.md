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

### `business.users.registered_total`

Records the current total number of registered Better Auth users.

Attributes: none.

Sources:

- Backend Convex cron `daily telemetry maintenance`, once a day, which
  schedules `record registered users total` as one of its steps.
- Manual backend action `telemetry/actions:recordRegisteredUsersTotalNow` for
  tests and dashboard backfill checks.

This metric is a gauge because it represents current state, not new
registrations during a period.

### `business.user_accounts.signed_in_count`

Counts successful user sign-ins.

Attributes:

- `auth_method`: `email_password`, `google`, or `apple`
- `client_platform`: `native` or `web`

Sources:

- Backend native auth routes after successful email/password or Google sign-in.

Native sign-ups continue to use `business.user_accounts.created_count`; they
are not counted as sign-ins unless the user later performs a sign-in flow.

### `agent.session.cost_usd`

Records the estimated total USD cost for a logical agent session. Native emits
this gauge when the session is explicitly ended.

Attributes:

- `model`: stable model name, such as `gemini-3.1-flash-live-preview`
- `mode`: `voice`, `text`, or `mixed`
- `cost_source`: `estimated`, `provider_usage`, or `reconciled`

Sources:

- Native Gemini Live usage metadata when a session ends.

The voice session id is sent as the metric envelope `sessionId`, not as a
metric attribute, so dashboards can detect expensive sessions without creating
high-cardinality Grafana series.

### `agent.interaction.cost_usd`

Records the estimated USD cost delta for one completed agent interaction.
Native emits this gauge whenever Gemini Live sends new `usageMetadata`.

Attributes:

- `model`: stable model name, such as `gemini-3.1-flash-live-preview`
- `mode`: `voice`, `text`, or `mixed`
- `cost_source`: `estimated`, `provider_usage`, or `reconciled`

Sources:

- Native Gemini Live usage metadata after completed turns/interactions. Native
  sends token-count attributes; backend recalculates the USD value from the
  server-side pricing table before storing/exporting the metric.

For authenticated users, backend stores each accepted interaction cost sample
in `agentUsageSamples` and rolls it up into `agentUsageMonthly` by
`userId + month + model + mode`. The native client sends a low-cardinality
metric plus a non-label `sampleId`; backend uses `sampleId` for idempotency
without exporting it as a Grafana label.

### `agent.user.monthly_cost_usd`

Records the current accumulated estimated AI cost for the top 20
`user + model + mode` rows in the current UTC month. It is emitted every 6
hours from the backend rollup table.

Attributes:

- `user_hash`: stable SHA-256 prefix of the application user id
- `rank`: rank in the monthly top 20 export
- `month`: UTC month in `YYYY-MM` format
- `model`: stable model name
- `mode`: `voice`, `text`, or `mixed`

Sources:

- Backend Convex cron `daily telemetry maintenance`, once a day, which
  schedules `record agent monthly usage` as one of its steps, reading
  `agentUsageMonthly`.
- Manual backend action `telemetry/actions:recordAgentMonthlyUsageNow` for
  tests and dashboard refresh checks.

This metric is a gauge because it represents the latest monthly accumulated
state, not the delta since the previous export.

### `agent.interactions.completed_count`

Counts completed agent interactions. Native emits it together with
`agent.interaction.cost_usd` only when the estimated cost differs from the
previous usage metadata sample, so repeated identical samples are not counted
again.

Attributes:

- `model`: stable model name
- `mode`: `voice`, `text`, or `mixed`
- `interaction_type`: `voice`, `text`, `mixed`, or `tool`

Sources:

- Native Gemini Live usage metadata after completed turns/interactions.

### `agent.session.cost_bucket_count`

Counts agent sessions by estimated USD cost bucket.

Attributes:

- `model`: stable model name
- `mode`: `voice`, `text`, or `mixed`
- `cost_bucket`: `0-0.01`, `0.01-0.05`, `0.05-0.10`,
  `0.10-0.50`, `0.50-1.00`, or `1.00+`

Sources:

- Backend telemetry ingestion, derived from the accepted
  `agent.session.cost_usd` metric after server-side cost normalization.

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
- `agentUsageSamples`
- `agentUsageMonthly`

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
- Agent session cost uses a `gauge` with unit `usd`; bucket metrics use counters
  with unit `count`.
- Registered user total uses a `gauge` with unit `count`.
- Attribute values are validated against the catalog on HTTP ingestion.
- Metric delivery is best-effort on native and backend.
- Native stores a stable `telemetry_installation_id` in secure storage for
anonymous-safe telemetry payloads.

## Follow-ups

- Replace the hard-coded native `AppConfig.appVersion` telemetry value with the
  runtime package/build version so version labels match release artifacts built
  with Flutter `--build-name` / `--build-number`.
