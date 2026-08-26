import { defineTable } from 'convex/server'
import { v } from 'convex/values'

/**
 * Per-user settings the SERVER needs to know about. Not to be confused with
 * device-scoped display preferences (theme, and the tri-state language picker),
 * which stay on the device.
 *
 * `language` is the one the backend sends email in, and eventually WhatsApp.
 * All three language fields are optional because rows written before the
 * feature existed have none, and because a user whose clients have never
 * reported a locale legitimately has none: callers fall back through
 * `getUserLanguage` (v1/users/helpers.ts).
 *
 * - `language`       resolved to a shipped locale; what templates render in.
 * - `languageSource` `explicit` if the user picked a language in Settings,
 *   `device` if it was inferred from the OS/browser. A `device` report must
 *   never overwrite an `explicit` value. See `resolveLanguageWrite`
 *   (v1/users/utils.ts).
 * - `languageTag`    the raw BCP 47 tag behind it (`es-AR`), kept for regional
 *   number/date formatting in outbound messages.
 */
export const userSettings = defineTable({
    userId: v.string(),
    defaultCurrency: v.string(),
    language: v.optional(v.union(v.literal('es'), v.literal('en'))),
    languageSource: v.optional(
        v.union(v.literal('device'), v.literal('explicit')),
    ),
    languageTag: v.optional(v.string()),
    updatedAt: v.int64(),
}).index('by_user', ['userId'])
