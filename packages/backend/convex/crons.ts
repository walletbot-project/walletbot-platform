import { cronJobs } from 'convex/server'
import { internal } from './_generated/api'
import { AGENT_REPORT_RETENTION_MS } from './agentReports/utils'
import { ORPHAN_ATTACHMENT_TTL_MS } from './feedback/utils'
import { VOICE_RETENTION_MS } from './voice/utils'

const crons = cronJobs()

crons.interval(
    'cleanup resend emails',
    { hours: 24 },
    internal.emails.internal.cleanupResendEmails,
    {},
)

// Everything telemetry and metrics used to be eleven crons on their own clocks,
// waking the deployment about 800 times a day between them. They are now one
// nightly pass that schedules its steps a few seconds apart and takes about five
// minutes: see `telemetry/internal.ts` for what runs, in what order, and why.
// 06:00 UTC is 03:00 in Buenos Aires — cron times are always UTC.
crons.cron(
    'daily telemetry maintenance',
    '0 6 * * *',
    internal.telemetry.internal.runDailyMaintenance,
    {},
)

// Market exchange rates for the agent's getExchangeRate tool. The Argentine
// markets move through the day; the central-bank reference rates behind the
// international set publish about once a day, so they are polled far less.
crons.interval(
    'refresh argentine exchange rates',
    { minutes: 30 },
    internal.exchangeRates.internal.refreshArgentineRates,
    {},
)

crons.interval(
    'refresh international exchange rates',
    { hours: 6 },
    internal.exchangeRates.internal.refreshInternationalRates,
    {},
)

// Feedback attachments go straight from the client to a Convex upload URL, so an
// abandoned or rejected submission leaves stored bytes with nothing pointing at
// them.
crons.interval(
    'delete orphaned feedback attachments',
    { hours: 6 },
    internal.feedback.internal.deleteOrphanAttachments,
    {
        olderThanMs: ORPHAN_ATTACHMENT_TTL_MS,
        limit: 100,
    },
)

// Reported agent responses hold conversation excerpts, so they expire on the
// same twelve-month clock as the voice history they were cut from.
crons.interval(
    'delete old agent reports',
    { hours: 6 },
    internal.agentReports.internal.deleteOldReports,
    {
        olderThanMs: AGENT_REPORT_RETENTION_MS,
        limit: 200,
    },
)

// Voice history is the retention promise the privacy policy makes most
// explicitly (§5, §9). Events run on a larger batch than sessions because one
// session produces hundreds of them.
crons.interval(
    'delete old voice sessions',
    { hours: 6 },
    internal.voice.internal.deleteOldVoiceSessions,
    {
        olderThanMs: VOICE_RETENTION_MS,
        limit: 200,
    },
)

crons.interval(
    'delete old voice session events',
    { hours: 6 },
    internal.voice.internal.deleteOldVoiceSessionEvents,
    {
        olderThanMs: VOICE_RETENTION_MS,
        limit: 2000,
    },
)

// A purge batch that throws is never retried by the scheduler, which used to
// leave an account half-deleted forever. This is the only thing that finishes
// the job when that happens.
crons.interval(
    'revive stalled account deletions',
    { minutes: 10 },
    internal.userDeletion.internal.reviveStalledDeletions,
    {},
)

// A WhatsApp agent turn that dies mid-flight leaves its conversation stuck in
// `processing`, and every later message then writes a row without starting a
// turn — the user is silently ignored forever. This is the only thing that
// recovers from that.
crons.interval(
    'release stuck whatsapp agent turns',
    { minutes: 5 },
    internal.whatsapp.internal.releaseStuckTurns,
    {},
)

// Link codes are credentials for binding a phone number to an account. They
// stop being useful minutes after they are minted, so the table is kept small
// and stale rows are dropped rather than left lying around.
crons.interval(
    'purge expired whatsapp link codes',
    { hours: 1 },
    internal.whatsapp.internal.purgeExpiredLinkCodes,
    {},
)

export default crons
