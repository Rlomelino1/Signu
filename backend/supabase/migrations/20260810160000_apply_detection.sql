-- Migration #4 — apply_detection, the atomic applier
-- Source of truth: subscription-tracker-data-model.md (v24, 2026-08-10)
--
-- ADDITIVE ONLY. Adds one function. No table, column, constraint, index or RLS
-- policy is touched.
--
-- WHY A DATABASE FUNCTION AT ALL
--
-- The rules live in TypeScript for testability (v24), but PostgREST has no
-- transaction across calls. A recompute applied as a sequence of REST writes can
-- fail halfway and leave the interpreted chain in a state no rule produced --
-- exactly the failure that chaining sync into detection was meant to prevent.
-- So the whole desired state is handed over in one call and applied inside one
-- transaction.
--
-- This function is a DUMB APPLIER. No rules, no arithmetic, no interpretation:
-- every value it writes was computed by the pure core and is written verbatim.
-- Decisions that look like they belong here are deliberately upstream --
-- service_name freezing on `user_renamed`, assertion preservation, and which
-- runs may be deleted are all resolved in TypeScript, so this function never has
-- to ask "why". Rule logic in SQL is what the v24 shape refuses; a transactional
-- write boundary is not rule logic.
--
-- NOTE ON THE DRAFTED DISPOSITION: v24 was drafted as "migration disposition: no
-- action", reasoning that "the atomic applier is a function, not schema". A
-- function IS a schema object, and an unversioned database function is precisely
-- the drift v17 exists to prevent. Corrected to Migration #4.

create or replace function public.apply_detection(
  p_user_id uuid,
  p_desired jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_sub          jsonb;
  v_run          jsonb;
  v_charge       jsonb;
  v_sub_id       uuid;
  v_run_id       uuid;
  v_runs_kept    int := 0;
  v_runs_created int := 0;
  v_charges      int := 0;
  v_deleted      int := 0;
begin
  -- Runs the caller computed as no-longer-supported. The core has already
  -- excluded any run holding a frozen charge, so this is an unconditional
  -- delete; charges cascade.
  if p_desired ? 'delete_run_ids' then
    delete from public.subscription_run r
    using public.subscription s
    where r.subscription_id = s.id
      and s.user_id = p_user_id
      and r.id = any (
        select (jsonb_array_elements_text(p_desired -> 'delete_run_ids'))::uuid
      );
    v_deleted := coalesce((select count(*) from jsonb_array_elements_text(p_desired -> 'delete_run_ids')), 0);
  end if;

  for v_sub in select * from jsonb_array_elements(p_desired -> 'subscriptions')
  loop
    -- Only ever writes the three engine-owned columns. nickname, category,
    -- ignored, remind_before_days and identification are user assertions and are
    -- absent from this statement on purpose -- they cannot be clobbered by a
    -- column that is never named.
    insert into public.subscription (
      user_id, service_name, merchant_key, dedupe_key, identification, ignored
    ) values (
      p_user_id,
      v_sub ->> 'service_name',
      v_sub ->> 'merchant_key',
      v_sub ->> 'dedupe_key',
      'auto',
      false
    )
    on conflict (user_id, dedupe_key) do update
      set service_name = excluded.service_name,
          merchant_key = excluded.merchant_key
    returning id into v_sub_id;

    for v_run in select * from jsonb_array_elements(v_sub -> 'runs')
    loop
      if (v_run ->> 'stored_run_id') is not null then
        update public.subscription_run
           set subscription_id    = v_sub_id,
               start_date         = (v_run ->> 'start_date')::date,
               end_date           = nullif(v_run ->> 'end_date', '')::date,
               billing_interval   = v_run ->> 'billing_interval',
               status             = v_run ->> 'status',
               detected_by        = v_run ->> 'detected_by',
               cancelled_date     = nullif(v_run ->> 'cancelled_date', '')::date,
               next_expected_date = nullif(v_run ->> 'next_expected_date', '')::date
         where id = (v_run ->> 'stored_run_id')::uuid
        returning id into v_run_id;
        v_runs_kept := v_runs_kept + 1;
      end if;

      if v_run_id is null then
        insert into public.subscription_run (
          subscription_id, start_date, end_date, billing_interval,
          status, detected_by, cancelled_date, next_expected_date
        ) values (
          v_sub_id,
          (v_run ->> 'start_date')::date,
          nullif(v_run ->> 'end_date', '')::date,
          v_run ->> 'billing_interval',
          v_run ->> 'status',
          v_run ->> 'detected_by',
          nullif(v_run ->> 'cancelled_date', '')::date,
          nullif(v_run ->> 'next_expected_date', '')::date
        )
        returning id into v_run_id;
        v_runs_created := v_runs_created + 1;
      end if;

      -- THE FROZEN REGION. Only charges that still have raw backing are
      -- replaced. `transaction_id is not null` is the whole guard: a charge
      -- orphaned by the remove-bank-link flow is an immutable historical record
      -- and is never recomputed, never deleted, never re-parented (v24).
      delete from public.charge
       where run_id = v_run_id
         and transaction_id is not null;

      for v_charge in select * from jsonb_array_elements(v_run -> 'charges')
      loop
        insert into public.charge (
          run_id, transaction_id, date, amount, currency, card_label
        ) values (
          v_run_id,
          (v_charge ->> 'transaction_id')::uuid,
          (v_charge ->> 'date')::date,
          (v_charge ->> 'amount')::numeric,
          v_charge ->> 'currency',
          nullif(v_charge ->> 'card_label', '')
        );
        v_charges := v_charges + 1;
      end loop;

      v_run_id := null;
    end loop;
  end loop;

  return jsonb_build_object(
    'runs_kept', v_runs_kept,
    'runs_created', v_runs_created,
    'charges_written', v_charges,
    'runs_deleted', v_deleted
  );
end;
$$;

-- service_role only. The function is security definer so it can write the
-- interpreted chain in one transaction; nothing about it should be reachable
-- from a user session, which reads through RLS and writes nothing.
revoke all on function public.apply_detection(uuid, jsonb) from public;
revoke all on function public.apply_detection(uuid, jsonb) from anon, authenticated;
grant execute on function public.apply_detection(uuid, jsonb) to service_role;
