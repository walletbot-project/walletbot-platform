# Exchange rates for the agent — `getExchangeRate`

Shipped 2026-08-25. Gives Gaston a market exchange rate for any pair of the
app's currencies, with the Argentine market variants (oficial, blue, MEP, CCL,
tarjeta, cripto, mayorista) as first-class options. Agent-only: no UI surface
consumes rates yet, and nothing in the app converts stored money.

## Shape

`getExchangeRate({ from, to, amount?, market? })` →

```
{ ok: true, from, to, market, rate, buy?, sell?, source, asOf, path,
  stale?: true, converted?, alternatives? }
{ ok: false, error }
```

- `rate` reads "1 `from` = rate `to`". Two-sided provider quotes also carry
  `buy`/`sell` (compra/venta); `rate` is their midpoint.
- `market` defaults to `official` and is echoed back, because a pair with no
  quote in the requested market falls back to `official`.
- `alternatives` lists every market that pair is quoted in — ARS pairs only —
  so the agent can say "oficial 1530, blue 1565" without a second call.
- `path` is `direct`, `inverse` or `triangulated` (through USD).
- `stale` appears past 72 h (`FX_STALE_AFTER_MS`), sized so a normal weekend
  does not read as broken.
- Errors, verbatim, because the tool description and the skill promise them:
  `Unknown currency code: X`, `from and to are the same currency`,
  `No exchange rate available for X→Y`,
  `Exchange rates are unavailable right now`.

## Data path

Clients never call a provider. The backend refreshes a small global cache and
both clients resolve against a snapshot of it.

```
crons ──► exchangeRates/internal:refreshArgentineRates      (dolarapi.com)
      ──► exchangeRates/internal:refreshInternationalRates  (api.frankfurter.dev)
                    │
                    ▼
          exchangeRates table (global, ~60 rows)
                    │
   web ── v1/exchangeRates/queries:snapshot ──┐
                                              ├── resolveFxQuote (shared)
   native ── GET /v1/fx/rates ── FxRatesController (device cache) ──┘
```

| Piece | Where |
|---|---|
| Table | `packages/backend/convex/schema/exchangeRates.ts` |
| Provider adapters (pure, tested) | `packages/backend/convex/exchangeRates/utils.ts` |
| Refresh + upsert + snapshot | `packages/backend/convex/exchangeRates/internal.ts` |
| Read helper | `packages/backend/convex/exchangeRates/helpers.ts` |
| Web read | `packages/backend/convex/v1/exchangeRates/queries.ts` |
| Native read | `packages/backend/convex/exchangeRates/http.ts` (`GET /v1/fx/rates`) |
| Resolution maths | `packages/shared/src/tools/fx.ts` + `apps/native/lib/voice/tool_fx.dart` |
| Executors | `apps/web/src/lib/agent-tools/executors.ts`, `apps/native/lib/voice/tool_executors.dart` |
| Device cache | `apps/native/lib/fx/fx_rates_controller.dart` |
| Skill | `exchange-rates` in `packages/shared/src/agent-skills/index.ts` |

Design points worth keeping:

- **Bounded table.** `upsertRates` rejects any base outside `SNAPSHOT_BASES`
  (USD, EUR, BRL, CLP, UYU) and any currency outside the shared catalog, so the
  row set is constant-size and `readSnapshot` can read it as five indexed
  ranges instead of a table scan.
- **Provider priority.** dolarapi owns ARS (it publishes both sides and the
  market variants); frankfurter may only fill a USD→ARS gap, and only once the
  dolarapi row is more than 24 h old (`SOURCE_TAKEOVER_AFTER_MS`).
- **Failures never overwrite.** A bad row is dropped by the adapter, and a
  failed fetch leaves the previous rows alone. A stale quote with an honest
  `asOf` beats no quote.
- **Native stays offline-safe.** The network hop lives in `FxRatesController`
  (app-scoped, device-cached in `flutter_secure_storage`), never in a tool
  executor — rates are public market data, so they stay out of
  `AppDatabase.forUser` and out of the sync protocol. `ToolExecutors` receives
  only a `List<FxQuote> Function()`, so it has no idea fetching exists.
- **No `AbortController` in Convex's default runtime**, so the refresh actions
  have no per-request timeout; a hung provider is bounded by the action limit
  and the next cron tick.

## Gating

Two independent gates, both server-side at mint time
(`convex/live/createToken.ts`):

1. **Feature flag `exchangeRates`** (`FLAG_GATED_TOOLS`), resolved for the
   connecting user before minting — from the session in `/v1/live/token` and
   from `requireAuth` in `v1/live/actions:requestLiveToken`. Off by default.
   The client never says which tools it may have.
2. **Native version floor** `0.3.1` (`NATIVE_TOOL_MIN_VERSION`), because the
   executor and the rate cache ship in that build. Web is unrestricted by
   version.

The prompt's `# Exchange rates` section is emitted only when the tool is
actually declared, and native only fetches rates while the flag is on
(`FxRatesController.enabled`, from the account config's flags).

## Rolling it out

1. Deploy the backend and wait for one cron tick (or run
   `internal.exchangeRates.internal.refreshArgentineRates` from the dashboard).
   `GET /v1/fx/rates` should return a non-empty `rates` array.
2. Turn on `exchangeRates` for your own user (a `featureFlagOverrides` row)
   before flipping the global default.
3. Native needs a release ≥ `0.3.1`; below that the tool is withheld even with
   the flag on.

## Tests

| What | Where |
|---|---|
| TS↔Dart parity of resolution, alternatives, rounding, staleness | `packages/shared/src/tools/fx-fixtures.json` run by `packages/shared/test/fx-fixtures.test.ts` and `apps/native/test/voice/fx_fixtures_test.dart` |
| Provider adapters against real-shaped payloads | `packages/backend/test/exchangeRates.test.ts` |
| Flag + version gating, prompt section | `packages/backend/test/createToken.test.ts` |
| Tool envelope, fallbacks, empty cache | `apps/native/test/voice/fx_tool_test.dart` |
| Executor coverage | web `satisfies Record<ToolName, ToolExecutor>`; native `tool_manifest_test.dart` |

## Not done

- No UI surface: the transfer form does not offer to pre-fill `toAmount` from a
  rate. Deliberate — the user's real rate is what belongs in a movement.
- No historical rates: the cache holds only the latest quote per pair/market.
- Risk register: `R-024` in `docs/riesgos.md`.
