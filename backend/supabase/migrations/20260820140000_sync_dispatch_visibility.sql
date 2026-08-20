create table if not exists public.sync_dispatch (
  request_id    bigint primary key,
  kind          text not null
                check (kind in ('pluggy_sync', 'send_reminders')),
  dispatched_at timestamptz not null default now(),
  status_code   int,
  timed_out     boolean,
  error         text,
  checked_at    timestamptz
);

comment on table public.sync_dispatch is
  'One row per scheduled HTTP call the database makes to a machine Edge Function, '
  'recorded so the call''s OUTCOME can be seen. pg_net is asynchronous: '
  'net.http_post returns a request id and the response lands later in '
  'net._http_response, so a trigger that discards the id throws the only evidence '
  'away. pg_cron then records the queueing, not the HTTP result, and a rejected '
  'call reads as a successful run. That is the v42 outage: a SYNC_SECRET that no '
  'longer matches the function''s copy returns 403 before any per-connection error '
  'path, so last_sync_error stays null, last_synced_at never advances, and every '
  'indicator looks healthy for days. This table holds request ids and status codes '
  'only -- no secret and no digest of one, because the check is made by observing '
  'the status the database already receives rather than by comparing copies.';

comment on column public.sync_dispatch.request_id is
  'The pg_net request id, which is also net._http_response.id. Primary key, so a '
  'dispatch cannot be recorded twice.';

comment on column public.sync_dispatch.timed_out is
  'True when pg_net reported a timeout, and also when no response was ever '
  'recorded. An unanswered call is treated as failed rather than assumed fine.';

comment on column public.sync_dispatch.checked_at is
  'Null until the outcome has been resolved. Only unresolved rows are examined, so '
  'the resolution pass is cheap and idempotent.';

create index if not exists sync_dispatch_kind_dispatched_idx
  on public.sync_dispatch (kind, dispatched_at desc);

create index if not exists sync_dispatch_unresolved_idx
  on public.sync_dispatch (dispatched_at)
  where checked_at is null;

alter table public.sync_dispatch enable row level security;

revoke all on table public.sync_dispatch from anon, authenticated;

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

  insert into public.sync_dispatch (request_id, kind)
  values (v_id, 'pluggy_sync')
  on conflict (request_id) do nothing;

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

  insert into public.sync_dispatch (request_id, kind)
  values (v_id, 'send_reminders')
  on conflict (request_id) do nothing;

  return v_id;
end;
$$;

revoke all on function public.trigger_send_reminders() from public;
revoke all on function public.trigger_send_reminders() from anon, authenticated;

create or replace function public.record_sync_dispatch_results()
returns integer
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_resolved integer;
begin
  with resolved as (
    update public.sync_dispatch d
       set status_code = r.status_code,
           timed_out   = coalesce(r.timed_out, false),
           error       = r.error_msg,
           checked_at  = now()
      from net._http_response r
     where r.id = d.request_id
       and d.checked_at is null
    returning 1
  )
  select count(*) into v_resolved from resolved;

  return v_resolved;
end;
$$;

comment on function public.record_sync_dispatch_results() is
  'Copies the outcome pg_net recorded into sync_dispatch. Separate from the '
  'assertion on purpose: an assertion that raises rolls back its own transaction, '
  'so recording and complaining must not share one, or the complaint would undo '
  'the record and repeat forever.';

create or replace function public.expire_stale_sync_dispatches()
returns integer
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_expired integer;
begin
  with expired as (
    update public.sync_dispatch
       set checked_at = now(),
           timed_out  = true,
           error      = 'no response was ever recorded for this request; pg_net '
                        'retention elapsed before the outcome was read, so the '
                        'call is treated as failed rather than assumed fine'
     where checked_at is null
       and dispatched_at < now() - interval '30 minutes'
    returning 1
  )
  select count(*) into v_expired from expired;

  return v_expired;
end;
$$;

create or replace function public.assert_sync_dispatches_healthy()
returns void
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_failed text;
  v_stale  text;
begin
  select string_agg(
           format('%s dispatched %s answered %s%s',
                  kind,
                  to_char(dispatched_at, 'YYYY-MM-DD HH24:MI'),
                  case when timed_out then 'nothing'
                       else coalesce(status_code::text, 'no status') end,
                  case when error is not null then ' (' || error || ')' else '' end),
           '; ' order by kind)
    into v_failed
    from (
      select distinct on (kind) kind, dispatched_at, status_code, timed_out, error
        from public.sync_dispatch
       where checked_at is not null
       order by kind, dispatched_at desc
    ) latest
   where timed_out
      or status_code is null
      or status_code < 200
      or status_code >= 300;

  if v_failed is not null then
    raise exception
      'a scheduled call to a machine function failed: %. A 403 means the '
      'x-sync-secret the database sent is not the SYNC_SECRET the function holds: '
      'the two copies have drifted, and every other indicator still reads healthy '
      'because the function rejects the request before any per-connection error '
      'path. That is the v42 outage, and it cost three days. Set both copies from '
      'one value in the same sitting; the next scheduled run clears this by '
      'itself.', v_failed;
  end if;

  select string_agg(format('%s last dispatched %s',
                           kind, to_char(last_dispatch, 'YYYY-MM-DD HH24:MI')),
                    '; ' order by kind)
    into v_stale
    from (
      select kind, max(dispatched_at) as last_dispatch
        from public.sync_dispatch
       group by kind
      having max(dispatched_at) < now() - interval '26 hours'
    ) stale;

  if v_stale is not null then
    raise exception
      'a daily schedule has stopped dispatching: %. The most recent call was over '
      '26 hours ago, so the schedule itself is not firing -- which the latest '
      'outcome cannot show, because a call that never happened leaves no failing '
      'row. Checked only for a kind that has dispatched before, so a database '
      'that has never run one stays quiet.', v_stale;
  end if;
end;
$$;

comment on function public.assert_sync_dispatches_healthy() is
  'Raises when the newest resolved dispatch for any kind failed, so a rejected '
  'call turns a scheduled run red instead of green. Judging only the NEWEST '
  'dispatch makes it self-clearing: once the secret is fixed, the next successful '
  'call ends the noise with no manual acknowledgement to forget.';

revoke all on function public.record_sync_dispatch_results() from public;
revoke all on function public.record_sync_dispatch_results() from anon, authenticated;
revoke all on function public.expire_stale_sync_dispatches() from public;
revoke all on function public.expire_stale_sync_dispatches() from anon, authenticated;
revoke all on function public.assert_sync_dispatches_healthy() from public;
revoke all on function public.assert_sync_dispatches_healthy() from anon, authenticated;

select cron.schedule(
  'signu-sync-dispatch-record',
  '*/10 * * * *',
  $$select public.record_sync_dispatch_results();$$
);

select cron.schedule(
  'signu-sync-dispatch-expire',
  '3-59/10 * * * *',
  $$select public.expire_stale_sync_dispatches();$$
);

select cron.schedule(
  'signu-sync-dispatch-assert',
  '6-59/10 * * * *',
  $$select public.assert_sync_dispatches_healthy();$$
);
