// @ts-check
import { satteri } from '@astrojs/markdown-satteri'
import vercel from '@astrojs/vercel'
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
    // plain HTML. The adapter is still required so the build emits Vercel's
    // Build Output API format instead of a bare `dist/`.
    adapter: vercel(),

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

    // `/` has no content of its own. This is preferred over
    // `i18n.routing.redirectToDefaultLocale`, which requires a root
    // `src/pages/index.astro` and then only emits a 2-second meta-refresh page
    // that conflicts with it; the adapter turns this into a real HTTP redirect
    // in `.vercel/output/config.json`. 302, not 301, so the choice of default
    // locale is not permanently cached in browsers.
    redirects: {
        '/': { status: 302, destination: '/en/' },
    },

    markdown: {
        processor: satteri({ hastPlugins: [legalDocLinks] }),
    },

    vite: {
        // Tailwind v4 ships as a Vite plugin; the `@astrojs/tailwind`
        // integration is gone. See src/styles/global.css.
        plugins: [tailwindcss()],
    },
})
