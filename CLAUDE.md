## About

Wallet Bot — app for keeping track of personal expenses

**Before working on auth, the native app, or anything touching `convex_flutter`, read [LESSONS.md](./LESSONS.md).** It documents recurring mistakes made on this codebase — every rule in it was paid for with a bug.

## Monorepo structure

| Package | Path | Stack |
|---|---|---|
| Native app | `apps/app` | Flutter |
| Web app | `apps/web` | Vite + React + Tailwind v4 + shadcn (base-ui) |
| Backend | `packages/backend` | Convex + better-auth |
| Shared | `packages/shared` | Pure TypeScript — convex backend |

## Rules

- Use pnpm (not npm/yarn)
- When changing frontend, always lint: `pnpm run lint` (from `apps/web`)
- When changing backend or shared, always typecheck: `pnpm run typecheck` (from root — runs all packages)
- Run `pnpm run format` after changes (from root)
- Follow user's instructions precisely, don't do un-requested work, and ask for clarification if unsure.
- Never do destructive operations (database, git commands, etc...) without explicit instructions and approval.
- Always try to avoid using `git stash`, `git checkout`, `git reset`. You can ask user for permissions if it really makes sense.
- NEVER by any reason use the type `any`.
- NEVER force types by doing ` as unknown as `.
- Avoid complex type inference, there is usually a simpler way.
- Avoid hacky solutions, there is always a right way to do things.
- If you are debugging something and you apply a fix and it doesn't work, you must revert it manually before trying something else.
- If you change shared component, YOU MUST CHECK ALL USAGES AND MAKE SURE IT DOESN'T BREAK ANYTHING. If you are not sure, ask for help or approval.
- Use `kebab-case` for file names, EXCEPT in `convex/` dir, use `camelCase` there.
- When designing features, always consider error cases, including not found, failed to load, error boundaries, and empty states. Don't forget to handle loading states as well.
- Use toast notification for loading, success, and error states.
- When asked to implement a broad capability (e.g. "implement expenses tracking"), always clarify scope before writing code. A single capability may involve a **module** (frontend), a **feature** (backend), and/or a **flow** (agent) — see README.md § Terminology. Ask the user which layers are needed, what entities/fields/relationships are involved, what roles/permissions apply, and whether an agent flow is desired.
- Follow guidelines for frontend and backend development. There are already many reusable components. Research first common patterns before creating something new.
- THE CLIENT IS NOT TRUSTABLE!!! Always authenticate, authorize and validate permission. DO NOT TRUST client for authorization.
- Don't use primary/brand color for text (it is too light)
- Do not suppress linter, YOU MUST request approval if you need to for some weird reason.
- To use VFS, always use helpers from storage feature, never access VFS tables directly.
- NEVER EVER EVER write shadcn's component (never write inside /components/ui). ALWAYS use CLI to add components.
- NEVER ASSUME ANYTHING!!! NEVER!!! ASSUMPTIONS ALREADY KILLED John and Timmy on this project.
- Avoid reading dependencies source, always try to use skills and documentation.
- Do not remove imports unless you are 100% sure they are not used, also `pnpm format` already removes unused imports, you don't need to do it manually.
- PLEASE consider Convex workflows for complex long running or multi steps processes
- After implementing a feature, review `docs/riesgos.md` and decide whether
  the feature mitigates an existing risk, changes its probability or impact, or
  introduces a new risk that should be added.
- The current native SQLite schema is `v3`. Do not reset the baseline or ask
  testers to reinstall as a substitute for migrations. Every schema change must
  increment `schemaVersion`, implement an explicit data-preserving `onUpgrade`
  path, export a new schema snapshot, and add schema plus data-integrity
  migration tests. Follow `docs/schema/README.md`.
- After all steps of any task run a CLAUDE.md rules check
- Always report violations


### Feature Parity between mobile and web

- If the user or a linear ticket asks you to implement a feature in mobile or web, asks the user if he also wants to implement that feature in the other platform to maintain feature parity and suggest possible implementations for this.

## Dev workflow

- `pnpm dev` at root starts both web and convex dev servers in parallel
- Convex dev server must be running for backend types to generate — restart it if types stop updating after adding new files to `convex/`

## Web app

Follow `apps/web/DEVELOPMENT.md` for project structure, layout system, and module conventions.

## Shared package

`packages/shared` contains code shared between frontend and backend. Import via `@wallet-bot/shared`.

## Backend

Follow `packages/backend/README.md` for environment setup (Convex, better-auth, Google OAuth).
Follow `packages/backend/DEVELOPMENT.md` for backend architecture and conventions.

### Feature layout (quick ref)

Each feature gets a directory under `convex/`:

| File | Purpose |
|---|---|
| `queries.ts` | Client-callable reads (`query`) |
| `mutations.ts` | Client-callable writes (`mutation`) |
| `actions.ts` | Client-callable side-effects (`action`) |
| `internal.ts` | Server-only functions (`internalQuery`, `internalMutation`, `internalAction`) |
| `helpers.ts` | Exported utilities (other features can import) |
| `utils.ts` | Internal utilities (private to the feature) |

Schema definitions go in `convex/schema/{feature}.ts` and are composed in `convex/schema.ts`.

### File storage

(pending documentation)

## Convex's database access rules

- Never do full table scans in queries (don't use `db.table('x').collect()`), unless you are guaranteed the table is small (e.g. <100 rows) and it will always be small. Please inform and request explicit consent for any table scan.
- Always use indexes for queries. If you find yourself needing to do a full table scan, add an index on the relevant field(s) and query against that index instead.
- Use features like `.first()`, `.unique()` and `db.normalizeId()` when it makes sense. Prefer using `v.string()` over `v.id()` in query args when the id may not exists (for example for handling 404 error cases, `v.id()` crashes if entity is not present).
- Always default to make queries paginated. Use the pagination utilities in `convex-helpers` to make this easier. You can skip this in the same cases you can use a table scan (please have a good criteria).
- If accessing a protected resource, make sure to use authorization (check userId or whatever corresponds)
- Never do overview stats or similar by collecting all entities. Not allowed at all!
- Never do text search in the backend by loading all elements and filtering them in memory. If you need text search, add a search index and query against it.


### `'use node'` runtime rules

Convex has two runtimes: the default (fast, no Node APIs) and Node.js. Files that need Node APIs (e.g. `crypto`, `fs`) must follow these rules:

- **Only actions** (not queries or mutations) can be exported from `'use node'` files. If you need both actions and mutations, split them into separate files.
- **Import chain rule**: A `'use node'` file can import files without `'use node'` — but those imported files must NOT use any Node APIs (`crypto`, `fs`, `Buffer`, etc.). If an imported file uses Node APIs, it must also have `'use node'`. Example: `actions.ts` (`'use node'`) can import `helpers.ts` (no Node APIs, no directive needed), but must NOT import `gcs.ts` (uses `node:crypto`) unless `gcs.ts` also has `'use node'`.
- **Do NOT add `'use node'` to files that don't need it** — especially `http.ts` (the HTTP router). Making the router a Node file forces ALL HTTP handlers into Node runtime.
- **HTTP handlers that need Node APIs** should delegate to internal actions via `ctx.runAction()` instead of importing Node code directly. Example: the file serve handler calls `internal.storage.actions.generateGcsReadUrl` instead of importing `gcs.ts`.
- **Auth helpers** (`requireAuth`, `requireRole`) use `QueryCtx | MutationCtx` — they don't work in actions (`ActionCtx`). Use `ctx.runQuery(internal.*.requireStorageEditor)` to verify auth from an action.
- **Pure utility files** (no Convex function exports) that use Node APIs still need `'use node'` at the top.

### Authorization (quick ref)

(pending documentation)

### Data aggregates

- Please use Convex's aggregate component when needing to build features with stats or counts, rankings, etc...

## Long or complex processes

- Please use multiple steps, and ideally use the Convex's Workflows component for durable long running proceses. Read docs to do it correctly.

<!-- convex-ai-start -->
This project uses [Convex](https://convex.dev) as its backend.

When working on Convex code, **always read `convex/_generated/ai/guidelines.md` first** for important guidelines on how to correctly use Convex APIs and patterns. The file contains rules that override what you may have learned about Convex from training data.

Convex agent skills for common tasks can be installed by running `npx convex ai-files install`.
<!-- convex-ai-end -->
