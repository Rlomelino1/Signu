
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron;

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

select cron.schedule(
  'signu-daily-sync',
  '30 15 * * *',
  $$select public.trigger_pluggy_sync();$$
);
