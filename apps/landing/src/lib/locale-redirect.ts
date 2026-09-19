import { DEFAULT_LOCALE, isLocale, type Locale } from '../i18n/locales'

/**
 * The `Accept-Language` negotiation behind every unprefixed route, shared by
 * the Pages Functions in `functions/`.
 *
 * Every page is prerendered under `/en/` or `/es/` (see `i18n.routing` in
 * `astro.config.mjs`), so the unprefixed URLs have no content of their own and
 * have to send visitors to a language. Choosing that language from
 * `Accept-Language` needs to happen per request, which a static `_redirects`
 * rule cannot do — it has no access to request headers.
 */

/**
 * The slice of Pages' `EventContext` these handlers touch. Typed locally rather
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

/**
 * Pages the landing prerenders per locale and also answers unprefixed. `''` is
 * the home page, whose localized URL is just `/<locale>/`.
 */
export type LocalizedPage = '' | 'privacy' | 'terms' | 'support'

/**
 * Builds the `onRequest` handler for one unprefixed route: it 302s to the same
 * page under the negotiated locale.
 */
export function localeRedirect(
    page: LocalizedPage,
): (context: RequestContext) => Response {
    return ({ request }) => {
        const locale = negotiateLocale(request.headers.get('accept-language'))

        // Campaign links point at the bare domain, so the query string has to
        // survive the hop for analytics on the localized page to attribute it.
        const { search } = new URL(request.url)

        return new Response(null, {
            status: 302,
            headers: {
                // Relative, so preview deployments on `*.pages.dev` redirect
                // within whatever origin served them instead of jumping to
                // production.
                location: `/${locale}/${page}${search}`,
                // The destination is derived from a request header: without
                // this, one visitor's language gets cached and served to the
                // next.
                vary: 'accept-language',
                'cache-control': 'no-store',
            },
        })
    }
}
