-- Migration #9 — the scheduled POST must outlive the work it triggers
-- Source of truth: subscription-tracker-data-model.md (v42, 2026-08-14)
--
-- ADDITIVE ONLY, and narrower than that: two `create or replace function`
-- bodies, gaining one argument and one guard each. No table, column, constraint,
-- index, RLS policy, grant or cron entry is touched. The schedules, the Vault
-- names and the revokes from Migration #6 and #7 all stand exactly as written.
--
-- WHAT WAS WRONG
--
-- `net.http_post` was called without `timeout_milliseconds`, so it took pg_net's
-- default of **5000 ms**. The work behind that URL does not fit in five seconds
-- and never did: measured on 2026-08-14, `pluggy-sync` stamped the connection at
-- 3.9s and its chained `run-detection` finished rewriting charges at ~6.6s. So
-- every successful daily sync recorded `status_code = null` with
-- `error_msg = 'Timeout of 5000 ms reached'`.
--
-- THE DAMAGE WAS TO EVIDENCE, NOT TO THE SYNC
--
-- Verified rather than assumed, because the two have opposite fixes: pg_net
-- giving up does NOT abort the Edge Function. Detection wrote to the database
-- 1.9s AFTER pg_net recorded the timeout, so the run completed in full while the
-- caller was told it had not. Nothing here is a retry or a repair.
--
-- What broke was the only durable record of what the schedule achieved.
-- `cron.job_run_details` cannot fill that gap: `trigger_pluggy_sync()` returns
-- the moment pg_net *queues* the request, so its "succeeded" describes the
-- queueing and would read the same for a 200, a 403 or a DNS failure. The HTTP
-- status lands in `net._http_response` and nowhere else -- and with a guaranteed
-- timeout written over it, that row said nothing either.
--
-- This is not hypothetical. It is how **three days of HTTP 403** passed unnoticed
-- between 2026-08-11 and 2026-08-13: the Vault copy of the shared secret had been
-- overwritten with a 4-character paste artefact ~108 seconds after the manual
-- test that proved the chain worked, and every firing since was rejected at
-- `pluggy-sync`'s gate. The schedule fired on time, every run reported success,
-- and the app's own "Updated 2d ago" label was the only thing that ever said
-- otherwise. Migration #6 was careful to make a MISSING secret loud; a WRONG one
-- was silent.
--
-- WHY 150000
--
-- Matched to the platform's own ceiling rather than to a measurement, so a run
-- that is merely slow is not mislabelled as a failure: a Supabase Edge Function
-- request is cut off at ~150s, so a POST still outstanding at 150s means the
-- function is gone, and "timeout" is then the honest word for it. Today's run
-- needed ~7s, which is the margin we want -- 6.6s of work under a 5s deadline is
-- exactly how a working pipeline came to be recorded as a broken one.
--
-- Both triggers get the same value. `send-reminders` is the faster of the two
-- today (one row, one Resend call), but it has the same shape -- a loop over
-- candidates behind one HTTP request -- and giving the two schedules different
-- deadlines would mean a second rule to remember for no gain.
--
-- WHAT THIS STILL DOES NOT DO
--
-- It makes the evidence CORRECT, not LOUD. After this, a 403 is recorded as 403
-- and a 200 as 200 -- but `net._http_response` is still a table nothing reads,
-- and pg_net prunes it within hours. Noticing a failure without being asked is
-- separate work, deliberately not smuggled in here: it needs a staleness check
-- over `max(connection.last_synced_at)` and a channel to complain through, which
-- is a new Edge Function and a third cron entry, not a function body swap.

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
  -- Migration #9. A FLOOR, not a format assertion. The three-day outage v42
  -- records was a 4-character Vault value -- the literal placeholder `<⌘V>` from
  -- a paste that never happened -- and a 403 at the gate is invisible from here.
  -- 32 is "this is obviously not a secret", chosen low enough that a future
  -- rotation to a shorter secret is not broken by this line. It cannot catch a
  -- wrong-but-plausible value; that is what the read-back in the v42 entry is
  -- for. What it does buy: a mangled paste fails as a FAILED cron run on the
  -- first firing instead of syncing nothing for three days.
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
