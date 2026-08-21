import { DEFAULT_LOCALE, isLocale, type Locale } from './locales'

/**
 * `Accept-Language` negotiation and the redirect built from it, shared by the
 * Pages Functions in `functions/`.
 *
 * Every page is prerendered under `/en/` or `/es/` (see `i18n.routing` in
 * `astro.config.mjs`), so the unprefixed URLs — `/`, and the legal pages as
 * they get pasted into store listings and chats — have no content of their own
 * and have to send visitors to a language. Choosing that language per request
 * is what forces server code: a static `_redirects` rule has no access to
 * request headers.
 */

/**
 * The slice of Pages' `EventContext` these handlers touch. Typed locally rather
 * than through `@cloudflare/workers-types`, whose global `Request`/`Response`
 * declarations would collide with the DOM types the rest of the package builds
 * against.
 */
export type RequestContext = {
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
 * Query string of the incoming request, or `''`. Campaign links point at the
 * unprefixed URLs, so it has to survive every hop below for analytics on the
 * destination page to attribute the visit.
 */
const searchOf = (request: Request): string => new URL(request.url).search

/**
 * 302 from an unprefixed path to its localized twin:
 * `redirectToLocale(request, 'privacy/')` sends `/privacy` to `/es/privacy/`
 * for a Spanish-speaking visitor.
 *
 * `path` is everything after the locale segment and carries its own trailing
 * slash, because that is the form Pages serves the prerendered pages at —
 * `/es/privacy` itself 308s to `/es/privacy/`, and naming the final URL here
 * saves visitors that second hop.
 */
export function redirectToLocale(request: Request, path: string): Response {
    const locale = negotiateLocale(request.headers.get('accept-language'))

    return new Response(null, {
        status: 302,
        headers: {
            // Relative, so preview deployments on `*.pages.dev` redirect within
            // whatever origin served them instead of jumping to production.
            location: `/${locale}/${path}${searchOf(request)}`,
            // The destination is derived from a request header: without this,
            // one visitor's language gets cached and served to the next.
            vary: 'accept-language',
            'cache-control': 'no-store',
        },
    })
}

/**
 * 302 to one fixed page, for the Spanish-slug aliases:
 * `redirectTo(request, '/es/privacy/')` is what `/privacidad` answers.
 *
 * Nothing is negotiated — the slug itself names the language, so a visitor who
 * follows a Spanish link lands on the Spanish document whatever their browser
 * asks for. That also makes the response cacheable, unlike the negotiated one:
 * it depends on no request header, so a shared cache can serve it and leave the
 * Worker cold. The hour is short enough that the mapping stays correctable.
 */
export function redirectTo(request: Request, path: string): Response {
    return new Response(null, {
        status: 302,
        headers: {
            location: `${path}${searchOf(request)}`,
            'cache-control': 'public, max-age=3600',
        },
    })
}
