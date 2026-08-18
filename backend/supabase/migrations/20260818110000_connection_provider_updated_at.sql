-- Migration #17 — the app can say how old the DATA is, not how recently we looked
-- Source of truth: subscription-tracker-data-model.md (v65, 2026-08-18)
--
-- ADDITIVE. One nullable column on `connection`. No table, constraint, index,
-- policy or grant is touched, and no existing column changes meaning.
--
-- WHAT WAS WRONG WITH "UPDATED 3H AGO"
--
-- `last_synced_at` is written as `new Date()` at the end of a sync -- OUR clock, at
-- the moment WE finished reading Pluggy. Home renders it as "Updated 3h ago", which
-- reads as a claim about the data and is in fact a claim about our own polling.
--
-- The two diverge exactly when it matters. Pluggy auto-syncs an item roughly every
-- 24h, so on 2026-08-18 the item's own data was last refreshed at 15:01Z while our
-- read happened at 15:30Z: the app would say "Updated 5m ago" about data that was
-- already 29 minutes stale at best, and on a day when Pluggy's own sync failed it
-- would keep saying "Updated 5m ago" about data frozen a day earlier. A freshness
-- label that cannot express staleness is worse than none: it actively argues against
-- the user's own suspicion that something is behind.
--
-- `pluggy-sync` ALREADY fetches `GET /items/{id}` and already reads
-- `consentExpiresAt` and `connector.name` off it. `lastUpdatedAt` sits in the same
-- response and was being discarded, so this is one assignment plus somewhere to put
-- it.
--
-- SYNC-OWNED, LIKE EVERY OTHER COLUMN ON THIS TABLE
--
-- Written only by `pluggy-sync` under the service role. The client's column-scoped
-- UPDATE grants (Migration #1, seven user-owned columns) are untouched, so a new
-- column arrives read-only to `authenticated` with no grant change -- the same
-- property Migration #11 relied on for `remind_before_days`.
--
-- NULLABLE ON PURPOSE, AND NOT BACKFILLED
--
-- Null means "we have never recorded what Pluggy said", which is true of every row
-- until the next sync and stays true for any provider response that omits the field.
-- The client falls back to `last_synced_at` in that case rather than inventing a
-- freshness it cannot support. Backfilling from `last_synced_at` would manufacture
-- exactly the false claim this column exists to retire.

alter table public.connection
  add column if not exists provider_updated_at timestamptz;

comment on column public.connection.provider_updated_at is
  'Pluggy''s own `item.lastUpdatedAt`: when the PROVIDER last refreshed this item '
  'from the institution. Distinct from `last_synced_at`, which is when WE last read '
  'Pluggy. Data freshness is bounded by both, so the app shows the older of the two. '
  'Sync-owned (service_role); null until the next sync, and never backfilled -- a '
  'value copied from last_synced_at would be the very claim this column retires.';
