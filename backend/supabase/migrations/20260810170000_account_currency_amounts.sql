-- Migration #5 — account-currency amounts
-- Source of truth: subscription-tracker-data-model.md (v26, 2026-08-10)
--
-- ADDITIVE ONLY. Three nullable columns, no defaults, no constraint changes, no
-- RLS policy changes. Migration #1 is applied to the remote, so in-place
-- correction is closed (v17).
--
-- WHY
--
-- Pluggy sends TWO amounts for an international transaction and they are not
-- derivable from each other:
--
--     amount                    6.45   currencyCode = USD    (transaction currency)
--     amountInAccountCurrency  34.51                         (account currency)
--
-- The implied FX rate moves per transaction -- 34.51/6.45 = 5.349 on one row and
-- 34.33/6.45 = 5.323 on the next -- so neither number reconstructs the other.
-- They are two independent facts, and only `amount` was being stored.
--
-- Each one is load-bearing for a DIFFERENT rule, so dropping either breaks
-- something specific:
--
--   * `amount` is what R1 needs. It is the STABLE number -- 6.45 every month for
--     a USD-priced subscription. Keyed on the account-currency value instead, R1
--     would see 34.51 vs 34.33, call them different, and never anchor; the real
--     subscription would degrade to an R3 suggestion and never auto-track. This
--     is not hypothetical: it is how the one genuine subscription in this ledger
--     was found (v24).
--   * `amount_in_account_currency` is what TOTALS need. 57 of 258 rows are USD;
--     summing 6.45 USD with 39.90 BRL is meaningless, which is why the hero
--     totals could not render (v24 scope limit).
--
-- Storing both is also what the raw-chain doctrine already requires: "the raw
-- layer stays a literal record of the aggregator; no interpretation smuggled
-- into the evidence." Pluggy sends both fields, so dropping one is choosing
-- which number matters -- and that is interpretation.
--
-- THE INVARIANT, verified before writing this migration
--
-- `amountInAccountCurrency` is populated exactly when the transaction currency
-- differs from the account currency. Checked across all 258 real rows: 201
-- same-currency rows with it null, 57 foreign rows with it populated, ZERO
-- violations. Therefore:
--
--     coalesce(amount_in_account_currency, amount)  IS ALWAYS in the account currency
--
-- That is what makes totals a plain sum. Stated here so a future reader does not
-- have to rediscover why the coalesce is safe.
--
-- DELIBERATELY NOT ADDED
--
--   * fx_rate -- derivable as amount_in_account_currency / amount, and a derived
--     value in the raw chain is what the doctrine refuses.
--   * a third always-populated "resolved" amount on TRANSACTION -- same reason.
--     The coalesce is one function call and does not need a column that could
--     drift from its inputs.

alter table public.transaction
  -- Exactly as Pluggy sends it: null for a transaction already in the account's
  -- currency, where `amount` IS the account-currency figure.
  add column amount_in_account_currency numeric;

alter table public.charge
  -- CHARGE duplicates this for the same reason it duplicates date, amount and
  -- currency: it is deliberately self-describing so it survives transaction_id
  -- going NULL when a bank link is removed. A frozen charge with no
  -- account-currency figure could never be totalled, and the frozen region is
  -- permanent by design (v24).
  add column amount_in_account_currency numeric;

alter table public.bank_account
  -- Without this, `amount_in_account_currency` has no declared unit -- "account
  -- currency" would be an assumption rather than a stored fact. BANK_ACCOUNT had
  -- no currency column at all; Pluggy's account carries currencyCode (BRL on
  -- both of this item's accounts). Nullable rather than NOT NULL because
  -- Migration #1 is already applied and existing rows have no value to state.
  add column currency text
    check (currency is null or char_length(currency) = 3);


-- ---------------------------------------------------------------------------
-- apply_detection, redefined to write charge.amount_in_account_currency.
--
-- Migration #4 is ALREADY APPLIED to the remote, so it must not be edited in
-- place (v17: "in-place correction is safe only before first apply"). The
-- function is therefore restated here in full via `create or replace`. Migration
-- #5 is unapplied, so this belongs here rather than in a further migration --
-- adding the column and teaching the applier to write it is one change.
--
-- The ONLY difference from Migration #4 is the charge insert: one extra column,
-- copied through with no arithmetic. The applier stays a dumb applier.
-- ---------------------------------------------------------------------------

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
          run_id, transaction_id, date, amount, currency,
          amount_in_account_currency, card_label
        ) values (
          v_run_id,
          (v_charge ->> 'transaction_id')::uuid,
          (v_charge ->> 'date')::date,
          (v_charge ->> 'amount')::numeric,
          v_charge ->> 'currency',
          -- Copied through, never computed here: the applier stays dumb.
          nullif(v_charge ->> 'amount_in_account_currency', '')::numeric,
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
