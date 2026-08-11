-- Migration #7 — renewal reminders: the sent-marker column and the daily schedule
-- Source of truth: subscription-tracker-data-model.md (v28, 2026-08-11)
--
-- ADDITIVE ONLY. One nullable column, one function, one cron entry. No existing
-- column, constraint, index, policy or grant is altered.
--
-- WHY THE MARKER LIVES ON subscription_run, AND WHY IT IS A DATE
--
-- Reminder settings are per-subscription (`remind_before_days`, v5) but the date
-- being reminded about is `subscription_run.next_expected_date`, so the marker
-- belongs beside it. Verified by reading `apply_detection` rather than assuming:
-- its UPDATE names columns explicitly and matches a surviving run by
-- `stored_run_id`, so a column it never names cannot be clobbered; its DELETE
-- only removes runs the engine dropped, whose reminder state is moot.
--
-- A date, not a boolean and not a timestamp:
--   * a boolean would let last month's reminder silence this month's;
--   * a timestamp would need extra arithmetic to decide whether a renewal that
--     MOVED still counts as reminded.
-- Storing the `next_expected_date` that was reminded about gets both right for
-- free, and gets them right *because* detection rewrites `next_expected_date` on
-- every pass: a shifted renewal no longer matches the marker and re-arms itself.
--
-- GRANTS ARE DELIBERATELY UNTOUCHED
--
-- `grant select on public.subscription_run to authenticated` is table-level, so
-- the client can read this column with no new grant. The column-scoped UPDATE
-- grants do NOT include it and must not: this is engine-owned state, not a user
-- assertion, and the "sync-owned vs user-owned never overlap" boundary is a
-- permission boundary here rather than a convention.
--
-- ONE MANUAL STEP PER ENVIRONMENT, as with Migration #6. Until it is done the job
-- is scheduled and fails loudly when it fires, which is the intended failure mode:
--
--   select vault.create_secret('https://<ref>.supabase.co/functions/v1/send-reminders',
--                              'signu_reminders_url');
--
-- `signu_sync_secret` is reused rather than duplicated -- send-reminders checks
-- the same SYNC_SECRET the other two functions do, so a second secret would be a
-- second thing to rotate with no boundary gained.

alter table public.subscription_run
  add column if not exists last_reminded_for_date date;

comment on column public.subscription_run.last_reminded_for_date is
  'The next_expected_date a renewal reminder was last sent for. Null = never '
  'reminded. Engine-owned (service_role only); written after the mail provider '
  'accepts the send, never before -- a send recorded before it succeeded would '
  'skip the renewal entirely, while one recorded late at worst repeats.';

-- Callable by hand for testing:  select public.trigger_send_reminders();
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

revoke all on function public.trigger_send_reminders() from public;
revoke all on function public.trigger_send_reminders() from anon, authenticated;

-- 16:30 UTC, one hour after the sync at 15:30. Not chained off the sync the way
-- detection is: a reminder must go out even on a day the bank link is broken and
-- the sync fails, because `next_expected_date` is already stored and a renewal
-- does not stop coming because syncing stopped. One hour is margin for the
-- sync -> detection chain to finish, so reminders read fresh dates.
--
-- 13:30 in Sao Paulo, which is also a defensible hour to receive it.
--
-- Re-running is safe: pg_cron upserts on jobname, so `db reset` reproduces
-- exactly one entry rather than accumulating duplicates.
select cron.schedule(
  'signu-daily-reminders',
  '30 16 * * *',
  $$select public.trigger_send_reminders();$$
);
