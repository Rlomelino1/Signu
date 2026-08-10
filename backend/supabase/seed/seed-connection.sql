-- Seed one CONNECTION row by hand.
--
-- DELIBERATE STOPGAP, not the intended path. The real flow is Pluggy Connect
-- inside the SwiftUI app writing this row when the user links a bank — that
-- screen is not designed yet, so the item was created by hand through the
-- hosted widget and its id is transcribed here.
--
-- Written as a committed, parameterized script rather than an INSERT typed once
-- into psql, because a manual step that exists only in shell history is
-- invisible in exactly the way this project keeps getting bitten by. When the
-- in-app connect flow lands, this file is deleted, not adapted.
--
-- The itemId is passed in rather than hardcoded so it stays out of a public repo.
--
-- Usage (from backend/):
--   psql "$SUPABASE_DB_URL" \
--     -v item_id="<your Pluggy itemId>" \
--     -v user_email="you@example.com" \
--     -f supabase/seed/seed-connection.sql
--
-- psql is not installed on the dev machine this was written on, so against a
-- local stack go through the container instead (same script, same variables):
--
--   docker exec -i supabase_db_backend psql -U postgres -d postgres \
--     -v item_id="<your Pluggy itemId>" \
--     -v user_email="you@example.com" \
--     < supabase/seed/seed-connection.sql
--
-- Idempotent: re-running with the same item_id updates rather than duplicating,
-- which UNIQUE (user_id, provider_connection_id) would reject anyway.

\if :{?item_id}
\else
  \echo 'ERROR: pass -v item_id="<Pluggy itemId>"'
  \quit
\endif

\if :{?user_email}
\else
  \echo 'ERROR: pass -v user_email="you@example.com"'
  \quit
\endif

begin;

with target_user as (
  select id
  from auth.users
  where email = :'user_email'
)
insert into public.connection (
  user_id,
  provider_connection_id,
  institution_id,
  institution_name,
  status,
  consent_expires_at,
  last_synced_at,
  last_sync_error
)
select
  target_user.id,
  :'item_id',
  -- Connector 200 = MeuPluggy, the free own-accounts proxy. It reports
  -- isOpenFinance = false, yet still passes Open-Finance-only fields such as
  -- billId through (v20) — so the flag is not a capability guarantee.
  '200',
  'MeuPluggy',
  -- 'active' is a claim, so it is the weakest thing we can honestly say here:
  -- the row is only truly active once pluggy-sync has reached the item. The
  -- first sync overwrites status from the live item state, and writes
  -- last_synced_at with it.
  'needs_action',
  null,   -- consent_expires_at: sync fills this from the item
  null,   -- last_synced_at: never synced yet, and saying otherwise would lie
  null
from target_user
on conflict (user_id, provider_connection_id) do update
  set institution_id   = excluded.institution_id,
      institution_name = excluded.institution_name;

-- Fails loudly rather than silently seeding nothing if the email does not match
-- a row in auth.users (wrong project, or the user was never created).
do $$
begin
  if not exists (select 1 from public.connection) then
    raise exception
      'no connection row was created — does the user_email exist in auth.users?';
  end if;
end $$;

commit;

\echo ''
\echo 'Seeded. Verify with:'
\echo '  select id, institution_name, status, last_synced_at from public.connection;'
\echo ''
