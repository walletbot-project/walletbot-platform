import { type RequestContext, redirectTo } from '../../src/i18n/negotiate'

/**
 * `/es/privacidad` → `/es/privacy/`: the Spanish slug where a reader would
 * expect it, under the Spanish prefix. Same destination as the unprefixed
 * `/privacidad`, so both spellings and both prefixes land on one page.
 */
export function onRequest({ request }: RequestContext): Response {
    return redirectTo(request, '/es/privacy/')
}
