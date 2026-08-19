
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
           timeout_milliseconds := 150000
         )
    into v_id;

  return v_id;
end;
$$;

revoke all on function public.trigger_send_reminders() from public;
revoke all on function public.trigger_send_reminders() from anon, authenticated;
