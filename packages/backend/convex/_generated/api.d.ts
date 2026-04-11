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
import type * as expenses_constants from "../expenses/constants.js";
import type * as expenses_helpers from "../expenses/helpers.js";
import type * as expenses_mutations from "../expenses/mutations.js";
import type * as expenses_queries from "../expenses/queries.js";
import type * as http from "../http.js";
import type * as live_actions from "../live/actions.js";
import type * as schema_expenses from "../schema/expenses.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  auth: typeof auth;
  "expenses/constants": typeof expenses_constants;
  "expenses/helpers": typeof expenses_helpers;
  "expenses/mutations": typeof expenses_mutations;
  "expenses/queries": typeof expenses_queries;
  http: typeof http;
  "live/actions": typeof live_actions;
  "schema/expenses": typeof schema_expenses;
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
