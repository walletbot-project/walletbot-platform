# Landing

Public marketing site for Wallet Bot — Astro 7, Tailwind v4, deployed to
Cloudflare Pages. Separate from `apps/web`, which is the authenticated app
served from `app.walletbot.live` (its own Pages project).

## Pages

| Route (per locale) | Source | Content |
|---|---|---|
| `/{en,es}/` | `src/components/home-page.astro` | Hero, feature grid, get-the-app links |
| `/{en,es}/privacy` | `src/components/legal-page.astro` | Renders `docs/legal/privacy-policy.{locale}.md` |
| `/{en,es}/terms` | `src/components/legal-page.astro` | Renders `docs/legal/terms-and-conditions.{locale}.md` |

Every marketing claim on the home page maps to shipped code (voice agent,
offline sync, local accounts, multi-currency, dashboard). Do not add claims for
features that don't exist — the saved-filters card is commented out until that
feature ships — and keep local-only wording scoped to *financial records*, per
`docs/legal/README.md`.

Store links are the primary CTA (hero badges, header button, closing section):
Google Play points at the real `live.walletbot.app` listing URL (a placeholder
until the listing goes live) and the App Store badge is "coming soon" (no
link). The web app is deliberately downplayed — a single quiet footer link to
`app.walletbot.live`. URLs live in `src/lib/links.ts`.

## Legal documents

The privacy policy and terms are **not copied** into this package. A content
collection (`src/content.config.ts`) loads `docs/legal/*.md` from the repo root
via the glob loader's `base` option, so the landing always renders the exact
operative files. A custom `generateId` keeps ids as filename stems
(`privacy-policy.en`), and a Sätteri hast plugin in `astro.config.mjs` rewrites
the docs' repo-relative cross-links (`./privacy-policy.en.md` → `/en/privacy`)
at render time.

The build therefore has to run from a full checkout of the repo, not from this
package alone — CI builds it in `.github/workflows/*-deploy.yml` after
`actions/checkout`, so the out-of-package files are present.

## Commands

Run from this directory:

| Command | Does |
|---|---|
| `pnpm dev` | Dev server on `localhost:4321` |
| `pnpm build` | Prerenders every page to `dist/` |
| `pnpm preview` | Serves the built output locally |
| `pnpm typecheck` | `astro check` — types `.astro`, `.ts` and template expressions |

`pnpm dev` and `pnpm typecheck` at the repo root include this package.

`pnpm dev` does **not** run the Pages Function, so `/` 404s there — go straight
to `/en/` or `/es/`. To exercise the redirect, build and serve the output through
Wrangler instead:

```sh
pnpm build && npx wrangler pages dev dist
```

If that errors with `This Worker requires compatibility date …`, the local
`workerd` binary is older than today's date that `pages dev` defaults to; pin it
with `--compatibility-date=<a date the binary supports>` or update Wrangler. This
only affects local dev — deployments run on Cloudflare's current runtime.

## Routing and i18n

Astro's built-in i18n routing owns the URLs; `src/i18n/` owns the copy.

- `i18n.routing.prefixDefaultLocale: true` — every URL carries its language, so
  pages live under `src/pages/en/` and `src/pages/es/`. There is no unprefixed
  content.
- `/` has no page in the build. `functions/index.ts` owns it and 302s to the
  language the browser asked for — see § Deploying. Neither Astro mechanism can
  do this: `redirects` in `astro.config.mjs` only emits a meta-refresh page
  without an adapter, and `i18n.routing.redirectToDefaultLocale` demands a root
  `src/pages/index.astro` (which it then shadows, warning about the conflict on
  every build) and can only ever pick the default locale.
- `Astro.currentLocale` is typed `string | undefined`. Narrow it through
  `useTranslations(Astro.currentLocale)`, which returns `{ locale, t }`.
- `getRelativeLocaleUrl` / `getAbsoluteLocaleUrl` from `astro:i18n` build
  cross-locale links. Never hand-concatenate `/${locale}/...`.

Adding a locale means four edits: `i18n.locales` in `astro.config.mjs`, `LOCALES`
and `LOCALE_LABELS` in `src/i18n/locales.ts`, a new catalog file, and a
`src/pages/<locale>/` directory. The edge redirect needs no edit — it imports
`LOCALES` from `src/i18n/locales.ts` and starts negotiating the new language as
soon as it is listed there.

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

- Dark theme (`bg-slate-950`), Linear-style: white/slate type, hairline
  `white/10` borders, `--color-brand` (the native app's Material seed color)
  reserved for glows, icons and tinted chips. It is too light for text — never
  use it as a text color.
- Font: Inter Variable, self-hosted via `@fontsource-variable/inter`.
- Icons are inline SVGs in `src/components/icon.astro` — Lucide outlines plus
  the Apple and Google Play brand glyphs (Simple Icons paths). No icon font, no
  client JS.
- The hero phone mockup (`src/components/phone-mockup.astro`) is a CSS-only
  illustration of the native voice screen; its copy lives in the `demo` catalog
  section.
- Legal pages use `@tailwindcss/typography` (`prose prose-invert`), loaded with
  `@plugin` in `global.css`.

## Markdown

Astro 7's default processor is Sätteri (`@astrojs/markdown-satteri`), not
remark/rehype — `markdown.remarkPlugins`/`rehypePlugins` require installing the
legacy `@astrojs/markdown-remark` processor. This package stays on Sätteri and
extends it through `markdown.processor: satteri({ hastPlugins: [...] })`
(`satteri` is a devDependency for the plugin types).

## Deploying

Cloudflare Pages project `walletbot-landing`, deployed by
`.github/workflows/prod-deploy.yml` (production, on `main`) and
`preview-deploy.yml` (a per-branch preview on every PR). There is **no adapter**:
`output` stays at its default `'static'`, so `astro build` produces a plain
`dist/` that Pages serves directly. Astro only needs an adapter to render routes
on demand, and only one route here is dynamic at all.

`site` in `astro.config.mjs` feeds canonical and `hreflang` URLs — it must match
the production domain (`www.walletbot.live`).

### The one piece of server code

`functions/index.ts` is a Pages Function serving `/`, and exists solely because
picking a language from the `Accept-Language` header has to happen per request —
a static redirect rule has no access to request headers. It parses the header's
weighted language ranges (honouring `q=` ordering and `q=0` rejections, matching
on the primary subtag so `es-419` and `es-AR` both resolve to `es`), then 302s to
`/<locale>/`, carrying the query string over so campaign parameters survive.

The response sets `Vary: Accept-Language` and `Cache-Control: no-store`: the
destination is derived from a request header, so without them a shared cache
would pin one visitor's language and serve it to the next.

Three conventions keep this cheap:

| File | Role |
|---|---|
| `functions/index.ts` | Pages' file-based routing maps this to exactly `/` |
| `public/_routes.json` | `include: ["/"]` — pins invocation to that one path, so the six prerendered pages and every asset stay free static requests and never start a Worker |
| `public/_headers` | Immutable caching for `/_astro/*`, which Astro fingerprints; replaces what the Vercel adapter used to emit |

`_routes.json` and `_headers` live in `public/` because Astro copies that
directory verbatim into `dist/`, which is where Cloudflare expects them.

The handler imports `LOCALES` from `src/i18n/locales.ts` rather than restating
the list, so it cannot drift from the catalogs. It types the request context
locally instead of pulling in `@cloudflare/workers-types`, whose global
`Request`/`Response` declarations collide with the DOM types the rest of the
package builds against.

### Infrastructure that is not in this repo

- The `walletbot-landing` Pages project itself.
- `www.walletbot.live` (and the apex, if it should redirect to `www`) as a custom
  domain on that project.
- The `CLOUDFLARE_API_TOKEN` / `CLOUDFLARE_ACCOUNT_ID` secrets — already present,
  shared with the `walletbot-platform` project.
