import {
    LEGAL_VERSIONS,
    type LegalDocument,
    type Locale,
    resolveLocale,
} from '@wallet-bot/shared'
import { internal } from '../_generated/api'
import type { ActionCtx } from '../_generated/server'
import type { FlagKey } from '../featureFlags/utils'
import { compareVersions } from './utils'

type NativeVersionConfig = {
    minSupportedVersion: string
    latestVersion: string
    banners: LocalizedConfigBanner[]
    softVersionBanner: LocalizedConfigBanner
    hardVersionBanner: LocalizedConfigBanner
}

type ConfigBannerAction = {
    label: string
    url: string
}

type ConfigBannerTone = 'info' | 'warning' | 'critical'
type ConfigBannerPlacement = 'home' | 'auth'

type ConfigBanner = {
    key: string
    index: number
    placements: ConfigBannerPlacement[]
    tone: ConfigBannerTone
    title: string
    messageMarkdown: string
    actions: ConfigBannerAction[]
}

type LocalizedConfigBanner = Record<Locale, ConfigBanner>

export const PLATFORM_ANDROID = 'android' as const
export const PLATFORM_IOS = 'ios' as const
export const PLATFORM_MACOS = 'macos' as const

type NativePlatform =
    | typeof PLATFORM_ANDROID
    | typeof PLATFORM_IOS
    | typeof PLATFORM_MACOS

export type ConfigVerdict = {
    supported: boolean
    forceUpdate: boolean
    updateAvailable: boolean
    minSupportedVersion: string
    latestVersion: string
    updateUrl: string | null
    banners: ConfigBanner[]
    /**
     * Current/minimum version of each legal document
     * (`@wallet-bot/shared`'s `legal.ts`). Served here because native needs
     * them for LOCAL-only accounts, which have no backend user and therefore
     * cannot ask `v1/legal/queries:acceptanceStatus`. Additive: older clients
     * ignore the field, and a client that never reaches the endpoint falls
     * back to its bundled copy
     * (`apps/native/lib/legal/legal_versions.dart`).
     */
    legal: Record<LegalDocument, { current: string; min: string }>
}

export type AccountConfigVerdict = {
    banners: ConfigBanner[]
    flags: Record<FlagKey, boolean>
}

type AccountConfigAccount =
    | { type: 'remote'; userId: string }
    | { type: 'local'; name: string | null; accountId: string | null }
    | null

// apps/native/pubspec.yaml is currently 0.3.0+5. PackageInfo.version sends the
// build-name only, so the backend compares against 0.3.0.
//
// Bumped from 0.2.0 alongside native drift schemaVersion v3 -> v4 (adds the
// synced `agent_memories` table — the agent-overhaul memory subsystem). Per
// the CLAUDE.md client–server contract, a change to the set of synced tables
// must bump BOTH this `minSupportedVersion` and the drift `schemaVersion` in
// the same change so pre-v4 clients fail CLOSED on sync (they keep working
// offline on local data). Previous bump: 0.1.0 -> 0.2.0 with v1 -> v2
// (`transactions.time_status`).
const BASE_MIN_SUPPORTED_VERSION = '0.3.0'
// Keep in lockstep with the shipped `apps/native/pubspec.yaml` build-name.
// Setting this ahead of the released build nags every current client with the
// soft-update banner for a version that isn't out yet.
const BASE_LATEST_VERSION = '0.3.0'

// A client that cannot determine its own version reports '0.0.0' (and any
// unparseable string parses to 0.0.0 too — see utils.ts). Treat that as
// "unknown" and fail OPEN: a transient PackageInfo failure must never gate a
// current build out of sync (CLAUDE.md: native config fails open). A genuinely
// outdated client reports its real version, never 0.0.0.
const UNKNOWN_VERSION = '0.0.0'
const isUnknownVersion = (appVersion: string): boolean =>
    compareVersions(appVersion, UNKNOWN_VERSION) === 0
const ANDROID_MIN_SUPPORTED_VERSION = BASE_MIN_SUPPORTED_VERSION
const ANDROID_LATEST_VERSION = BASE_LATEST_VERSION
const IOS_MIN_SUPPORTED_VERSION = BASE_MIN_SUPPORTED_VERSION
const IOS_LATEST_VERSION = BASE_LATEST_VERSION
const MACOS_MIN_SUPPORTED_VERSION = BASE_MIN_SUPPORTED_VERSION
const MACOS_LATEST_VERSION = BASE_LATEST_VERSION

const ANDROID_PLAY_STORE_URL =
    'https://play.google.com/store/apps/details?id=live.walletbot.app'

const BASE_SOFT_VERSION_BANNER: LocalizedConfigBanner = {
    en: {
        key: 'soft-version-update',
        index: 100,
        placements: ['home', 'auth'],
        tone: 'info',
        title: 'New version available',
        messageMarkdown:
            'Update when you can to receive **the latest improvements**.',
        actions: [],
    },
    es: {
        key: 'soft-version-update',
        index: 100,
        placements: ['home', 'auth'],
        tone: 'info',
        title: 'Nueva versión disponible',
        messageMarkdown:
            'Actualizá cuando puedas para recibir **las últimas mejoras**.',
        actions: [],
    },
}

const BASE_HARD_VERSION_BANNER: LocalizedConfigBanner = {
    en: {
        key: 'hard-version-update',
        index: 0,
        placements: ['home', 'auth'],
        tone: 'critical',
        title: 'Update required',
        messageMarkdown: 'Update the app to continue syncing your data.',
        actions: [],
    },
    es: {
        key: 'hard-version-update',
        index: 0,
        placements: ['home', 'auth'],
        tone: 'critical',
        title: 'Actualización obligatoria',
        messageMarkdown:
            'Actualizá la aplicación para seguir sincronizando tus datos.',
        actions: [],
    },
}

const DEFAULT_CONFIG: NativeVersionConfig = {
    minSupportedVersion: BASE_MIN_SUPPORTED_VERSION,
    latestVersion: BASE_LATEST_VERSION,
    banners: [],
    softVersionBanner: BASE_SOFT_VERSION_BANNER,
    hardVersionBanner: BASE_HARD_VERSION_BANNER,
}

// Simple production knob for native version handling. Change these constants
// when a release needs a soft update nudge or a hard sync floor.
const CONFIG_BY_PLATFORM: Record<NativePlatform, NativeVersionConfig> = {
    [PLATFORM_ANDROID]: {
        minSupportedVersion: ANDROID_MIN_SUPPORTED_VERSION,
        latestVersion: ANDROID_LATEST_VERSION,
        banners: [],
        softVersionBanner: {
            en: {
                ...BASE_SOFT_VERSION_BANNER.en,
                actions: [
                    { label: 'Open Play Store', url: ANDROID_PLAY_STORE_URL },
                ],
            },
            es: {
                ...BASE_SOFT_VERSION_BANNER.es,
                actions: [
                    { label: 'Abrir Play Store', url: ANDROID_PLAY_STORE_URL },
                ],
            },
        },
        hardVersionBanner: {
            en: {
                ...BASE_HARD_VERSION_BANNER.en,
                actions: [
                    { label: 'Open Play Store', url: ANDROID_PLAY_STORE_URL },
                ],
            },
            es: {
                ...BASE_HARD_VERSION_BANNER.es,
                actions: [
                    { label: 'Abrir Play Store', url: ANDROID_PLAY_STORE_URL },
                ],
            },
        },
    },
    // TODO: iOS/macOS have no distribution URL yet, so their version banners
    // carry no action and `updateUrl` stays null — the hard-update prompt has no
    // button. Add an App Store / distribution link (like Android's Play Store
    // action) once there is a public build channel.
    [PLATFORM_IOS]: {
        minSupportedVersion: IOS_MIN_SUPPORTED_VERSION,
        latestVersion: IOS_LATEST_VERSION,
        banners: [],
        softVersionBanner: BASE_SOFT_VERSION_BANNER,
        hardVersionBanner: BASE_HARD_VERSION_BANNER,
    },
    [PLATFORM_MACOS]: {
        minSupportedVersion: MACOS_MIN_SUPPORTED_VERSION,
        latestVersion: MACOS_LATEST_VERSION,
        banners: [],
        softVersionBanner: BASE_SOFT_VERSION_BANNER,
        hardVersionBanner: BASE_HARD_VERSION_BANNER,
    },
}

const isNativePlatform = (platform: string): platform is NativePlatform =>
    platform === PLATFORM_ANDROID ||
    platform === PLATFORM_IOS ||
    platform === PLATFORM_MACOS

const sortBanners = (banners: ConfigBanner[]): ConfigBanner[] =>
    [...banners].sort((left, right) => {
        const byIndex = left.index - right.index
        if (byIndex !== 0) return byIndex
        return left.key.localeCompare(right.key)
    })

// The wire sentinel returned by sync `push`/`pull` when the calling client is
// below the platform's `minSupportedVersion`. The native sync engine matches on
// this exact value to halt sync and surface the hard update prompt.
export const CLIENT_OUTDATED = 'client_outdated' as const

const configForPlatform = (platform: string): NativeVersionConfig =>
    isNativePlatform(platform) ? CONFIG_BY_PLATFORM[platform] : DEFAULT_CONFIG

export function resolveConfigVerdict(args: {
    platform: string
    appVersion: string
    deviceId: string
    locale?: string
}): ConfigVerdict {
    const config = configForPlatform(args.platform)
    const locale = resolveLocale(args.locale)
    const configuredBanners = config.banners.map((banner) => banner[locale])

    // Fail open for a client that can't report its version: treat it as
    // supported and up to date so a transient PackageInfo failure never locks
    // it out of sync or forces a dead-end update prompt.
    if (isUnknownVersion(args.appVersion)) {
        return {
            supported: true,
            forceUpdate: false,
            updateAvailable: false,
            minSupportedVersion: config.minSupportedVersion,
            latestVersion: config.latestVersion,
            updateUrl: null,
            banners: sortBanners(configuredBanners),
            legal: LEGAL_VERSIONS,
        }
    }

    const supported =
        compareVersions(args.appVersion, config.minSupportedVersion) >= 0
    const updateAvailable =
        compareVersions(args.appVersion, config.latestVersion) < 0
    const versionBanner = !supported
        ? config.hardVersionBanner[locale]
        : updateAvailable
          ? config.softVersionBanner[locale]
          : null
    const banners =
        versionBanner === null
            ? configuredBanners
            : [versionBanner, ...configuredBanners]
    const updateUrl = versionBanner?.actions[0]?.url ?? null

    return {
        supported,
        forceUpdate: !supported,
        updateAvailable,
        minSupportedVersion: config.minSupportedVersion,
        latestVersion: config.latestVersion,
        updateUrl,
        banners: sortBanners(banners),
        legal: LEGAL_VERSIONS,
    }
}

export async function resolveAccountConfig(args: {
    ctx: ActionCtx
    platform: string
    appVersion: string
    deviceId: string
    locale?: string
    account: AccountConfigAccount
}): Promise<AccountConfigVerdict> {
    // Local-only device accounts have no backend userId, so they always get
    // the global default for every flag; only authenticated remote users can
    // carry a per-user override.
    const userId = args.account?.type === 'remote' ? args.account.userId : null
    const flags = await args.ctx.runQuery(
        internal.featureFlags.internal.resolveFlagsForUserInternal,
        { userId },
    )
    return {
        banners: [],
        flags,
    }
}

export function isClientSupported(
    platform: string,
    appVersion: string,
): boolean {
    return resolveConfigVerdict({
        platform,
        appVersion,
        deviceId: 'unknown',
    }).supported
}
