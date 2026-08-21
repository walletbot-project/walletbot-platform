import { type RequestContext, redirectTo } from '../../src/i18n/negotiate'

/** `/es/terminos` → `/es/terms/`. See `functions/es/privacidad.ts`. */
export function onRequest({ request }: RequestContext): Response {
    return redirectTo(request, '/es/terms/')
}
