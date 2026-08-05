/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as aggregates from "../aggregates.js";
import type * as auth from "../auth.js";
import type * as authNative_http from "../authNative/http.js";
import type * as authNative_mutations from "../authNative/mutations.js";
import type * as authNative_utils from "../authNative/utils.js";
import type * as config_helpers from "../config/helpers.js";
import type * as config_http from "../config/http.js";
import type * as config_utils from "../config/utils.js";
import type * as crons from "../crons.js";
import type * as emails_helpers from "../emails/helpers.js";
import type * as emails_internal from "../emails/internal.js";
import type * as emails_utils from "../emails/utils.js";
import type * as http from "../http.js";
import type * as httpHelpers from "../httpHelpers.js";
import type * as live_createToken from "../live/createToken.js";
import type * as schema_accounts from "../schema/accounts.js";
import type * as schema_categories from "../schema/categories.js";
import type * as schema_dashboard from "../schema/dashboard.js";
import type * as schema_refreshTokens from "../schema/refreshTokens.js";
import type * as schema_sync from "../schema/sync.js";
import type * as schema_tags from "../schema/tags.js";
import type * as schema_transactionTags from "../schema/transactionTags.js";
import type * as schema_transactions from "../schema/transactions.js";
import type * as schema_voice from "../schema/voice.js";
import type * as sync_helpers from "../sync/helpers.js";
import type * as transactions_backfill from "../transactions/backfill.js";
import type * as users_helpers from "../users/helpers.js";
import type * as v1_accounts_mutations from "../v1/accounts/mutations.js";
import type * as v1_accounts_queries from "../v1/accounts/queries.js";
import type * as v1_categories_mutations from "../v1/categories/mutations.js";
import type * as v1_categories_queries from "../v1/categories/queries.js";
import type * as v1_live_actions from "../v1/live/actions.js";
import type * as v1_sync_mutations from "../v1/sync/mutations.js";
import type * as v1_sync_queries from "../v1/sync/queries.js";
import type * as v1_tags_mutations from "../v1/tags/mutations.js";
import type * as v1_tags_queries from "../v1/tags/queries.js";
import type * as v1_transactions_mutations from "../v1/transactions/mutations.js";
import type * as v1_transactions_queries from "../v1/transactions/queries.js";
import type * as v1_voice_sessions from "../v1/voice/sessions.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  aggregates: typeof aggregates;
  auth: typeof auth;
  "authNative/http": typeof authNative_http;
  "authNative/mutations": typeof authNative_mutations;
  "authNative/utils": typeof authNative_utils;
  "config/helpers": typeof config_helpers;
  "config/http": typeof config_http;
  "config/utils": typeof config_utils;
  crons: typeof crons;
  "emails/helpers": typeof emails_helpers;
  "emails/internal": typeof emails_internal;
  "emails/utils": typeof emails_utils;
  http: typeof http;
  httpHelpers: typeof httpHelpers;
  "live/createToken": typeof live_createToken;
  "schema/accounts": typeof schema_accounts;
  "schema/categories": typeof schema_categories;
  "schema/dashboard": typeof schema_dashboard;
  "schema/refreshTokens": typeof schema_refreshTokens;
  "schema/sync": typeof schema_sync;
  "schema/tags": typeof schema_tags;
  "schema/transactionTags": typeof schema_transactionTags;
  "schema/transactions": typeof schema_transactions;
  "schema/voice": typeof schema_voice;
  "sync/helpers": typeof sync_helpers;
  "transactions/backfill": typeof transactions_backfill;
  "users/helpers": typeof users_helpers;
  "v1/accounts/mutations": typeof v1_accounts_mutations;
  "v1/accounts/queries": typeof v1_accounts_queries;
  "v1/categories/mutations": typeof v1_categories_mutations;
  "v1/categories/queries": typeof v1_categories_queries;
  "v1/live/actions": typeof v1_live_actions;
  "v1/sync/mutations": typeof v1_sync_mutations;
  "v1/sync/queries": typeof v1_sync_queries;
  "v1/tags/mutations": typeof v1_tags_mutations;
  "v1/tags/queries": typeof v1_tags_queries;
  "v1/transactions/mutations": typeof v1_transactions_mutations;
  "v1/transactions/queries": typeof v1_transactions_queries;
  "v1/voice/sessions": typeof v1_voice_sessions;
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
  resend: import("@convex-dev/resend/_generated/component.js").ComponentApi<"resend">;
  outflowsByAccount: import("@convex-dev/aggregate/_generated/component.js").ComponentApi<"outflowsByAccount">;
  inflowsByAccount: import("@convex-dev/aggregate/_generated/component.js").ComponentApi<"inflowsByAccount">;
};
