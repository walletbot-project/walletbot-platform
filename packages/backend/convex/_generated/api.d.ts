/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as auth from "../auth.js";
import type * as authNative_http from "../authNative/http.js";
import type * as authNative_mutations from "../authNative/mutations.js";
import type * as authNative_utils from "../authNative/utils.js";
import type * as crons from "../crons.js";
import type * as health from "../health.js";
import type * as http from "../http.js";
import type * as live_actions from "../live/actions.js";
import type * as schema_accounts from "../schema/accounts.js";
import type * as schema_categories from "../schema/categories.js";
import type * as schema_refreshTokens from "../schema/refreshTokens.js";
import type * as schema_sync from "../schema/sync.js";
import type * as schema_tags from "../schema/tags.js";
import type * as schema_transactionTags from "../schema/transactionTags.js";
import type * as schema_transactions from "../schema/transactions.js";
import type * as test from "../test.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  auth: typeof auth;
  "authNative/http": typeof authNative_http;
  "authNative/mutations": typeof authNative_mutations;
  "authNative/utils": typeof authNative_utils;
  crons: typeof crons;
  health: typeof health;
  http: typeof http;
  "live/actions": typeof live_actions;
  "schema/accounts": typeof schema_accounts;
  "schema/categories": typeof schema_categories;
  "schema/refreshTokens": typeof schema_refreshTokens;
  "schema/sync": typeof schema_sync;
  "schema/tags": typeof schema_tags;
  "schema/transactionTags": typeof schema_transactionTags;
  "schema/transactions": typeof schema_transactions;
  test: typeof test;
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
};
