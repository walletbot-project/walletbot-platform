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
    sampleId?: string
    userId?: string
    appVersion?: string
    platform?: TelemetryPlatform
}

export type MetricName =
    | 'business.user_accounts.created_count'
    | 'business.financial_accounts.created_count'
    | 'business.movements.created_count'
    | 'business.transfers.created_count'
    | 'business.users.registered_total'
    | 'business.user_accounts.signed_in_count'
    | 'agent.session.cost_usd'
    | 'agent.interaction.cost_usd'
    | 'agent.user.monthly_cost_usd'
    | 'agent.interactions.completed_count'
    | 'agent.session.cost_bucket_count'

export type MetricSource = 'web' | 'native' | 'backend'

export type MetricType = 'counter' | 'gauge' | 'histogram'

export type MetricUnit = 'count' | 'ms' | 'usd'

export type MetricAttributeValue = string | number | boolean

export type MetricInput = {
    name: MetricName
    timestamp: number
    source: MetricSource
    type: MetricType
    value: number
    unit?: MetricUnit
    attributes?: Record<string, MetricAttributeValue>
    installationId?: string
    sessionId?: string
    sampleId?: string
    userId?: string
    appVersion?: string
    platform?: TelemetryPlatform
}
