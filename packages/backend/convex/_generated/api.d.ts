/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as accounts_helpers from "../accounts/helpers.js";
import type * as accounts_mutations from "../accounts/mutations.js";
import type * as accounts_queries from "../accounts/queries.js";
import type * as auth from "../auth.js";
import type * as categories_helpers from "../categories/helpers.js";
import type * as categories_mutations from "../categories/mutations.js";
import type * as categories_queries from "../categories/queries.js";
import type * as crons from "../crons.js";
import type * as currencies_actions from "../currencies/actions.js";
import type * as currencies_internal from "../currencies/internal.js";
import type * as currencies_mutations from "../currencies/mutations.js";
import type * as currencies_queries from "../currencies/queries.js";
import type * as expenses_constants from "../expenses/constants.js";
import type * as expenses_helpers from "../expenses/helpers.js";
import type * as expenses_mutations from "../expenses/mutations.js";
import type * as expenses_queries from "../expenses/queries.js";
import type * as http from "../http.js";
import type * as lib_auth from "../lib/auth.js";
import type * as lib_validators from "../lib/validators.js";
import type * as live_actions from "../live/actions.js";
import type * as recurrences_internal from "../recurrences/internal.js";
import type * as recurrences_mutations from "../recurrences/mutations.js";
import type * as recurrences_queries from "../recurrences/queries.js";
import type * as schema_accounts from "../schema/accounts.js";
import type * as schema_categories from "../schema/categories.js";
import type * as schema_currencies from "../schema/currencies.js";
import type * as schema_expenses from "../schema/expenses.js";
import type * as schema_recurrences from "../schema/recurrences.js";
import type * as schema_tags from "../schema/tags.js";
import type * as schema_transactions from "../schema/transactions.js";
import type * as settings_mutations from "../settings/mutations.js";
import type * as settings_queries from "../settings/queries.js";
import type * as tags_helpers from "../tags/helpers.js";
import type * as tags_mutations from "../tags/mutations.js";
import type * as tags_queries from "../tags/queries.js";
import type * as transactions_helpers from "../transactions/helpers.js";
import type * as transactions_mutations from "../transactions/mutations.js";
import type * as transactions_queries from "../transactions/queries.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  "accounts/helpers": typeof accounts_helpers;
  "accounts/mutations": typeof accounts_mutations;
  "accounts/queries": typeof accounts_queries;
  auth: typeof auth;
  "categories/helpers": typeof categories_helpers;
  "categories/mutations": typeof categories_mutations;
  "categories/queries": typeof categories_queries;
  crons: typeof crons;
  "currencies/actions": typeof currencies_actions;
  "currencies/internal": typeof currencies_internal;
  "currencies/mutations": typeof currencies_mutations;
  "currencies/queries": typeof currencies_queries;
  "expenses/constants": typeof expenses_constants;
  "expenses/helpers": typeof expenses_helpers;
  "expenses/mutations": typeof expenses_mutations;
  "expenses/queries": typeof expenses_queries;
  http: typeof http;
  "lib/auth": typeof lib_auth;
  "lib/validators": typeof lib_validators;
  "live/actions": typeof live_actions;
  "recurrences/internal": typeof recurrences_internal;
  "recurrences/mutations": typeof recurrences_mutations;
  "recurrences/queries": typeof recurrences_queries;
  "schema/accounts": typeof schema_accounts;
  "schema/categories": typeof schema_categories;
  "schema/currencies": typeof schema_currencies;
  "schema/expenses": typeof schema_expenses;
  "schema/recurrences": typeof schema_recurrences;
  "schema/tags": typeof schema_tags;
  "schema/transactions": typeof schema_transactions;
  "settings/mutations": typeof settings_mutations;
  "settings/queries": typeof settings_queries;
  "tags/helpers": typeof tags_helpers;
  "tags/mutations": typeof tags_mutations;
  "tags/queries": typeof tags_queries;
  "transactions/helpers": typeof transactions_helpers;
  "transactions/mutations": typeof transactions_mutations;
  "transactions/queries": typeof transactions_queries;
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
