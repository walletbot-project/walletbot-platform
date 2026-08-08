# Landing

Public marketing site for Wallet Bot — Astro 7, Tailwind v4, deployed to Vercel.
Separate from `apps/web`, which is the authenticated app served from
`app.walletbot.live`.

## Commands

Run from this directory:

| Command | Does |
|---|---|
| `pnpm dev` | Dev server on `localhost:4321` |
| `pnpm build` | Prerenders to `dist/` and emits `.vercel/output/` |
| `pnpm preview` | Serves the built output locally |
| `pnpm typecheck` | `astro check` — types `.astro`, `.ts` and template expressions |

`pnpm dev` and `pnpm typecheck` at the repo root include this package.

## Routing and i18n

Astro's built-in i18n routing owns the URLs; `src/i18n/` owns the copy.

- `i18n.routing.prefixDefaultLocale: true` — every URL carries its language, so
  pages live under `src/pages/en/` and `src/pages/es/`. There is no unprefixed
  content.
- `/` is a 302 to `/en/`, declared in `redirects` in `astro.config.mjs` and
  emitted as a real edge redirect in `.vercel/output/config.json`.
  `i18n.routing.redirectToDefaultLocale` was deliberately *not* used: it demands
  a root `src/pages/index.astro`, then shadows it with a 2-second meta-refresh
  page and warns about the route conflict on every build.
- `Astro.currentLocale` is typed `string | undefined`. Narrow it through
  `useTranslations(Astro.currentLocale)`, which returns `{ locale, t }`.
- `getRelativeLocaleUrl` / `getAbsoluteLocaleUrl` from `astro:i18n` build
  cross-locale links. Never hand-concatenate `/${locale}/...`.

Adding a locale means four edits: `i18n.locales` in `astro.config.mjs`, `LOCALES`
and `LOCALE_LABELS` in `src/i18n/locales.ts`, a new catalog file, and a
`src/pages/<locale>/` directory.

### Catalogs

Mirrors `apps/web/src/lib/i18n`: `es.ts` is the reference locale and its shape
defines `Messages`, so `en.ts` — typed as `Messages` — fails `astro check` on a
missing key, a stray key, or a value function whose parameters drifted. There is
no runtime key-fallback and no key-parity test, because neither is needed.

Entries that interpolate are functions, not template strings, which keeps their
parameter names and types checked at the call site:

```ts
t.home.setupNotice({ locale })
```

## Styling

Tailwind v4 via `@tailwindcss/vite` (configured in `astro.config.mjs`), not the
retired `@astrojs/tailwind` integration. There is no `tailwind.config.js` —
tokens go in the `@theme` block in `src/styles/global.css`, which
`base-layout.astro` imports.

## Deploying

`@astrojs/vercel` with `output` left at its default `'static'`: everything
prerenders, and the adapter exists to emit Vercel's Build Output API format
(redirects, asset caching headers) rather than a bare `dist/`.

Point the Vercel project at this directory as its root. `site` in
`astro.config.mjs` feeds canonical and `hreflang` URLs — it must match the
deployed domain.
