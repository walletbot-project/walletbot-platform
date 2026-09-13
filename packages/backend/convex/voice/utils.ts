/**
 * How long voice history is kept before the retention cron reclaims it.
 *
 * Twelve months is a promise, not a tuning knob: Privacy Policy §5 and §9
 * commit to deleting `voiceSessions` and `voiceSessionEvents` on this clock,
 * in both languages, at `www.walletbot.live/{en,es}/privacy`. Changing it here
 * means changing the published documents first (see `docs/legal/README.md`).
 *
 * `AGENT_REPORT_RETENTION_MS` deliberately matches: a moderation report holds
 * excerpts cut from this history and must not outlive it.
 */
export const VOICE_RETENTION_MS = 365 * 24 * 60 * 60 * 1000
