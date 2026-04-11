# Journal

## 2026-04-11 — Cleanup: auth, page unification, route simplification

### What was done

**Backend — auth enforcement:**
- Removed `userId` from all expense query/mutation args. Backend now derives user identity from `authComponent.getAuthUser(ctx)` instead of trusting client-provided userId.
- Auth-protected `requestLiveToken` action via `ctx.auth.getUserIdentity()`.
- Removed `MOCK_USER_ID` constant from backend.

**Frontend — page unification:**
- Merged expenses page, voice assistant (live-demo-cloud), and home page into a single unified dashboard at `/` behind AuthGuard.
- Dashboard uses tabs to switch between "Expenses" and "Voice Assistant" panels.
- Deleted `expenses.tsx`, `live-demo.tsx`, `live-demo-cloud.tsx` pages.
- Removed `MOCK_USER_ID` from frontend code.
- Updated `expense-tools.ts` to accept both `ConvexClient` and `ConvexReactClient` (voice assistant now uses authenticated Convex React client instead of standalone `ConvexHttpClient`).

**Router cleanup:**
- Removed 3 public routes (`/live-demo`, `/live-demo-cloud`, `/expenses`).
- Final routes: `/login` (public), `/` (protected dashboard), `/*` (404).

### Lessons for future reference
- `authComponent.getAuthUser(ctx)` works in queries/mutations but not in actions (actions have `ActionCtx`, not `QueryCtx`). For actions, use `ctx.auth.getUserIdentity()` directly.
- `ConvexReactClient` (from `useConvex()`) has the same `.query()/.mutation()/.action()` methods as `ConvexHttpClient`, so tool execution code can work with either client type.

## 2026-04-11 — Voice assistant: compact UI, mic selector, full tool suite

### What was done

**UI — compact voice bar:**
- Replaced tabs with inline voice bar in expenses card header (connect, mute, mic selector dropdown).
- Removed all debug UI (transcript, tool call display, turn status, mic level meter).
- Added microphone device selector dropdown using shadcn DropdownMenu with radio items.
- Mic list auto-refreshes on `devicechange` events; switching mic while connected restarts capture.

**Tools — full CRUD + filtering:**
- Added `updateExpense` mutation (auth-protected, partial update via `db.patch`).
- Added `updateExpense` tool declaration for Gemini voice assistant.
- Added optional `category` filter to `listExpensesByDateRange` and `getExpenseSummary` queries (in-memory filter on top of date-range index query, capped at 500).
- Updated tool declarations for `listExpenses` and `getExpenseSummary` to include `category` enum parameter.
- Rewrote system prompt to be comprehensive: lists all capabilities, categories, currencies, and behavioral rules (e.g. "list first to get ID before edit/delete").

### Lessons for future reference
- `DropdownMenuLabel` in shadcn (base-ui) must be inside a `DropdownMenuGroup` — otherwise throws `MenuGroupRootContext is missing`.
- For category filtering alongside date-range index queries, in-memory `.filter()` on the already-capped result set is simpler and good enough vs. a compound index.
