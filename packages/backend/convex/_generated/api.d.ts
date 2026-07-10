/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as accounts_mutations from "../accounts/mutations.js";
import type * as accounts_queries from "../accounts/queries.js";
import type * as aggregates from "../aggregates.js";
import type * as auth from "../auth.js";
import type * as authNative_http from "../authNative/http.js";
import type * as authNative_mutations from "../authNative/mutations.js";
import type * as authNative_utils from "../authNative/utils.js";
import type * as categories_mutations from "../categories/mutations.js";
import type * as categories_queries from "../categories/queries.js";
import type * as crons from "../crons.js";
import type * as http from "../http.js";
import type * as live_actions from "../live/actions.js";
import type * as schema_accounts from "../schema/accounts.js";
import type * as schema_categories from "../schema/categories.js";
import type * as schema_dashboard from "../schema/dashboard.js";
import type * as schema_refreshTokens from "../schema/refreshTokens.js";
import type * as schema_sync from "../schema/sync.js";
import type * as schema_tags from "../schema/tags.js";
import type * as schema_telemetry from "../schema/telemetry.js";
import type * as schema_transactionTags from "../schema/transactionTags.js";
import type * as schema_transactions from "../schema/transactions.js";
import type * as sync_helpers from "../sync/helpers.js";
import type * as sync_mutations from "../sync/mutations.js";
import type * as sync_queries from "../sync/queries.js";
import type * as tags_mutations from "../tags/mutations.js";
import type * as tags_queries from "../tags/queries.js";
import type * as telemetry_actions from "../telemetry/actions.js";
import type * as telemetry_http from "../telemetry/http.js";
import type * as telemetry_mutations from "../telemetry/mutations.js";
import type * as telemetry_queries from "../telemetry/queries.js";
import type * as telemetry_types from "../telemetry/types.js";
import type * as telemetry_validators from "../telemetry/validators.js";
import type * as test from "../test.js";
import type * as transactions_backfill from "../transactions/backfill.js";
import type * as transactions_mutations from "../transactions/mutations.js";
import type * as transactions_queries from "../transactions/queries.js";
import type * as users_helpers from "../users/helpers.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  "accounts/mutations": typeof accounts_mutations;
  "accounts/queries": typeof accounts_queries;
  aggregates: typeof aggregates;
  auth: typeof auth;
  "authNative/http": typeof authNative_http;
  "authNative/mutations": typeof authNative_mutations;
  "authNative/utils": typeof authNative_utils;
  "categories/mutations": typeof categories_mutations;
  "categories/queries": typeof categories_queries;
  crons: typeof crons;
  http: typeof http;
  "live/actions": typeof live_actions;
  "schema/accounts": typeof schema_accounts;
  "schema/categories": typeof schema_categories;
  "schema/dashboard": typeof schema_dashboard;
  "schema/refreshTokens": typeof schema_refreshTokens;
  "schema/sync": typeof schema_sync;
  "schema/tags": typeof schema_tags;
  "schema/telemetry": typeof schema_telemetry;
  "schema/transactionTags": typeof schema_transactionTags;
  "schema/transactions": typeof schema_transactions;
  "sync/helpers": typeof sync_helpers;
  "sync/mutations": typeof sync_mutations;
  "sync/queries": typeof sync_queries;
  "tags/mutations": typeof tags_mutations;
  "tags/queries": typeof tags_queries;
  "telemetry/actions": typeof telemetry_actions;
  "telemetry/http": typeof telemetry_http;
  "telemetry/mutations": typeof telemetry_mutations;
  "telemetry/queries": typeof telemetry_queries;
  "telemetry/types": typeof telemetry_types;
  "telemetry/validators": typeof telemetry_validators;
  test: typeof test;
  "transactions/backfill": typeof transactions_backfill;
  "transactions/mutations": typeof transactions_mutations;
  "transactions/queries": typeof transactions_queries;
  "users/helpers": typeof users_helpers;
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
  outflowsByAccount: import("@convex-dev/aggregate/_generated/component.js").ComponentApi<"outflowsByAccount">;
  inflowsByAccount: import("@convex-dev/aggregate/_generated/component.js").ComponentApi<"inflowsByAccount">;
};
