import { type RequestContext, redirectToLocale } from '../src/i18n/negotiate'

/**
 * Pages Function for `/privacy` — the unprefixed URL the policy gets shared as.
 * There is no page there in the build, so it used to 404 while `/en/privacy/`
 * and `/es/privacy/` both worked; this 302s to whichever of the two the browser
 * asked for.
 *
 * Trailing slashes are optional in Pages' *function* routing, so this one file
 * answers both `/privacy` and `/privacy/` — but `public/_routes.json` lists the
 * two forms separately, since invocation matching is by literal path and
 * nothing documents it as normalizing the slash away.
 */
export function onRequest({ request }: RequestContext): Response {
    return redirectToLocale(request, 'privacy/')
}
