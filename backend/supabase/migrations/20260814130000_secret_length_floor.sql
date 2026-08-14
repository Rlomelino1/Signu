-- Migration #10 — the secret length floor, which #9 left behind
-- Source of truth: subscription-tracker-data-model.md (v44, 2026-08-14)
--
-- ADDITIVE ONLY: the same two `create or replace function` bodies as Migration
-- #9, now including the guard. No table, column, constraint, index, RLS policy,
-- grant or cron entry is touched.
--
-- WHY THIS IS A SECOND MIGRATION AND NOT AN EDIT TO #9
--
-- Because #9 was already applied, and **`supabase db push` tracks migration
-- versions, not their contents**. Version 20260814120000 was recorded in
-- `supabase_migrations.schema_migrations` while the file still held only the
-- timeout change; the length floor was added to that same file minutes later.
-- Every later `db push` then reported "Remote database is up to date" and applied
-- nothing, because the version was already in the ledger. Editing an applied
-- migration does not re-apply it -- it just makes the repo disagree with the
-- database in a way that no command reports.
--
-- The divergence was real and was caught by reading production rather than
-- trusting the ledger: `supabase db dump --schema public` showed
-- `timeout_milliseconds := 150000` present in both triggers and the
-- `length(v_secret)` guard absent. CI's `Schema applies` gate could never have
-- caught it -- it builds from scratch, where #9's edited file is complete and
-- correct. The gap only exists on a database that applied the earlier version,
-- which is to say: only in production.
--
-- Re-running is harmless in both directions. On a from-scratch database #9
-- already produces these exact bodies and this migration replaces them with
-- identical text; on production it adds the missing guard. `create or replace`
-- is idempotent, so the two orders converge.
--
-- WHAT THE GUARD IS FOR (v42, in full there)
--
-- The Vault copy of `signu_sync_secret` held four characters -- the literal
-- placeholder from a paste that never happened -- so every scheduled POST was
-- rejected at `pluggy-sync`'s gate with HTTP 403 for three days while cron
-- reported "succeeded". A 403 is invisible from inside Postgres. This makes the
-- mangled-paste case fail as a FAILED cron run on the first firing instead.

create or replace function public.trigger_pluggy_sync()
returns bigint
language plpgsql
security definer
set search_path = public, extensions, vault, pg_temp
as $$
declare
  v_url    text;
  v_secret text;
  v_id     bigint;
begin
  select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'signu_sync_url';
  select decrypted_secret into v_secret
    from vault.decrypted_secrets where name = 'signu_sync_secret';

  -- Loud, not silent. An unconfigured schedule that quietly does nothing is
  -- indistinguishable from a working one until someone notices stale data.
  if v_url is null then
    raise exception
      'vault secret "signu_sync_url" is not set -- see Migration #6 header';
  end if;
  if v_secret is null then
    raise exception
      'vault secret "signu_sync_secret" is not set -- see Migration #6 header';
  end if;
  -- A FLOOR, not a format assertion. 32 is "this is obviously not a secret",
  -- chosen low enough that a future rotation to a shorter secret is not broken
  -- by this line. It cannot catch a wrong-but-plausible value; the read-back
  -- against `supabase secrets list` is what covers that.
  if length(v_secret) < 32 then
    raise exception
      'vault secret "signu_sync_secret" is % chars -- too short to be the '
      'SYNC_SECRET the functions expect; a paste probably failed. Read it back '
      'against `supabase secrets list` before trusting it (v42).',
      length(v_secret);
  end if;

  select net.http_post(
           url     := v_url,
           headers := jsonb_build_object(
                        'Content-Type', 'application/json',
                        'x-sync-secret', v_secret
                      ),
           body    := '{}'::jsonb,
           -- Migration #9. The default 5000 is shorter than the work: a
           -- successful sync chains detection and takes ~7s, so the default
           -- overwrote every real status with a timeout.
           timeout_milliseconds := 150000
         )
    into v_id;

  return v_id;
end;
$$;

revoke all on function public.trigger_pluggy_sync() from public;
revoke all on function public.trigger_pluggy_sync() from anon, authenticated;

create or replace function public.trigger_send_reminders()
returns bigint
language plpgsql
security definer
set search_path = public, extensions, vault, pg_temp
as $$
declare
  v_url    text;
  v_secret text;
  v_id     bigint;
begin
  select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'signu_reminders_url';
  select decrypted_secret into v_secret
    from vault.decrypted_secrets where name = 'signu_sync_secret';

  if v_url is null then
    raise exception
      'vault secret "signu_reminders_url" is not set -- see Migration #7 header';
  end if;
  if v_secret is null then
    raise exception
      'vault secret "signu_sync_secret" is not set -- see Migration #6 header';
  end if;
  -- Same floor as the sync trigger, and for the same reason: both schedules read
  -- the same Vault row, so a mangled paste silences reminders too. It did.
  if length(v_secret) < 32 then
    raise exception
      'vault secret "signu_sync_secret" is % chars -- too short to be the '
      'SYNC_SECRET the functions expect; a paste probably failed. Read it back '
      'against `supabase secrets list` before trusting it (v42).',
      length(v_secret);
  end if;

  select net.http_post(
           url     := v_url,
           headers := jsonb_build_object(
                        'Content-Type', 'application/json',
                        'x-sync-secret', v_secret
                      ),
           body    := '{}'::jsonb,
           -- Same deadline as the sync, for the same reason: one rule, not two.
           timeout_milliseconds := 150000
         )
    into v_id;

  return v_id;
end;
$$;

revoke all on function public.trigger_send_reminders() from public;
revoke all on function public.trigger_send_reminders() from anon, authenticated;
