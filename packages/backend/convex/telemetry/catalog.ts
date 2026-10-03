import { agentPricingAttributeSpec } from './agentPricing'
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
    'business.users.registered_total',
    'business.user_accounts.signed_in_count',
    'agent.sessions.started_count',
    'agent.session.cost_usd',
    'agent.interaction.cost_usd',
    'agent.user.monthly_cost_usd',
    'agent.interactions.completed_count',
    'agent.session.cost_bucket_count',
    'agent.reports.submitted_count',
])

export const metricSources = new Set<MetricSource>(['web', 'native', 'backend'])

export const metricTypes = new Set<MetricType>([
    'counter',
    'gauge',
    'histogram',
])

export const metricUnits = new Set<MetricUnit>(['count', 'ms', 'usd'])

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
    'business.users.registered_total': {
        type: 'gauge',
        unit: 'count',
        attributes: {},
    },
    'business.user_accounts.signed_in_count': {
        type: 'counter',
        unit: 'count',
        attributes: {
            auth_method: new Set(['email_password', 'google', 'apple']),
            client_platform: new Set(['native', 'web']),
        },
    },
    // One live session opened on a client, counted where the session actually
    // begins (the client's session repository) rather than where its token is
    // minted: a mint happens on every reconnect and on the screen's speculative
    // prefetch, so minting is not a session.
    //
    // `start_kind` is the difference the mint could never report: `new` is a
    // session that did not exist a moment ago, `resumed` is the same
    // conversation picked up again through a live resume handle. Sessions
    // created = `new`; re-opened = `resumed`.
    'agent.sessions.started_count': {
        type: 'counter',
        unit: 'count',
        attributes: {
            model: 'string',
            start_kind: new Set(['new', 'resumed']),
        },
    },
    'agent.session.cost_usd': {
        type: 'gauge',
        unit: 'usd',
        attributes: {
            model: 'string',
            mode: new Set(['voice', 'text', 'mixed']),
            cost_source: new Set(['provider_usage', 'estimated', 'reconciled']),
            ...agentPricingAttributeSpec,
        },
    },
    'agent.interaction.cost_usd': {
        type: 'gauge',
        unit: 'usd',
        attributes: {
            model: 'string',
            mode: new Set(['voice', 'text', 'mixed']),
            cost_source: new Set(['provider_usage', 'estimated', 'reconciled']),
            ...agentPricingAttributeSpec,
        },
    },
    'agent.user.monthly_cost_usd': {
        type: 'gauge',
        unit: 'usd',
        attributes: {
            user_hash: 'string',
            rank: 'string',
            month: 'string',
            model: 'string',
            mode: new Set(['voice', 'text', 'mixed']),
        },
    },
    'agent.interactions.completed_count': {
        type: 'counter',
        unit: 'count',
        attributes: {
            model: 'string',
            mode: new Set(['voice', 'text', 'mixed']),
            interaction_type: new Set(['voice', 'text', 'mixed', 'tool']),
        },
    },
    'agent.session.cost_bucket_count': {
        type: 'counter',
        unit: 'count',
        attributes: {
            model: 'string',
            mode: new Set(['voice', 'text', 'mixed']),
            cost_bucket: new Set([
                '0-0.01',
                '0.01-0.05',
                '0.05-0.10',
                '0.10-0.50',
                '0.50-1.00',
                '1.00+',
            ]),
        },
    },
    // Reported agent responses. `reason` is the shared AGENT_REPORT_REASONS set;
    // a spike in one of them is the signal that the prompt or the safety
    // settings need attention, which is the half of Play's "use reports to
    // inform moderation" that the admin queue alone doesn't cover.
    'agent.reports.submitted_count': {
        type: 'counter',
        unit: 'count',
        attributes: {
            reason: new Set([
                'offensive',
                'sexual',
                'dangerous',
                'misleading',
                'privacy',
                'other',
            ]),
            scope: new Set(['response', 'session']),
            client_platform: 'string',
        },
    },
}
