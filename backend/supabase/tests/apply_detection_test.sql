-- pgTAP: `apply_detection`, the app's most consequential SQL — and until now the
-- least tested. CI's `Schema applies` proves migrations APPLY; nothing asserted what
-- this function DOES.
--
-- v24's frozen-charge rule and v26's dual amounts both live in here, and both were
-- verified by reading. These tests exist so the next change to this function is not
-- also verified by reading.
--
-- Everything runs inside one transaction and rolls back, so the local database is
-- unchanged and the tests can be run repeatedly.

begin;
create extension if not exists pgtap with schema extensions;
select plan(22);

-- ----------------------------------------------------------------- fixtures

-- A user. `profiles` appears by trigger (Migration #1), which is itself worth
-- exercising: an applier test that hand-inserted the profile would not notice the
-- trigger breaking.
insert into auth.users (id, email, raw_user_meta_data)
values ('11111111-1111-1111-1111-111111111111', 'applier@example.test', '{}'::jsonb);

select isnt_empty(
  $$ select 1 from public.profiles where id = '11111111-1111-1111-1111-111111111111' $$,
  'the signup trigger created the profile the applier will write against'
);

insert into public.connection (id, user_id, provider_connection_id, institution_id, institution_name, status)
values ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111',
        'item-applier', '200', 'MeuPluggy', 'active');

insert into public.bank_account (id, connection_id, provider_account_id, type, brand, last4, official_name, status)
values ('33333333-3333-3333-3333-333333333333', '22222222-2222-2222-2222-222222222222',
        'acct-applier', 'credit_card', 'MASTERCARD', '2049', 'platinum', 'active');

insert into public.transaction (id, account_id, provider_tx_id, status, type, date, amount, currency, raw_description)
values
  ('44444444-4444-4444-4444-444444444401', '33333333-3333-3333-3333-333333333333', 'p-1', 'posted', 'DEBIT', '2026-01-10', 39.90, 'BRL', 'ACME STREAMING'),
  ('44444444-4444-4444-4444-444444444402', '33333333-3333-3333-3333-333333333333', 'p-2', 'posted', 'DEBIT', '2026-02-10', 39.90, 'BRL', 'ACME STREAMING'),
  ('44444444-4444-4444-4444-444444444403', '33333333-3333-3333-3333-333333333333', 'p-3', 'posted', 'DEBIT', '2026-03-10', 39.90, 'BRL', 'ACME STREAMING');

-- The desired state the engine would produce for the first two charges.
create temporary table payload (body jsonb);
insert into payload values ($json${
  "subscriptions": [{
    "dedupe_key": "acme:1",
    "merchant_key": "acme",
    "service_name": "ACME STREAMING",
    "runs": [{
      "stored_run_id": null,
      "start_date": "2026-01-10",
      "end_date": null,
      "billing_interval": "monthly",
      "status": "active",
      "detected_by": "R1",
      "cancelled_date": null,
      "next_expected_date": "2026-04-10",
      "charges": [
        {"transaction_id": "44444444-4444-4444-4444-444444444401", "date": "2026-01-10", "amount": 39.90, "currency": "BRL", "amount_in_account_currency": null, "card_label": "Master 2049"},
        {"transaction_id": "44444444-4444-4444-4444-444444444402", "date": "2026-02-10", "amount": 39.90, "currency": "BRL", "amount_in_account_currency": null, "card_label": "Master 2049"}
      ]
    }]
  }]
}$json$::jsonb);

-- --------------------------------------------------------------- convergence

select lives_ok(
  $$ select public.apply_detection('11111111-1111-1111-1111-111111111111', (select body from payload)) $$,
  'a first pass applies without error'
);

select is(
  (select count(*)::int from public.charge), 2,
  'both desired charges were written'
);

select is(
  (select card_label from public.charge where transaction_id = '44444444-4444-4444-4444-444444444401'),
  'Master 2049',
  'card_label is stored, not dropped — the column the engine only started writing in v60'
);

select is(
  (select count(*)::int from public.subscription where user_id = '11111111-1111-1111-1111-111111111111'), 1,
  'one subscription'
);

-- ------------------------------------------------------ ids across two passes

create temporary table before_ids as
  select transaction_id, id from public.charge where transaction_id is not null;

-- The run now exists, so a second pass names it, exactly as the engine would.
create temporary table payload2 (body jsonb);
insert into payload2
select jsonb_set(
         body,
         '{subscriptions,0,runs,0,stored_run_id}',
         to_jsonb((select id::text from public.subscription_run limit 1))
       )
from payload;

select lives_ok(
  $$ select public.apply_detection('11111111-1111-1111-1111-111111111111', (select body from payload2)) $$,
  'a second, identical pass applies without error'
);

select is(
  (select count(*)::int from public.charge), 2,
  'an identical pass does not duplicate charges'
);

-- THE POINT OF THIS FILE. Under delete-then-insert every charge gets a new id on
-- every sync, so nothing can ever reference a charge: not a user note, not a
-- receipt, not a stable export. The calendar already keys its entries by charge id
-- (v46) and so churns daily for no reason.
select is(
  (select count(*)::int
     from public.charge c
     join before_ids b on b.transaction_id = c.transaction_id
    where c.id = b.id),
  2,
  'charge ids SURVIVE a re-run — a charge is the same row, not a new one each day'
);

-- ------------------------------------------------------------ the frozen region

-- v24: a charge orphaned by the remove-bank-link flow is an immutable historical
-- record. It has no transaction, so no pass may recompute, delete or re-parent it.
insert into public.charge (run_id, transaction_id, date, amount, currency, card_label)
select id, null, '2025-12-10', 29.90, 'BRL', 'Visa 4821' from public.subscription_run limit 1;

select lives_ok(
  $$ select public.apply_detection('11111111-1111-1111-1111-111111111111', (select body from payload2)) $$,
  'a pass runs with an orphaned charge present'
);

select is(
  (select count(*)::int from public.charge where transaction_id is null), 1,
  'the orphaned charge survives — never recomputed, never deleted (v24)'
);

select is(
  (select amount from public.charge where transaction_id is null), 29.90,
  'and its values are untouched'
);

-- -------------------------------------------------------------------- pruning

-- Detection drops the February charge (a correction, or the transaction vanished
-- upstream). The stored state must follow.
create temporary table payload3 (body jsonb);
insert into payload3
select jsonb_set(body, '{subscriptions,0,runs,0,charges}',
                 (body #> '{subscriptions,0,runs,0,charges}') - 1)
from payload2;

select lives_ok(
  $$ select public.apply_detection('11111111-1111-1111-1111-111111111111', (select body from payload3)) $$,
  'a pass with one fewer charge applies'
);

select is(
  (select count(*)::int from public.charge where transaction_id = '44444444-4444-4444-4444-444444444402'), 0,
  'a charge the engine no longer wants is pruned'
);


select is(
  (select count(*)::int from public.charge where transaction_id = '44444444-4444-4444-4444-444444444401'), 1,
  'and the one it still wants is left alone'
);

-- ------------------------------------------------------- a steady pass is silent

-- `charges_written` counts rows actually inserted or updated, so an agreeing pass
-- reports zero. This is the observable form of "no dead tuples": if the no-op guard
-- ever stops matching a column, this number stops being zero.
select is(
  (select public.apply_detection('11111111-1111-1111-1111-111111111111',
                                 (select body from payload3)) ->> 'charges_written'),
  '0',
  'a pass that agrees with stored state writes NOTHING'
);

select is(
  (select public.apply_detection('11111111-1111-1111-1111-111111111111',
                                 (select body from payload3)) ->> 'charges_pruned'),
  '0',
  'and prunes nothing'
);

-- --------------------------------------------------------------- a re-parent moves

-- A charge's run can change: detection decides the January charge belongs to a new
-- run rather than the stored one. The charge is the same event, so it must MOVE.
--
-- The two runs are deliberately ordered NEW-FIRST, which is the order that breaks a
-- prune scoped to each run's own charge list: the old run would look at a charge that
-- is no longer its own and delete the row the new run had just claimed. The prune
-- tests against the whole payload's wanted set for exactly this reason.
create temporary table before_reparent as
  select id from public.charge where transaction_id = '44444444-4444-4444-4444-444444444401';

create temporary table payload4 (body jsonb);
insert into payload4
select jsonb_build_object(
  'subscriptions', jsonb_build_array(jsonb_build_object(
    'dedupe_key', 'acme:1',
    'merchant_key', 'acme',
    'service_name', 'ACME STREAMING',
    'runs', jsonb_build_array(
      -- the NEW run, claiming the charge
      jsonb_build_object(
        'stored_run_id', null,
        'start_date', '2026-01-10', 'end_date', null,
        'billing_interval', 'monthly', 'status', 'active', 'detected_by', 'R3',
        'cancelled_date', null, 'next_expected_date', '2026-04-10',
        'charges', body #> '{subscriptions,0,runs,0,charges}'
      ),
      -- the STORED run, now empty
      jsonb_build_object(
        'stored_run_id', body #>> '{subscriptions,0,runs,0,stored_run_id}',
        'start_date', '2026-01-10', 'end_date', null,
        'billing_interval', 'monthly', 'status', 'active', 'detected_by', 'R1',
        'cancelled_date', null, 'next_expected_date', '2026-04-10',
        'charges', '[]'::jsonb
      )
    )
  ))
)
from payload3;

select lives_ok(
  $$ select public.apply_detection('11111111-1111-1111-1111-111111111111', (select body from payload4)) $$,
  'a pass that re-parents a charge applies'
);

select is(
  (select count(*)::int from public.charge where transaction_id = '44444444-4444-4444-4444-444444444401'), 1,
  'the re-parented charge still exists exactly once — not deleted by the old run'
);

select is(
  (select count(*)::int
     from public.charge c, before_reparent b
    where c.transaction_id = '44444444-4444-4444-4444-444444444401' and c.id = b.id),
  1,
  'and it kept its id: a charge that changes run is a MOVE, not a new row'
);

select isnt(
  (select run_id from public.charge where transaction_id = '44444444-4444-4444-4444-444444444401'),
  (select (body #>> '{subscriptions,0,runs,1,stored_run_id}')::uuid from payload4),
  'while its run_id did change to the new run'
);

-- ------------------------------------------------------------- the fail-safe

-- THE reason the prune is scoped to runs the payload mentions. If `detect` ever
-- returns nothing — a transient read failure, a bug, rows that had not loaded — an
-- unscoped prune would delete the user's whole charge history on one bad pass. The
-- old delete-then-insert could not do that, and neither may this.
create temporary table charges_before_empty as select id from public.charge;

select lives_ok(
  $$ select public.apply_detection('11111111-1111-1111-1111-111111111111', '{"subscriptions": []}'::jsonb) $$,
  'an empty payload applies without error'
);

select is(
  (select count(*)::int from public.charge),
  (select count(*)::int from charges_before_empty),
  'an EMPTY payload deletes nothing — a failed detection cannot erase history'
);

select * from finish();
rollback;
