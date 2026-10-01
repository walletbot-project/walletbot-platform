# Native backward compatibility — PR #263

## Accepted behavior

The minimum native version remains **0.3.0**; the new app is **0.4.0+9**.
Older clients keep syncing without a mandatory upgrade. They receive future
movements and their tags immediately, as ordinary rows without recurrence
metadata. **Their activity, balances and summaries may include future amounts.**
This limitation is explicitly accepted in exchange for a simpler contract.

There is **no recurrence publication cron, delayed delivery job or backfill**.
The old publication code and queue index were removed. The optional
`legacyPendingDate` field and `occurrenceClock` table remain inert schema
compatibility declarations because an earlier development deployment wrote
those values. No code maintains or reads the clock; the field is stripped
from sync responses. Other features' existing jobs are unchanged.

Older edits preserve the canonical series metadata; an old deletion affects
only that movement. On v4→v5 upgrade, sync replays without clearing local data
or pending writes, then hydrates recurrence metadata. Existing web arguments
remain valid without `asOfMs`; their fallback recalculates when the query runs,
so an old cached subscription may need a normal invalidation or reload.

WhatsApp writes use the shared transaction helpers. Its activity, summaries,
balances and adjustments respect the current occurrence cutoff. Unsupported
recurrence/scope arguments are omitted from its declarations and rejected
before a write, and its skill index/read endpoint omit the recurrence guide.

## Correctness fixes

- Native date-only recurrence end dates normalize to the end of the selected
  local day. Precise stored rule boundaries used for truncation are unchanged.
- Native custom-day input validates the visible text and blocks saving empty,
  zero or otherwise invalid values. It cannot silently save a previous value.
- Web future-movement edits preserve the original timestamp and confidence
  unless the corresponding date/time controls change. Amount-only edits use
  the existing update path instead of splitting and shortening the series.

## Current automated validation (2026-09-13)

All checks passed: **687 native tests**, **118 backend tests**, **13 web tests**,
workspace TypeScript checks, web lint and `flutter analyze`. The separate
original-client v4 sync test described below also passed. Formatting and
`git diff --check` passed for the changed files.

The regression suites cover:

- Old native wire shapes, future rows/tags delivered immediately, pagination
  through hidden recurrence rules, legacy edits/deletes, future write
  acknowledgements, upgrade replay and retired schema metadata.
- Two future WhatsApp writes delivered together without publication jobs,
  existing tags retained on date edits, current-client cutoff reads, balance
  adjustments and rejection of unsupported series operations.
- Native form submission from January 31 through May 31, 2028, at noon: five
  occurrences including February 29 and the full last day. Empty, `0` and `00`
  custom intervals cannot save; valid replacement input does save. Both light
  and dark themes are exercised.
- Web unchanged timestamp precision and confidence, plus independent calendar
  date and clock edits. Preserving the timestamp prevents an amount-only edit
  from selecting the series-split path.

A separate temporary checkout of native **0.3.2 from main (`34829d3`)** ran its
original v4 database and `PullPageMerger`. It accepted a future movement and
tag, applied an amount update, and applied deletion without errors. This was
an automated test of the published code, not a fresh physical-device session.

## Earlier physical-device evidence

Before the no-publication simplification, an isolated Pixel 8 Pro test used
0.3.2's original database, sync engine, merger, serializer and balance code.
It verified an offline edit surviving sync and a v4→v5 upgrade preserving the
same local database and hydrating series metadata. Those data-preservation
paths remain unchanged. Its former timed-delivery/balance observations do
**not** describe the current accepted behavior.

The temporary phone package and financial QA data were removed after that
session. This revision did not modify the user's phone or financial data.
Production was not deployed.
