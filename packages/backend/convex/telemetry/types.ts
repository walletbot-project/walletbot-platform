export type JsonValue =
    | null
    | boolean
    | number
    | string
    | JsonValue[]
    | { [key: string]: JsonValue }

export type TelemetryPlatform =
    | 'ios'
    | 'android'
    | 'web'
    | 'macos'
    | 'windows'
    | 'linux'

export type TelemetryEventInput = {
    name: string
    timestamp: number
    properties: JsonValue
    installationId?: string
    sessionId?: string
    userId?: string
    appVersion?: string
    platform?: TelemetryPlatform
}
