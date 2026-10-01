/** The authenticated web app — open beta, available to anyone. */
export const WEB_APP_URL = 'https://app.walletbot.live'

/**
 * Play Store listing for the Android app. `live.walletbot.app` is the real
 * `applicationId` (apps/native/android) and the same URL the backend's update
 * banners point to (packages/backend/convex/config/helpers.ts).
 *
 * Both listings are public, but nothing on the landing links to them on
 * purpose: the store badges route to `/{locale}/beta` so visitors fill out the
 * form first, and the form's confirmation message carries these two URLs.
 * Change one here and there in the same edit.
 */
export const PLAY_STORE_URL =
    'https://play.google.com/store/apps/details?id=live.walletbot.app'

/** App Store listing for the iOS app. Unlinked for the same reason as Play. */
export const APP_STORE_URL =
    'https://apps.apple.com/us/app/wallet-bot-expense-tracker/id6809253565'

/**
 * Google Form behind the beta page's card, and the way into both store apps:
 * its confirmation message holds `PLAY_STORE_URL` and `APP_STORE_URL`.
 */
export const BETA_FORM_URL =
    'https://docs.google.com/forms/d/e/1FAIpQLScCYCKypY28cKM4nSHhJk263GV6r9cnNRH_lhXlT6wH_XOXJQ/viewform?usp=preview'
