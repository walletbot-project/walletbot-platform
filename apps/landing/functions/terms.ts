import { type RequestContext, redirectToLocale } from '../src/i18n/negotiate'

/**
 * Pages Function for `/terms` — the unprefixed twin of `functions/privacy.ts`,
 * and the same 404 it fixed: there is no page at `/terms` in the build, only
 * `/en/terms/` and `/es/terms/`. Anything that links the documents without a
 * language (store listings, pasted links, `docs/legal/README.md`'s publishing
 * checklist) hits this and gets sent to the language the browser asked for.
 *
 * Both documents must stay reachable the same way — the acceptance checkbox
 * shows them as a pair, so a working privacy link next to a dead terms link is
 * the worse half of the bug.
 */
export function onRequest({ request }: RequestContext): Response {
    return redirectToLocale(request, 'terms/')
}
