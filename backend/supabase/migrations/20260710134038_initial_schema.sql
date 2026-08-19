


create table public.profiles (
  id                uuid primary key references auth.users (id) on delete cascade,
  display_name      text,

  reminder_channels text not null default 'email'
                    check (reminder_channels in ('push', 'email', 'both')),

  created_at        timestamptz not null default now()
);

create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data ->> 'full_name',
      new.raw_user_meta_data ->> 'name',
      new.email
    )
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();



create table public.connection (
  id                     uuid primary key default gen_random_uuid(),
  user_id                uuid not null references public.profiles (id) on delete cascade,
  provider_connection_id text not null,
  institution_id         text not null,
  institution_name       text not null,
  status                 text not null
                         check (status in ('active', 'needs_action', 'expired', 'disconnected')),
  consent_expires_at     date,
  last_synced_at         timestamptz,
  last_sync_error        text,
  created_at             timestamptz not null default now(),

  unique (user_id, provider_connection_id)
);

create table public.bank_account (
  id                  uuid primary key default gen_random_uuid(),
  connection_id       uuid not null references public.connection (id) on delete cascade,
  provider_account_id text not null,
  type                text not null check (type in ('credit_card', 'checking')),
  brand               text,
  last4               text,
  official_name       text,
  nickname            text,
  status              text not null
                      check (status in ('active', 'closed')),
  created_at          timestamptz not null default now(),

  unique (connection_id, provider_account_id)
);

create table public.transaction (
  id                  uuid primary key default gen_random_uuid(),
  account_id          uuid not null references public.bank_account (id) on delete cascade,
  provider_tx_id      text not null,
  status              text not null check (status in ('pending', 'posted')),
  type                text not null check (type in ('DEBIT', 'CREDIT')),
  date                date not null,
  amount              numeric not null,
  currency            text not null check (char_length(currency) = 3),
  raw_description     text not null,
  normalized_merchant text,
  provider_category   text,
  created_at          timestamptz not null default now(),

  unique (account_id, provider_tx_id)
);



create table public.subscription (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references public.profiles (id) on delete cascade,
  service_name   text not null,
  nickname       text,
  merchant_key   text not null,
  dedupe_key     text not null,
  category       text,


  remind_before_days integer,

  identification text not null default 'auto'
                 check (identification in ('auto', 'user_confirmed', 'user_renamed')),
  ignored        boolean not null default false,
  created_at     timestamptz not null default now(),

  unique (user_id, dedupe_key)
);

create table public.subscription_run (
  id                 uuid primary key default gen_random_uuid(),
  subscription_id    uuid not null references public.subscription (id) on delete cascade,
  start_date         date not null,
  end_date           date,
  billing_interval   text not null
                     check (billing_interval in ('monthly', 'annual')),
  status             text not null
                     check (status in ('possible', 'active', 'overdue',
                                       'ended', 'cancelled')),
  detected_by        text not null
                     check (detected_by in ('R1', 'R3', 'R4')),
  cancelled_date     date,
  next_expected_date date,
  created_at         timestamptz not null default now()
);

create table public.charge (
  id             uuid primary key default gen_random_uuid(),
  run_id         uuid not null references public.subscription_run (id) on delete cascade,

  transaction_id uuid references public.transaction (id) on delete set null,

  date           date not null,
  amount         numeric not null,
  currency       text not null check (char_length(currency) = 3),
  card_label     text,
  created_at     timestamptz not null default now(),

  unique (transaction_id)
);



alter table public.profiles          enable row level security;
alter table public.connection        enable row level security;
alter table public.bank_account      enable row level security;
alter table public.transaction       enable row level security;
alter table public.subscription      enable row level security;
alter table public.subscription_run  enable row level security;
alter table public.charge            enable row level security;


create policy "select own profile" on public.profiles
  for select using (id = (select auth.uid()));

create policy "update own profile" on public.profiles
  for update using (id = (select auth.uid()))
        with check (id = (select auth.uid()));

create policy "select own connections" on public.connection
  for select using (user_id = (select auth.uid()));

create policy "select own subscriptions" on public.subscription
  for select using (user_id = (select auth.uid()));

create policy "update own subscriptions" on public.subscription
  for update using (user_id = (select auth.uid()))
        with check (user_id = (select auth.uid()));


create policy "select own bank accounts" on public.bank_account
  for select using (
    exists (
      select 1 from public.connection c
      where c.id = bank_account.connection_id
        and c.user_id = (select auth.uid())
    )
  );

create policy "update own bank accounts" on public.bank_account
  for update using (
    exists (
      select 1 from public.connection c
      where c.id = bank_account.connection_id
        and c.user_id = (select auth.uid())
    )
  )
  with check (
    exists (
      select 1 from public.connection c
      where c.id = bank_account.connection_id
        and c.user_id = (select auth.uid())
    )
  );

create policy "select own transactions" on public.transaction
  for select using (
    exists (
      select 1
      from public.bank_account ba
      join public.connection c on c.id = ba.connection_id
      where ba.id = transaction.account_id
        and c.user_id = (select auth.uid())
    )
  );

create policy "select own runs" on public.subscription_run
  for select using (
    exists (
      select 1 from public.subscription s
      where s.id = subscription_run.subscription_id
        and s.user_id = (select auth.uid())
    )
  );

create policy "select own charges" on public.charge
  for select using (
    exists (
      select 1
      from public.subscription_run r
      join public.subscription s on s.id = r.subscription_id
      where r.id = charge.run_id
        and s.user_id = (select auth.uid())
    )
  );



revoke all on public.profiles,
              public.connection,
              public.bank_account,
              public.transaction,
              public.subscription,
              public.subscription_run,
              public.charge
  from anon, authenticated;

grant select on public.profiles,
                public.connection,
                public.bank_account,
                public.transaction,
                public.subscription,
                public.subscription_run,
                public.charge
  to authenticated;

grant update (display_name, reminder_channels)
  on public.profiles     to authenticated;
grant update (nickname)
  on public.bank_account to authenticated;
grant update (nickname, category, ignored, remind_before_days)
  on public.subscription to authenticated;



create index bank_account_connection_id_idx on public.bank_account (connection_id);
create index transaction_account_id_date_idx on public.transaction (account_id, date);
create index subscription_run_subscription_id_idx on public.subscription_run (subscription_id);
create index charge_run_id_idx on public.charge (run_id);