
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
  select coalesce(array_agg((ch ->> 'transaction_id')::uuid), '{}'::uuid[])
    into v_wanted_tx
    from jsonb_array_elements(coalesce(p_desired -> 'subscriptions', '[]'::jsonb)) sub,
         jsonb_array_elements(coalesce(sub -> 'runs', '[]'::jsonb)) run,
         jsonb_array_elements(coalesce(run -> 'charges', '[]'::jsonb)) ch
   where (ch ->> 'transaction_id') is not null;

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
