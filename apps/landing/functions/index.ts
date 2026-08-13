import { DEFAULT_LOCALE, isLocale, type Locale } from '../src/i18n/locales'

/**
 * Cloudflare Pages Function for `/` — the site's only piece of server code.
 *
 * Every page is prerendered under `/en/` or `/es/` (see `i18n.routing` in
 * `astro.config.mjs`), so `/` has no content of its own and has to send visitors
 * to a language. Choosing that language from `Accept-Language` needs to happen
 * per request, which a static `_redirects` rule cannot do — it has no access to
 * request headers.
 *
 * Pages' file-based routing maps `functions/index.ts` to exactly `/`, and
 * `public/_routes.json` pins invocation to that one path, so the other routes
 * stay pure static assets and never spin up a Worker.
 */

/**
 * The slice of Pages' `EventContext` this handler touches. Typed locally rather
 * than through `@cloudflare/workers-types`, whose global `Request`/`Response`
 * declarations would collide with the DOM types the rest of the package builds
 * against.
 */
type RequestContext = {
    request: Request
}

/** One `Accept-Language` entry, reduced to what the match needs. */
type LanguageRange = {
    /** Primary subtag, lowercased: `es-419` and `es-AR` both yield `es`. */
    language: string
    /** RFC 9110 weight; absent `q=` means 1. */
    quality: number
}

const parseLanguageRange = (entry: string): LanguageRange => {
    // Language tags and parameter names are both case-insensitive, and the only
    // parameter that matters holds a number, so the whole entry can be folded to
    // lowercase before it is taken apart.
    const [tag = '', ...parameters] = entry.toLowerCase().split(';')
    const weight = parameters
        .map((parameter) => parameter.trim())
        .find((parameter) => parameter.startsWith('q='))
    const quality =
        weight === undefined ? 1 : Number.parseFloat(weight.slice('q='.length))

    return {
        language: tag.trim().split('-')[0] ?? '',
        // A malformed weight is treated as a rejection rather than a
        // preference, which keeps a broken header from outranking a valid one.
        quality: Number.isNaN(quality) ? 0 : quality,
    }
}

/**
 * Highest-weighted language the client asked for that this site ships, or
 * `DEFAULT_LOCALE`. A missing header, an unsupported set of languages and the
 * `*` wildcard all land on the default.
 */
export function negotiateLocale(header: string | null): Locale {
    if (header === null) return DEFAULT_LOCALE

    const ranges = header
        .split(',')
        .map(parseLanguageRange)
        // `q=0` explicitly rejects a language, so it must never be chosen.
        .filter((range) => range.quality > 0)
        // Stable in V8, so equal weights keep the client's stated order.
        .sort((a, b) => b.quality - a.quality)

    for (const { language } of ranges) {
        if (isLocale(language)) return language
    }

    return DEFAULT_LOCALE
}

export function onRequest({ request }: RequestContext): Response {
    const locale = negotiateLocale(request.headers.get('accept-language'))

    // Campaign links point at the bare domain, so the query string has to
    // survive the hop for analytics on the localized page to attribute it.
    const { search } = new URL(request.url)

    return new Response(null, {
        status: 302,
        headers: {
            // Relative, so preview deployments on `*.pages.dev` redirect within
            // whatever origin served them instead of jumping to production.
            location: `/${locale}/${search}`,
            // The destination is derived from a request header: without this,
            // one visitor's language gets cached and served to the next.
            vary: 'accept-language',
            'cache-control': 'no-store',
        },
    })
}
