
begin;
create extension if not exists pgtap with schema extensions;
select plan(12);


select has_table('public', 'sync_dispatch', 'the dispatch ledger exists');

select is(
  (select relrowsecurity from pg_class
    where oid = 'public.sync_dispatch'::regclass),
  true,
  'row level security is on, as it is on every other table'
);

select is_empty(
  $$ select grantee, privilege_type from information_schema.role_table_grants
      where table_schema = 'public' and table_name = 'sync_dispatch'
        and grantee in ('anon', 'authenticated') $$,
  'no client role holds any privilege: this ledger is machine-only'
);

select lives_ok(
  $$ select public.assert_sync_dispatches_healthy() $$,
  'an empty ledger is quiet -- a database that has never dispatched is not broken'
);

insert into public.sync_dispatch (request_id, kind, dispatched_at, status_code, timed_out, checked_at)
values (1, 'pluggy_sync', now() - interval '2 hours', 200, false, now());

select lives_ok(
  $$ select public.assert_sync_dispatches_healthy() $$,
  'a successful newest dispatch is quiet'
);

insert into public.sync_dispatch (request_id, kind, dispatched_at, status_code, timed_out, checked_at)
values (2, 'pluggy_sync', now() - interval '1 hour', 403, false, now());

select throws_ok(
  $$ select public.assert_sync_dispatches_healthy() $$,
  'P0001',
  null,
  'a 403 on the newest dispatch raises, which is the whole point: pg_cron would '
  'otherwise record the run as a success'
);

insert into public.sync_dispatch (request_id, kind, dispatched_at, status_code, timed_out, checked_at)
values (3, 'pluggy_sync', now() - interval '10 minutes', 200, false, now());

select lives_ok(
  $$ select public.assert_sync_dispatches_healthy() $$,
  'it self-clears: a later success ends the noise with nothing to acknowledge'
);

delete from public.sync_dispatch;

insert into public.sync_dispatch (request_id, kind, dispatched_at)
values (4, 'send_reminders', now() - interval '5 minutes');

select lives_ok(
  $$ select public.assert_sync_dispatches_healthy() $$,
  'an unresolved dispatch is not yet a failure -- the response may still arrive'
);

select is(
  (select public.expire_stale_sync_dispatches()),
  0,
  'and it is not expired early either'
);

update public.sync_dispatch set dispatched_at = now() - interval '45 minutes'
 where request_id = 4;

select is(
  (select public.expire_stale_sync_dispatches()),
  1,
  'a dispatch nothing ever answered is resolved as failed, not left pending'
);

select throws_ok(
  $$ select public.assert_sync_dispatches_healthy() $$,
  'P0001',
  null,
  'and an unanswered call is loud, because silence is the failure being hunted'
);

delete from public.sync_dispatch;

insert into public.sync_dispatch (request_id, kind, dispatched_at, status_code, timed_out, checked_at)
values (5, 'pluggy_sync', now() - interval '30 hours', 200, false, now() - interval '30 hours');

select throws_ok(
  $$ select public.assert_sync_dispatches_healthy() $$,
  'P0001',
  null,
  'a schedule that stopped firing raises too: a call that never happened leaves '
  'no failing row, so the newest outcome cannot show it'
);


select * from finish();
rollback;
