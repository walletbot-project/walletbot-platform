import { type RequestContext, redirectTo } from '../src/i18n/negotiate'

/**
 * Spanish-slug alias for the terms: `/terminos` → `/es/terms/`. Unaccented
 * only, matching the slug as specified — `/t%C3%A9rminos` is not routed.
 *
 * See `functions/privacidad.ts` for why these aliases redirect rather than
 * serve, and why they do not negotiate.
 */
export function onRequest({ request }: RequestContext): Response {
    return redirectTo(request, '/es/terms/')
}
