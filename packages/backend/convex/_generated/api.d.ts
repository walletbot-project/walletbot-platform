/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as agent_helpers from "../agent/helpers.js";
import type * as agent_idempotency from "../agent/idempotency.js";
import type * as agent_internal from "../agent/internal.js";
import type * as agent_prompt from "../agent/prompt.js";
import type * as agent_resolve from "../agent/resolve.js";
import type * as agent_runner from "../agent/runner.js";
import type * as agent_time from "../agent/time.js";
import type * as agent_tools from "../agent/tools.js";
import type * as agent_toolset from "../agent/toolset.js";
import type * as agentReports_helpers from "../agentReports/helpers.js";
import type * as agentReports_internal from "../agentReports/internal.js";
import type * as agentReports_rateLimits from "../agentReports/rateLimits.js";
import type * as agentReports_utils from "../agentReports/utils.js";
import type * as agentUsage_queries from "../agentUsage/queries.js";
import type * as aggregates from "../aggregates.js";
import type * as appUsers_helpers from "../appUsers/helpers.js";
import type * as appUsers_internal from "../appUsers/internal.js";
import type * as auth from "../auth.js";
import type * as authNative_http from "../authNative/http.js";
import type * as authNative_mutations from "../authNative/mutations.js";
import type * as authNative_rateLimits from "../authNative/rateLimits.js";
import type * as authNative_utils from "../authNative/utils.js";
import type * as config_helpers from "../config/helpers.js";
import type * as config_http from "../config/http.js";
import type * as config_utils from "../config/utils.js";
import type * as crons from "../crons.js";
import type * as emails_helpers from "../emails/helpers.js";
import type * as emails_internal from "../emails/internal.js";
import type * as emails_nodeActions from "../emails/nodeActions.js";
import type * as emails_utils from "../emails/utils.js";
import type * as exchangeRates_helpers from "../exchangeRates/helpers.js";
import type * as exchangeRates_http from "../exchangeRates/http.js";
import type * as exchangeRates_internal from "../exchangeRates/internal.js";
import type * as exchangeRates_utils from "../exchangeRates/utils.js";
import type * as featureFlags_helpers from "../featureFlags/helpers.js";
import type * as featureFlags_internal from "../featureFlags/internal.js";
import type * as featureFlags_utils from "../featureFlags/utils.js";
import type * as feedback_helpers from "../feedback/helpers.js";
import type * as feedback_internal from "../feedback/internal.js";
import type * as feedback_rateLimits from "../feedback/rateLimits.js";
import type * as feedback_utils from "../feedback/utils.js";
import type * as http from "../http.js";
import type * as httpHelpers from "../httpHelpers.js";
import type * as legal_helpers from "../legal/helpers.js";
import type * as legal_internal from "../legal/internal.js";
import type * as legal_validators from "../legal/validators.js";
import type * as live_createToken from "../live/createToken.js";
import type * as live_helpers from "../live/helpers.js";
import type * as live_internal from "../live/internal.js";
import type * as live_rateLimits from "../live/rateLimits.js";
import type * as migrations from "../migrations.js";
import type * as occurrences_helpers from "../occurrences/helpers.js";
import type * as recurrences_internal from "../recurrences/internal.js";
import type * as recurrences_workflow from "../recurrences/workflow.js";
import type * as schema_accounts from "../schema/accounts.js";
import type * as schema_agentMemories from "../schema/agentMemories.js";
import type * as schema_agentReports from "../schema/agentReports.js";
import type * as schema_agentUsage from "../schema/agentUsage.js";
import type * as schema_appUsers from "../schema/appUsers.js";
import type * as schema_categories from "../schema/categories.js";
import type * as schema_dashboard from "../schema/dashboard.js";
import type * as schema_exchangeRates from "../schema/exchangeRates.js";
import type * as schema_featureFlags from "../schema/featureFlags.js";
import type * as schema_feedback from "../schema/feedback.js";
import type * as schema_legal from "../schema/legal.js";
import type * as schema_occurrenceClock from "../schema/occurrenceClock.js";
import type * as schema_recurrences from "../schema/recurrences.js";
import type * as schema_refreshTokens from "../schema/refreshTokens.js";
import type * as schema_supportEmails from "../schema/supportEmails.js";
import type * as schema_sync from "../schema/sync.js";
import type * as schema_tags from "../schema/tags.js";
import type * as schema_telemetry from "../schema/telemetry.js";
import type * as schema_transactionTags from "../schema/transactionTags.js";
import type * as schema_transactions from "../schema/transactions.js";
import type * as schema_usability from "../schema/usability.js";
import type * as schema_userDeletion from "../schema/userDeletion.js";
import type * as schema_userSettings from "../schema/userSettings.js";
import type * as schema_voice from "../schema/voice.js";
import type * as schema_whatsapp from "../schema/whatsapp.js";
import type * as support_actions from "../support/actions.js";
import type * as support_http from "../support/http.js";
import type * as support_internal from "../support/internal.js";
import type * as support_utils from "../support/utils.js";
import type * as sync_compatibility from "../sync/compatibility.js";
import type * as sync_helpers from "../sync/helpers.js";
import type * as tags_backfill from "../tags/backfill.js";
import type * as tags_helpers from "../tags/helpers.js";
import type * as telemetry_actions from "../telemetry/actions.js";
import type * as telemetry_agentPricing from "../telemetry/agentPricing.js";
import type * as telemetry_catalog from "../telemetry/catalog.js";
import type * as telemetry_http from "../telemetry/http.js";
import type * as telemetry_latency from "../telemetry/latency.js";
import type * as telemetry_metrics from "../telemetry/metrics.js";
import type * as telemetry_mutations from "../telemetry/mutations.js";
import type * as telemetry_queries from "../telemetry/queries.js";
import type * as telemetry_types from "../telemetry/types.js";
import type * as telemetry_usageActor from "../telemetry/usageActor.js";
import type * as telemetry_validators from "../telemetry/validators.js";
import type * as transactions_adjustmentBackfill from "../transactions/adjustmentBackfill.js";
import type * as transactions_backfill from "../transactions/backfill.js";
import type * as transactions_helpers from "../transactions/helpers.js";
import type * as usability_actions from "../usability/actions.js";
import type * as usability_datasets from "../usability/datasets.js";
import type * as usability_internal from "../usability/internal.js";
import type * as usability_utils from "../usability/utils.js";
import type * as usability_workflow from "../usability/workflow.js";
import type * as userDeletion_helpers from "../userDeletion/helpers.js";
import type * as userDeletion_http from "../userDeletion/http.js";
import type * as userDeletion_internal from "../userDeletion/internal.js";
import type * as users_helpers from "../users/helpers.js";
import type * as v1_accounts_helpers from "../v1/accounts/helpers.js";
import type * as v1_accounts_internal from "../v1/accounts/internal.js";
import type * as v1_accounts_mutations from "../v1/accounts/mutations.js";
import type * as v1_accounts_queries from "../v1/accounts/queries.js";
import type * as v1_agentReports_mutations from "../v1/agentReports/mutations.js";
import type * as v1_agentReports_queries from "../v1/agentReports/queries.js";
import type * as v1_categories_mutations from "../v1/categories/mutations.js";
import type * as v1_categories_queries from "../v1/categories/queries.js";
import type * as v1_dashboard_helpers from "../v1/dashboard/helpers.js";
import type * as v1_dashboard_mutations from "../v1/dashboard/mutations.js";
import type * as v1_dashboard_queries from "../v1/dashboard/queries.js";
import type * as v1_exchangeRates_queries from "../v1/exchangeRates/queries.js";
import type * as v1_featureFlags_mutations from "../v1/featureFlags/mutations.js";
import type * as v1_featureFlags_queries from "../v1/featureFlags/queries.js";
import type * as v1_feedback_mutations from "../v1/feedback/mutations.js";
import type * as v1_legal_mutations from "../v1/legal/mutations.js";
import type * as v1_legal_queries from "../v1/legal/queries.js";
import type * as v1_live_actions from "../v1/live/actions.js";
import type * as v1_memories_mutations from "../v1/memories/mutations.js";
import type * as v1_memories_queries from "../v1/memories/queries.js";
import type * as v1_recurrences_mutations from "../v1/recurrences/mutations.js";
import type * as v1_recurrences_queries from "../v1/recurrences/queries.js";
import type * as v1_support_queries from "../v1/support/queries.js";
import type * as v1_sync_internal from "../v1/sync/internal.js";
import type * as v1_sync_mutations from "../v1/sync/mutations.js";
import type * as v1_sync_queries from "../v1/sync/queries.js";
import type * as v1_sync_validators from "../v1/sync/validators.js";
import type * as v1_tags_mutations from "../v1/tags/mutations.js";
import type * as v1_tags_queries from "../v1/tags/queries.js";
import type * as v1_transactions_mutations from "../v1/transactions/mutations.js";
import type * as v1_transactions_queries from "../v1/transactions/queries.js";
import type * as v1_usability_mutations from "../v1/usability/mutations.js";
import type * as v1_usability_queries from "../v1/usability/queries.js";
import type * as v1_users_helpers from "../v1/users/helpers.js";
import type * as v1_users_internal from "../v1/users/internal.js";
import type * as v1_users_mutations from "../v1/users/mutations.js";
import type * as v1_users_queries from "../v1/users/queries.js";
import type * as v1_users_utils from "../v1/users/utils.js";
import type * as v1_voice_metrics from "../v1/voice/metrics.js";
import type * as v1_voice_sessions from "../v1/voice/sessions.js";
import type * as v1_voice_utils from "../v1/voice/utils.js";
import type * as v1_whatsapp_mutations from "../v1/whatsapp/mutations.js";
import type * as v1_whatsapp_queries from "../v1/whatsapp/queries.js";
import type * as voice_internal from "../voice/internal.js";
import type * as voice_utils from "../voice/utils.js";
import type * as whatsapp_helpers from "../whatsapp/helpers.js";
import type * as whatsapp_http from "../whatsapp/http.js";
import type * as whatsapp_internal from "../whatsapp/internal.js";
import type * as whatsapp_linking from "../whatsapp/linking.js";
import type * as whatsapp_nodeActions from "../whatsapp/nodeActions.js";
import type * as whatsapp_utils from "../whatsapp/utils.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  "agent/helpers": typeof agent_helpers;
  "agent/idempotency": typeof agent_idempotency;
  "agent/internal": typeof agent_internal;
  "agent/prompt": typeof agent_prompt;
  "agent/resolve": typeof agent_resolve;
  "agent/runner": typeof agent_runner;
  "agent/time": typeof agent_time;
  "agent/tools": typeof agent_tools;
  "agent/toolset": typeof agent_toolset;
  "agentReports/helpers": typeof agentReports_helpers;
  "agentReports/internal": typeof agentReports_internal;
  "agentReports/rateLimits": typeof agentReports_rateLimits;
  "agentReports/utils": typeof agentReports_utils;
  "agentUsage/queries": typeof agentUsage_queries;
  aggregates: typeof aggregates;
  "appUsers/helpers": typeof appUsers_helpers;
  "appUsers/internal": typeof appUsers_internal;
  auth: typeof auth;
  "authNative/http": typeof authNative_http;
  "authNative/mutations": typeof authNative_mutations;
  "authNative/rateLimits": typeof authNative_rateLimits;
  "authNative/utils": typeof authNative_utils;
  "config/helpers": typeof config_helpers;
  "config/http": typeof config_http;
  "config/utils": typeof config_utils;
  crons: typeof crons;
  "emails/helpers": typeof emails_helpers;
  "emails/internal": typeof emails_internal;
  "emails/nodeActions": typeof emails_nodeActions;
  "emails/utils": typeof emails_utils;
  "exchangeRates/helpers": typeof exchangeRates_helpers;
  "exchangeRates/http": typeof exchangeRates_http;
  "exchangeRates/internal": typeof exchangeRates_internal;
  "exchangeRates/utils": typeof exchangeRates_utils;
  "featureFlags/helpers": typeof featureFlags_helpers;
  "featureFlags/internal": typeof featureFlags_internal;
  "featureFlags/utils": typeof featureFlags_utils;
  "feedback/helpers": typeof feedback_helpers;
  "feedback/internal": typeof feedback_internal;
  "feedback/rateLimits": typeof feedback_rateLimits;
  "feedback/utils": typeof feedback_utils;
  http: typeof http;
  httpHelpers: typeof httpHelpers;
  "legal/helpers": typeof legal_helpers;
  "legal/internal": typeof legal_internal;
  "legal/validators": typeof legal_validators;
  "live/createToken": typeof live_createToken;
  "live/helpers": typeof live_helpers;
  "live/internal": typeof live_internal;
  "live/rateLimits": typeof live_rateLimits;
  migrations: typeof migrations;
  "occurrences/helpers": typeof occurrences_helpers;
  "recurrences/internal": typeof recurrences_internal;
  "recurrences/workflow": typeof recurrences_workflow;
  "schema/accounts": typeof schema_accounts;
  "schema/agentMemories": typeof schema_agentMemories;
  "schema/agentReports": typeof schema_agentReports;
  "schema/agentUsage": typeof schema_agentUsage;
  "schema/appUsers": typeof schema_appUsers;
  "schema/categories": typeof schema_categories;
  "schema/dashboard": typeof schema_dashboard;
  "schema/exchangeRates": typeof schema_exchangeRates;
  "schema/featureFlags": typeof schema_featureFlags;
  "schema/feedback": typeof schema_feedback;
  "schema/legal": typeof schema_legal;
  "schema/occurrenceClock": typeof schema_occurrenceClock;
  "schema/recurrences": typeof schema_recurrences;
  "schema/refreshTokens": typeof schema_refreshTokens;
  "schema/supportEmails": typeof schema_supportEmails;
  "schema/sync": typeof schema_sync;
  "schema/tags": typeof schema_tags;
  "schema/telemetry": typeof schema_telemetry;
  "schema/transactionTags": typeof schema_transactionTags;
  "schema/transactions": typeof schema_transactions;
  "schema/usability": typeof schema_usability;
  "schema/userDeletion": typeof schema_userDeletion;
  "schema/userSettings": typeof schema_userSettings;
  "schema/voice": typeof schema_voice;
  "schema/whatsapp": typeof schema_whatsapp;
  "support/actions": typeof support_actions;
  "support/http": typeof support_http;
  "support/internal": typeof support_internal;
  "support/utils": typeof support_utils;
  "sync/compatibility": typeof sync_compatibility;
  "sync/helpers": typeof sync_helpers;
  "tags/backfill": typeof tags_backfill;
  "tags/helpers": typeof tags_helpers;
  "telemetry/actions": typeof telemetry_actions;
  "telemetry/agentPricing": typeof telemetry_agentPricing;
  "telemetry/catalog": typeof telemetry_catalog;
  "telemetry/http": typeof telemetry_http;
  "telemetry/latency": typeof telemetry_latency;
  "telemetry/metrics": typeof telemetry_metrics;
  "telemetry/mutations": typeof telemetry_mutations;
  "telemetry/queries": typeof telemetry_queries;
  "telemetry/types": typeof telemetry_types;
  "telemetry/usageActor": typeof telemetry_usageActor;
  "telemetry/validators": typeof telemetry_validators;
  "transactions/adjustmentBackfill": typeof transactions_adjustmentBackfill;
  "transactions/backfill": typeof transactions_backfill;
  "transactions/helpers": typeof transactions_helpers;
  "usability/actions": typeof usability_actions;
  "usability/datasets": typeof usability_datasets;
  "usability/internal": typeof usability_internal;
  "usability/utils": typeof usability_utils;
  "usability/workflow": typeof usability_workflow;
  "userDeletion/helpers": typeof userDeletion_helpers;
  "userDeletion/http": typeof userDeletion_http;
  "userDeletion/internal": typeof userDeletion_internal;
  "users/helpers": typeof users_helpers;
  "v1/accounts/helpers": typeof v1_accounts_helpers;
  "v1/accounts/internal": typeof v1_accounts_internal;
  "v1/accounts/mutations": typeof v1_accounts_mutations;
  "v1/accounts/queries": typeof v1_accounts_queries;
  "v1/agentReports/mutations": typeof v1_agentReports_mutations;
  "v1/agentReports/queries": typeof v1_agentReports_queries;
  "v1/categories/mutations": typeof v1_categories_mutations;
  "v1/categories/queries": typeof v1_categories_queries;
  "v1/dashboard/helpers": typeof v1_dashboard_helpers;
  "v1/dashboard/mutations": typeof v1_dashboard_mutations;
  "v1/dashboard/queries": typeof v1_dashboard_queries;
  "v1/exchangeRates/queries": typeof v1_exchangeRates_queries;
  "v1/featureFlags/mutations": typeof v1_featureFlags_mutations;
  "v1/featureFlags/queries": typeof v1_featureFlags_queries;
  "v1/feedback/mutations": typeof v1_feedback_mutations;
  "v1/legal/mutations": typeof v1_legal_mutations;
  "v1/legal/queries": typeof v1_legal_queries;
  "v1/live/actions": typeof v1_live_actions;
  "v1/memories/mutations": typeof v1_memories_mutations;
  "v1/memories/queries": typeof v1_memories_queries;
  "v1/recurrences/mutations": typeof v1_recurrences_mutations;
  "v1/recurrences/queries": typeof v1_recurrences_queries;
  "v1/support/queries": typeof v1_support_queries;
  "v1/sync/internal": typeof v1_sync_internal;
  "v1/sync/mutations": typeof v1_sync_mutations;
  "v1/sync/queries": typeof v1_sync_queries;
  "v1/sync/validators": typeof v1_sync_validators;
  "v1/tags/mutations": typeof v1_tags_mutations;
  "v1/tags/queries": typeof v1_tags_queries;
  "v1/transactions/mutations": typeof v1_transactions_mutations;
  "v1/transactions/queries": typeof v1_transactions_queries;
  "v1/usability/mutations": typeof v1_usability_mutations;
  "v1/usability/queries": typeof v1_usability_queries;
  "v1/users/helpers": typeof v1_users_helpers;
  "v1/users/internal": typeof v1_users_internal;
  "v1/users/mutations": typeof v1_users_mutations;
  "v1/users/queries": typeof v1_users_queries;
  "v1/users/utils": typeof v1_users_utils;
  "v1/voice/metrics": typeof v1_voice_metrics;
  "v1/voice/sessions": typeof v1_voice_sessions;
  "v1/voice/utils": typeof v1_voice_utils;
  "v1/whatsapp/mutations": typeof v1_whatsapp_mutations;
  "v1/whatsapp/queries": typeof v1_whatsapp_queries;
  "voice/internal": typeof voice_internal;
  "voice/utils": typeof voice_utils;
  "whatsapp/helpers": typeof whatsapp_helpers;
  "whatsapp/http": typeof whatsapp_http;
  "whatsapp/internal": typeof whatsapp_internal;
  "whatsapp/linking": typeof whatsapp_linking;
  "whatsapp/nodeActions": typeof whatsapp_nodeActions;
  "whatsapp/utils": typeof whatsapp_utils;
}>;

/**
 * A utility for referencing Convex functions in your app's public API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = api.myModule.myFunction;
 * ```
 */
export declare const api: FilterApi<
  typeof fullApi,
  FunctionReference<any, "public">
>;

/**
 * A utility for referencing Convex functions in your app's internal API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = internal.myModule.myFunction;
 * ```
 */
export declare const internal: FilterApi<
  typeof fullApi,
  FunctionReference<any, "internal">
>;

export declare const components: {
  betterAuth: import("@convex-dev/better-auth/_generated/component.js").ComponentApi<"betterAuth">;
  migrations: import("@convex-dev/migrations/_generated/component.js").ComponentApi<"migrations">;
  rateLimiter: import("@convex-dev/rate-limiter/_generated/component.js").ComponentApi<"rateLimiter">;
  resend: import("@convex-dev/resend/_generated/component.js").ComponentApi<"resend">;
  workflow: import("@convex-dev/workflow/_generated/component.js").ComponentApi<"workflow">;
  outflowsByAccount: import("@convex-dev/aggregate/_generated/component.js").ComponentApi<"outflowsByAccount">;
  inflowsByAccount: import("@convex-dev/aggregate/_generated/component.js").ComponentApi<"inflowsByAccount">;
  transactionsByTag: import("@convex-dev/aggregate/_generated/component.js").ComponentApi<"transactionsByTag">;
  latencyByOperation: import("@convex-dev/aggregate/_generated/component.js").ComponentApi<"latencyByOperation">;
};
