-- Migration #6 — the daily sync schedule
-- Source of truth: subscription-tracker-data-model.md (v27, 2026-08-10)
--
-- ADDITIVE ONLY. Two extensions, one function, one cron entry. No table, column,
-- constraint, index or RLS policy is touched.
--
-- WHY A MIGRATION AND NOT DASHBOARD CONFIG
--
-- Both Edge Functions were written for cron, the sync contract discusses cron,
-- and no cron existed -- the schedule was the one part of the pipeline living
-- only in prose. Put here rather than in dashboard config for the same reason
-- Migration #4 exists: it is versioned with everything else, it survives a
-- rebuild, and `supabase db reset` reproduces it. A schedule that lives in a
-- dashboard drifts invisibly from the spec, which is what v17's discipline was
-- written about.
--
-- WHAT IT DOES NOT CONTAIN, AND CANNOT
--
-- The function URL and the shared secret are NOT in this file. The URL differs
-- between local and hosted; the secret must never enter a public repo. Both are
-- read from Vault by NAME, so this migration is environment-independent and
-- committing it leaks nothing.
--
-- TWO MANUAL STEPS ARE REQUIRED, ONCE PER ENVIRONMENT. Until they are done the
-- job is scheduled and will fail loudly when it fires, which is the intended
-- failure mode -- a job that silently no-ops reads as a job that works:
--
--   select vault.create_secret('https://<ref>.supabase.co/functions/v1/pluggy-sync',
--                              'signu_sync_url');
--   select vault.create_secret('<the SYNC_SECRET value>', 'signu_sync_secret');
--
-- Verified before writing: pg_cron 1.6.4 is available and IS present in
-- shared_preload_libraries, so the scheduler genuinely runs rather than the
-- extension merely installing; pg_net is already installed; vault.decrypted_secrets
-- exists; and `create extension` emits no NOTICE or WARNING, so the v18 CI
-- warning gate stays green.

create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron;

-- The cron entry calls this rather than inlining the request, so that a missing
-- secret produces a legible error instead of an http_post to a null URL, and so
-- the sync can be fired by hand for testing:  select public.trigger_pluggy_sync();
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

  select net.http_post(
           url     := v_url,
           headers := jsonb_build_object(
                        'Content-Type', 'application/json',
                        'x-sync-secret', v_secret
                      ),
           body    := '{}'::jsonb
         )
    into v_id;

  return v_id;
end;
$$;

revoke all on function public.trigger_pluggy_sync() from public;
revoke all on function public.trigger_pluggy_sync() from anon, authenticated;

-- 15:30 UTC daily. Deliberately AFTER the upstream refresh rather than at a
-- round hour: the item's nextAutoSyncAt lands about 14:42Z, so syncing before it
-- would read yesterday's data and the freshness would be a day behind for no
-- reason (v22). Sync chains into detection on success, so this one entry drives
-- the whole pipeline.
--
-- Re-running this migration is safe: pg_cron upserts on jobname, so `db reset`
-- reproduces exactly one entry rather than accumulating duplicates.
select cron.schedule(
  'signu-daily-sync',
  '30 15 * * *',
  $$select public.trigger_pluggy_sync();$$
);
