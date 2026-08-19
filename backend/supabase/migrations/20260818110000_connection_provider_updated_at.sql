
alter table public.connection
  add column if not exists provider_updated_at timestamptz;

comment on column public.connection.provider_updated_at is
  'Pluggy''s own `item.lastUpdatedAt`: when the PROVIDER last refreshed this item '
  'from the institution. Distinct from `last_synced_at`, which is when WE last read '
  'Pluggy. Data freshness is bounded by both, so the app shows the older of the two. '
  'Sync-owned (service_role); null until the next sync, and never backfilled -- a '
  'value copied from last_synced_at would be the very claim this column retires.';
