# Wallet Bot

A personal expense tracker built around a live voice mode: you say what you
spent and the assistant logs it — no spreadsheets, no forms, just a
conversation.

Final degree project (Trabajo Profesional) for Ingeniería en Informática,
FIUBA.

| | |
| --- | --- |
| **Landing** | <https://www.walletbot.live> |
| **Web app** | <https://app.walletbot.live> — open beta, anyone can sign in |
| **Android** | [Google Play](https://play.google.com/store/apps/details?id=live.walletbot.app) — `live.walletbot.app` |
| **iOS** | Not submitted. See [`docs/appstore-readiness.md`](docs/appstore-readiness.md) |
| **Beta / testers** | [walletbot.live/es/beta](https://www.walletbot.live/es/beta/) |
| **Dashboards** | [Grafana Cloud](https://fearlesspillar2602.grafana.net/d/geb465q/user-accounts-created-by-auth-method?var-Scope=production) — accounts created by auth method. Needs access to the org. |

> The landing resolves on `www` only — `walletbot.live` without it has no DNS
> record.
>
> The landing's store badges deliberately route to the beta form rather than to
> the stores; see the note in `apps/landing/src/lib/links.ts`.

---

## Español

Wallet Bot es un gestor de gastos personales construido alrededor de un modo de
voz en vivo: contás qué gastaste y el asistente lo anota. Sin planillas, sin
formularios tediosos, sólo una conversación.

Trabajo Profesional de Ingeniería en Informática, FIUBA.

El problema que ataca no es la falta de funciones sino la carga de datos. En la
encuesta que hicimos (207 respuestas, abril de 2026) más de la mitad de las
personas no anota sus gastos, y los tres grupos —quienes anotan, quienes lo
intentaron y abandonaron, y quienes nunca empezaron— coinciden en el mismo
motivo: registrar cada consumo a mano cuesta más de lo que rinde.

---

## Repo structure

pnpm workspace (`apps/*`, `packages/*`), pinned to pnpm 10.27 via
`packageManager`.

| Path | What it is |
| --- | --- |
| `packages/backend` | Convex: schema, queries/mutations, auth, sync, agent usage and telemetry. The source of truth for the data model. |
| `packages/shared` | Tool schemas shared by every client, so the assistant's contract is defined once. |
| `apps/web` | React 19 + Vite + Tailwind v4, React Router. Deployed to Cloudflare Pages. |
| `apps/native` | Flutter (Dart SDK ^3.11.4). Offline-first, with a local store that syncs when the device is back online. |
| `apps/landing` | Astro marketing site. Its own Cloudflare Pages project on `www`. See [`apps/landing/README.md`](apps/landing/README.md). |

### Backend

Convex hosts the database, the server functions and the scheduler. Auth is
`better-auth` through `@convex-dev/better-auth` (`convex/auth.ts`). Sync is
offline-first: a per-user monotonic `seq`, last-write-wins on `updatedAt`, and
compare-and-swap on push.

### Voice agent

The client opens a session against the Gemini Live API
(`gemini-3.1-flash-live-preview`) using an ephemeral token minted by Convex, so
no API key ever reaches the device. Tool calls execute on the client and write
straight to Convex.

- `packages/shared/src/tools/definitions.ts` — tool schemas, shared front and back
- `apps/web/src/hooks/use-voice.ts` — session lifecycle on web
- `apps/web/src/lib/agent-tools/executors.ts` — tool-call implementations
- [`docs/voice-session-lifecycle.md`](docs/voice-session-lifecycle.md) — how a session opens, runs and closes

---

## Getting started

```bash
pnpm install
pnpm dev          # every app in parallel
pnpm typecheck    # all workspaces
pnpm format       # biome, writes
```

Single app:

```bash
pnpm --filter web dev
pnpm --filter landing dev     # http://localhost:4321
pnpm native                   # flutter run, needs the Flutter SDK
```

## Deploys

- **Production** — `.github/workflows/prod-deploy.yml` on `main`: Convex, then
  the web app and the landing to their own Cloudflare Pages projects, then the
  Android build.
- **Staging previews** — `.github/workflows/preview-deploy.yml`, opt-in per PR
  through labels (`create-staging-web`, `create-staging-landing`,
  `create-staging-mobile`). Removing a label tears down what it created.

## Docs

`docs/` holds the design and planning notes: [data model](docs/data-model.md),
[native data layer](docs/native-data-layer.md), [client API
versioning](docs/client-api-versioning.md), [risk
register](docs/riesgos.md), [observability](docs/observability-grafana.md),
and the store-readiness checklists.

## Observability

Metrics ship from Convex to Grafana Cloud; the setup, the expected metrics and
the starter PromQL live in
[`docs/observability-grafana.md`](docs/observability-grafana.md).

- [Accounts created by auth method](https://fearlesspillar2602.grafana.net/d/geb465q/user-accounts-created-by-auth-method?var-Scope=production)
