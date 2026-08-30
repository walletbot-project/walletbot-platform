import { localeRedirect } from '../src/lib/locale-redirect'

/**
 * Pages Function for `/privacy` (and `/privacy/` — trailing slashes are
 * optional in Pages' routing).
 *
 * The policy is prerendered only at `/en/privacy` and `/es/privacy`, but the
 * URL that gets handed out is the bare one: Google Play and Apple each want a
 * single public privacy-policy link (see `docs/legal/README.md`), and neither
 * store listing nor an in-app link can know the reader's language. So the
 * unprefixed path has to negotiate instead of 404ing.
 */
export const onRequest = localeRedirect('privacy')
