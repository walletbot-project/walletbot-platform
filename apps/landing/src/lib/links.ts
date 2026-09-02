/** The authenticated web app — open beta, available to anyone. */
export const WEB_APP_URL = 'https://app.walletbot.live'

/**
 * Play Store listing for the Android app. `live.walletbot.app` is the real
 * `applicationId` (apps/native/android) and the same URL the backend's update
 * banners point to (packages/backend/convex/config/helpers.ts).
 *
 * Nothing on the landing links here yet: the Android build is a **closed**
 * test, so the listing is not public and access runs through the tester list
 * on `/{locale}/beta`. Point the Play badge back at this once the test opens.
 */
export const PLAY_STORE_URL =
    'https://play.google.com/store/apps/details?id=live.walletbot.app'

/**
 * Google Form behind the beta page's card. Collects tester requests until
 * there is a reason to build a real form against the backend.
 */
export const BETA_FORM_URL =
    'https://docs.google.com/forms/d/e/1FAIpQLScCYCKypY28cKM4nSHhJk263GV6r9cnNRH_lhXlT6wH_XOXJQ/viewform?usp=preview'
