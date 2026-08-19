
alter table public.subscription_run
  add column if not exists last_reminded_for_date date;

comment on column public.subscription_run.last_reminded_for_date is
  'The next_expected_date a renewal reminder was last sent for. Null = never '
  'reminded. Engine-owned (service_role only); written after the mail provider '
  'accepts the send, never before -- a send recorded before it succeeded would '
  'skip the renewal entirely, while one recorded late at worst repeats.';

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

select cron.schedule(
  'signu-daily-reminders',
  '30 16 * * *',
  $$select public.trigger_send_reminders();$$
);
