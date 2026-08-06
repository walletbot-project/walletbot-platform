import type {
    MetricAttributeValue,
    MetricName,
    MetricSource,
    MetricType,
    MetricUnit,
} from './types'

export const metricNames = new Set<MetricName>([
    'business.user_accounts.created_count',
    'business.financial_accounts.created_count',
    'business.movements.created_count',
    'business.transfers.created_count',
])

export const metricSources = new Set<MetricSource>(['web', 'native', 'backend'])

export const metricTypes = new Set<MetricType>([
    'counter',
    'gauge',
    'histogram',
])

export const metricUnits = new Set<MetricUnit>(['count', 'ms'])

export const metricCatalog: Record<
    MetricName,
    {
        type: MetricType
        unit: MetricUnit
        attributes: Record<string, Set<MetricAttributeValue> | 'string'>
    }
> = {
    'business.user_accounts.created_count': {
        type: 'counter',
        unit: 'count',
        attributes: {
            auth_method: new Set([
                'email_password',
                'google',
                'apple',
                'local',
            ]),
        },
    },
    'business.financial_accounts.created_count': {
        type: 'counter',
        unit: 'count',
        attributes: {
            created_by: new Set(['form', 'agent']),
            ingest_path: new Set(['direct_mutation', 'direct_client']),
        },
    },
    'business.movements.created_count': {
        type: 'counter',
        unit: 'count',
        attributes: {
            movement_type: new Set(['expense', 'income', 'balance_adjustment']),
            created_by: new Set(['form', 'agent']),
            ingest_path: new Set(['direct_mutation', 'direct_client']),
        },
    },
    'business.transfers.created_count': {
        type: 'counter',
        unit: 'count',
        attributes: {
            created_by: new Set(['form', 'agent']),
            ingest_path: new Set(['direct_mutation', 'direct_client']),
            cross_currency: new Set([true, false]),
        },
    },
}
