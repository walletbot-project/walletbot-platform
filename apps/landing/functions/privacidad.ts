import { type RequestContext, redirectTo } from '../src/i18n/negotiate'

/**
 * Spanish-slug alias for the policy: `/privacidad` → `/es/privacy/`.
 *
 * Spanish-only by design — the slug names the language, so this one does not
 * negotiate the way `/privacy` does. `/es/privacy/` stays the canonical URL
 * (it is what `packages/shared/src/legal.ts` builds for the apps and what the
 * pages' canonical and `hreflang` tags point at); the alias only redirects into
 * it, so nothing here creates a second address for the same document.
 */
export function onRequest({ request }: RequestContext): Response {
    return redirectTo(request, '/es/privacy/')
}
