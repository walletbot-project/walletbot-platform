// @ts-check
import { satteri } from '@astrojs/markdown-satteri'
import tailwindcss from '@tailwindcss/vite'
import { defineConfig } from 'astro/config'

/**
 * The legal pages render `docs/legal/*.md` verbatim (see
 * `src/content.config.ts`), and those files cross-link each other with
 * repo-relative hrefs like `./privacy-policy.en.md`. This Sätteri hast plugin
 * rewrites such links to the landing's routes (`/en/privacy`) at render time,
 * so the source files stay untouched and keep working on GitHub.
 *
 * @type {import('satteri').HastPluginDefinition}
 */
const legalDocLinks = {
    name: 'legal-doc-links',
    element: {
        filter: ['a'],
        visit(node, ctx) {
            const href = node.properties.href
            const match =
                typeof href === 'string'
                    ? href.match(
                          /^\.\/(privacy-policy|terms-and-conditions)\.(en|es)\.md$/,
                      )
                    : null
            if (!match) return
            const page = match[1] === 'privacy-policy' ? 'privacy' : 'terms'
            ctx.setProperty(node, 'href', `/${match[2]}/${page}`)
        },
    },
}

// https://astro.build/config
export default defineConfig({
    // The web app is served from `app.walletbot.live`; the landing gets `www`.
    // Feeds canonical URLs, `getAbsoluteLocaleUrl` and the sitemap.
    site: 'https://www.walletbot.live',

    // `output` is left at its default (`'static'`): the landing prerenders to
    // plain HTML in `dist/`, which Cloudflare Pages serves directly. No adapter
    // — Astro only needs one to render routes on demand, and nothing here does.

    i18n: {
        // Keep in sync with `LOCALES` in `src/i18n/locales.ts`.
        locales: ['en', 'es'],
        defaultLocale: 'en',
        routing: {
            // Every URL carries its language: `/en/...` and `/es/...`. Pages
            // therefore live under `src/pages/en/` and `src/pages/es/`.
            prefixDefaultLocale: true,
        },
    },

    // The unprefixed paths (`/`, `/privacy`, `/terms`) have no content of their
    // own and are deliberately absent from the build. `functions/` owns them,
    // negotiating `Accept-Language` into a 302. Neither Astro mechanism can do
    // that: `redirects` here only emits a meta-refresh page without an adapter,
    // and `i18n.routing.redirectToDefaultLocale` both demands a root
    // `src/pages/index.astro` and can only ever pick the default locale.

    markdown: {
        processor: satteri({ hastPlugins: [legalDocLinks] }),
    },

    vite: {
        // Tailwind v4 ships as a Vite plugin; the `@astrojs/tailwind`
        // integration is gone. See src/styles/global.css.
        plugins: [tailwindcss()],
    },
})
