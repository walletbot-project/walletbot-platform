import { compareVersions } from './utils'

type NativeVersionConfig = {
    minSupportedVersion: string
    latestVersion: string
    banners: ConfigBanner[]
    softVersionBanner: ConfigBanner
    hardVersionBanner: ConfigBanner
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
}

export type AccountConfigVerdict = {
    banners: ConfigBanner[]
}

type AccountConfigAccount =
    | { type: 'remote'; userId: string }
    | { type: 'local'; name: string | null; accountId: string | null }
    | null

// apps/native/pubspec.yaml is currently 0.1.0+1. PackageInfo.version sends the
// build-name only, so the backend compares against 0.1.0.
const BASE_MIN_SUPPORTED_VERSION = '0.1.0'
// Keep in lockstep with the shipped `apps/native/pubspec.yaml` build-name.
// Setting this ahead of the released build nags every current client with the
// soft-update banner for a version that isn't out yet.
const BASE_LATEST_VERSION = '0.1.0'

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

const BASE_SOFT_VERSION_BANNER: ConfigBanner = {
    key: 'soft-version-update',
    index: 100,
    placements: ['home', 'auth'],
    tone: 'info',
    title: 'Nueva version disponible',
    messageMarkdown:
        'Actualiza cuando puedas para recibir **las ultimas mejoras**.',
    actions: [],
}

const BASE_HARD_VERSION_BANNER: ConfigBanner = {
    key: 'hard-version-update',
    index: 0,
    placements: ['home', 'auth'],
    tone: 'critical',
    title: 'Actualizacion requerida',
    messageMarkdown: 'Actualiza la app para seguir sincronizando tus datos.',
    actions: [],
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
            ...BASE_SOFT_VERSION_BANNER,
            actions: [
                { label: 'Abrir Play Store', url: ANDROID_PLAY_STORE_URL },
            ],
        },
        hardVersionBanner: {
            ...BASE_HARD_VERSION_BANNER,
            actions: [
                { label: 'Abrir Play Store', url: ANDROID_PLAY_STORE_URL },
            ],
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
}): ConfigVerdict {
    const config = configForPlatform(args.platform)

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
            banners: sortBanners(config.banners),
        }
    }

    const supported =
        compareVersions(args.appVersion, config.minSupportedVersion) >= 0
    const updateAvailable =
        compareVersions(args.appVersion, config.latestVersion) < 0
    const versionBanner = !supported
        ? config.hardVersionBanner
        : updateAvailable
          ? config.softVersionBanner
          : null
    const banners =
        versionBanner === null
            ? config.banners
            : [versionBanner, ...config.banners]
    const updateUrl = versionBanner?.actions[0]?.url ?? null

    return {
        supported,
        forceUpdate: !supported,
        updateAvailable,
        minSupportedVersion: config.minSupportedVersion,
        latestVersion: config.latestVersion,
        updateUrl,
        banners: sortBanners(banners),
    }
}

export function resolveAccountConfig(args: {
    platform: string
    appVersion: string
    deviceId: string
    account: AccountConfigAccount
}): AccountConfigVerdict {
    // Keep this account layer intentionally boring for now. It exists so we can
    // target by stable install id plus authenticated remote user or local
    // account label later without changing the client wire contract.
    void args
    return {
        banners: [],
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
