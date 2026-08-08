// @ts-check
import vercel from '@astrojs/vercel'
import tailwindcss from '@tailwindcss/vite'
import { defineConfig } from 'astro/config'

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

    vite: {
        // Tailwind v4 ships as a Vite plugin; the `@astrojs/tailwind`
        // integration is gone. See src/styles/global.css.
        plugins: [tailwindcss()],
    },
})
