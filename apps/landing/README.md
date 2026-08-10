# Landing

Public marketing site for Wallet Bot — Astro 7, Tailwind v4, deployed to Vercel.
Separate from `apps/web`, which is the authenticated app served from
`app.walletbot.live`.

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

Vercel clones the whole repo even when the project root is `apps/landing`, so
the out-of-package files are available at build time.

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

`@astrojs/vercel` with `output` left at its default `'static'`: everything
prerenders, and the adapter exists to emit Vercel's Build Output API format
(redirects, asset caching headers) rather than a bare `dist/`.

Point the Vercel project at this directory as its root. `site` in
`astro.config.mjs` feeds canonical and `hreflang` URLs — it must match the
deployed domain.
