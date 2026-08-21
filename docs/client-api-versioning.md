# Client API versioning

WalletBot-owned public Convex RPCs used by native or web clients live under a
version directory. V1 function names use the form
`v1/<feature>/<module>:<export>`, while generated TypeScript callers use
`api.v1.<feature>.<module>.<export>`.

There are no unversioned compatibility aliases. Breaking contracts require a
new version namespace and an explicit client migration.

## V1 public Convex RPC inventory

| Feature | Queries | Mutations / actions |
| --- | --- | --- |
| Accounts | `listActive`, `list`, `get`, `recentTransactions` | `create`, `update`, `archive` |
| Categories | `listActive`, `listActiveWithCounts`, `get`, `spendByCurrency`, `recentTransactions` | `create`, `update`, `archive` |
| Tags | `listActive`, `listActiveWithCounts`, `get`, `spendByCurrency`, `recentTransactions` | `create`, `update`, `archive` |
| Transactions | `get`, `recent`, `listPaginated`, `balance` | `createExpense`, `createIncome`, `createTransfer`, `createBalanceAdjustment`, `update`, `archive`, `tag`, `untag` |
| Sync | `getCounter`, `pull` | `push` |
| Live | — | `requestLiveToken` action |
| Voice | — | `appendEvents` mutation |
| Legal | `getMyAcceptance` | `accept` |

The native dashboard and saved-filter records are part of the V1 sync payload;
they are read through `v1/sync/queries:pull` and written through
`v1/sync/mutations:push` rather than separate public RPC modules.

## HTTP surfaces

The existing WalletBot HTTP endpoints `/v1/config`, `/v1/account-config`, and
`POST /v1/live/token` remain versioned at V1. Framework-managed authentication,
OIDC, JWKS, Better Auth, and native authentication routes keep their framework
or authentication paths and are not placed under an API version namespace.

## Native compatibility gate

Both `v1/sync/queries:pull` and `v1/sync/mutations:push` require `platform` and
`appVersion`. They validate those values against `minSupportedVersion` and
return `{ ok: false, error: 'client_outdated' }` when the client is no longer
supported. The client-side `syncAllowed` gate remains the first line of defense;
the server-side checks preserve fail-closed sync when config loading fails open.
