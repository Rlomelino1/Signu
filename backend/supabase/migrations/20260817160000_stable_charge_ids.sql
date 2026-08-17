-- Migration #15 — a charge is the same row tomorrow
-- Source of truth: subscription-tracker-data-model.md (v61, 2026-08-17)
--
-- ADDITIVE: one `create or replace function`. No table, column, constraint, index,
-- policy or grant is touched, and the applier's contract — same arguments, same
-- return shape plus one key — is unchanged.
--
-- WHAT WAS WRONG, AND IT WAS NOT PERFORMANCE
--
-- The charge block deleted every charge of a run and re-inserted it, so **every
-- charge got a new id on every sync**. The write cost is negligible and always will be
-- (thirty subscriptions over ten years is ~3,600 rows a day), so this is not an
-- optimisation. It is that nothing can ever REFERENCE a charge: not a user note, not a
-- receipt, not "hide this one", not an export with stable ids. The calendar already
-- keys its entries by charge id (v46) and so churns daily for no reason, and an id you
-- saw yesterday does not exist today, which makes debugging harder than it needs to be.
--
-- The pgTAP suite added alongside this migration demonstrated it rather than arguing
-- it: zero of two ids survived an identical second pass.
--
-- AND IT FOUND A REAL BUG NOBODY WAS LOOKING FOR
--
-- Delete-then-insert could abort an entire detection pass with
-- `23505 duplicate key value violates unique constraint "charge_transaction_id_key"`.
-- When detection moves a transaction from one run to another — a run split, a
-- correction — and the RECEIVING run happens to be processed first, its insert lands
-- while the losing run still holds that charge, and `unique (transaction_id)` rejects
-- it. Nothing was pruned yet, because the losing run's delete had not run. The whole
-- `apply_detection` call rolls back, so a user in that state gets no sync at all until
-- the payload order happens to change: order-dependent, silent, and invisible in code
-- review. The old applier failed this test file's re-parent case exactly that way.
-- Upserting cannot hit it, because a moved charge is an UPDATE of the row that already
-- holds that transaction, whichever run is processed first.
--
-- HOW IT CONVERGES NOW
--
-- `charge` already carries `unique (transaction_id)` (Migration #1), so a charge has a
-- natural key and the applier can upsert on it instead of replacing rows. `run_id` is
-- in the update list, which is what lets a re-parented transaction MOVE rather than be
-- deleted and recreated.
--
-- The pure-core doctrine is untouched: detection still computes desired state, the
-- applier still makes stored state match it, and "re-runs repair" still holds.
--
-- THE PRUNE IS SCOPED PER RUN ON PURPOSE — THIS IS THE LOAD-BEARING PART
--
-- The obvious prune is global: delete any charge of this user whose transaction is not
-- in the desired set. That is wrong in a way worth spelling out, because the old code
-- was accidentally safe against it. If `detect` ever returns an empty payload — a
-- transient failure to read transactions, a bug, a user whose rows have not loaded —
-- a global prune deletes the user's entire charge history. The old per-run delete could
-- not do that: no runs in the payload meant no deletions.
--
-- So the prune stays scoped to runs the payload actually mentions, and the "still
-- wanted" test uses the union of desired transaction ids across the WHOLE payload
-- rather than just that run's. Per-run scope keeps the failure mode safe; the global
-- set makes the result independent of the order runs appear in, so a transaction moving
-- between two runs keeps its id whichever run is processed first.
--
-- THE FROZEN REGION IS UNCHANGED (v24)
--
-- `transaction_id is not null` still guards every write and the prune. An orphaned
-- charge is an immutable historical record: never recomputed, never deleted, never
-- re-parented. Postgres allows many nulls under a unique constraint, so orphans cannot
-- collide with the upsert either.
--
-- `charges_written` NOW MEANS WHAT IT SAYS
--
-- The no-op guard on the update means an unchanged charge is not rewritten at all, so
-- the counter only counts rows actually inserted or updated. A steady-state run reports
-- **zero**, which is a signal worth having: it says the pass agreed with what was
-- already stored. `charges_pruned` is added for the same reason.

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
  v_pruned       int := 0;
  v_deleted      int := 0;
  v_wanted_tx    uuid[];
  v_pruned_now   int;
begin
  -- Every transaction the payload wants a charge for, anywhere. Collected once,
  -- before any write, so the prune below cannot depend on iteration order.
  select coalesce(array_agg((ch ->> 'transaction_id')::uuid), '{}'::uuid[])
    into v_wanted_tx
    from jsonb_array_elements(coalesce(p_desired -> 'subscriptions', '[]'::jsonb)) sub,
         jsonb_array_elements(coalesce(sub -> 'runs', '[]'::jsonb)) run,
         jsonb_array_elements(coalesce(run -> 'charges', '[]'::jsonb)) ch
   where (ch ->> 'transaction_id') is not null;

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

      -- Upsert on the natural key, so a charge is the SAME ROW across passes and a
      -- re-parented transaction moves instead of being recreated (v61).
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
        )
        on conflict (transaction_id) do update
          set run_id                     = excluded.run_id,
              date                       = excluded.date,
              amount                     = excluded.amount,
              currency                   = excluded.currency,
              amount_in_account_currency = excluded.amount_in_account_currency,
              card_label                 = excluded.card_label
          -- No-op writes are skipped, so a steady-state pass touches nothing and
          -- leaves no dead tuples. EVERY value column is listed: one omitted here
          -- would be a column that silently never updates, which is the failure this
          -- codebase keeps paying for.
          where (
            public.charge.run_id,
            public.charge.date,
            public.charge.amount,
            public.charge.currency,
            public.charge.amount_in_account_currency,
            public.charge.card_label
          ) is distinct from (
            excluded.run_id,
            excluded.date,
            excluded.amount,
            excluded.currency,
            excluded.amount_in_account_currency,
            excluded.card_label
          );
        if found then v_charges := v_charges + 1; end if;
      end loop;

      -- Charges of THIS run that the payload no longer wants anywhere. Scoped to the
      -- run (so an empty payload cannot wipe a history) and tested against the whole
      -- payload's wanted set (so a re-parent is a move, not a delete). Orphans are
      -- excluded by `transaction_id is not null` — v24's frozen region.
      delete from public.charge
       where run_id = v_run_id
         and transaction_id is not null
         and not (transaction_id = any (v_wanted_tx));
      get diagnostics v_pruned_now = row_count;
      v_pruned := v_pruned + v_pruned_now;

      v_run_id := null;
    end loop;
  end loop;

  return jsonb_build_object(
    'runs_kept', v_runs_kept,
    'runs_created', v_runs_created,
    'charges_written', v_charges,
    'charges_pruned', v_pruned,
    'runs_deleted', v_deleted
  );
end;
$$;
