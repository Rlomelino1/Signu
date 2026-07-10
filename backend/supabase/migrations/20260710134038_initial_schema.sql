-- ============================================================
-- Subscription Tracker — Migration #1: initial schema
-- Source of truth: subscription-tracker-data-model.md (v2, 2026-07-08)
--
-- Locked decisions implemented here:
--   * text + CHECK constraints (no enums)
--   * FK deletes: CASCADE everywhere except charge.transaction_id (SET NULL)
--   * RLS on all tables; join-based ownership; (select auth.uid()) idiom;
--     clients read-only on raw chain; column-scoped UPDATE grants on
--     user-owned columns; all other writes via service role only
--   * Indexes: FK support only, with transaction's widened to
--     (account_id, date) for the detection engine
--
-- OPERATIONAL RULE (deletion tier b, "delete history too"):
--   Deleting a connection cascades through the RAW chain only
--   (bank_account -> transaction). The interpreted chain hangs off
--   profiles, not connection. If the user chooses to delete subscription
--   history along with a bank link, the Edge Function must find and
--   delete the affected subscriptions BEFORE deleting the connection —
--   afterwards charge.transaction_id is already NULL and the linkage
--   between the chains is gone.
-- ============================================================


-- ------------------------------------------------------------
-- 1. PROFILES + signup trigger
-- ------------------------------------------------------------

create table public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  created_at   timestamptz not null default now()
);

-- Auto-create a profile the moment anyone signs up, regardless of provider.
-- security definer: runs as the function owner, so it works during signup
-- when no user session exists yet.
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
    coalesce(new.raw_user_meta_data ->> 'full_name', new.email)
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- ------------------------------------------------------------
-- 2. RAW CHAIN: connection -> bank_account -> transaction
-- ------------------------------------------------------------

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

  -- rejects duplicate registration of the same bank link
  -- (double-tap / retry / duplicate webhook)
  unique (user_id, provider_connection_id)
);

create table public.bank_account (
  id                  uuid primary key default gen_random_uuid(),
  connection_id       uuid not null references public.connection (id) on delete cascade,
  provider_account_id text not null,
  type                text not null check (type in ('credit_card', 'checking')),
  brand               text,          -- card network; null for non-cards
  last4               text,
  official_name       text,          -- sync-owned; sync may overwrite
  nickname            text,          -- user-owned; never touched by sync
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
                                               -- Pluggy's direction signal; detection
                                               -- keys direction off this, NEVER off sign
                                               -- (credit cards: positive = new charge)
  date                date not null,
  amount              numeric not null,        -- exactly as sent by bank; sign semantics
                                               -- vary by account type — see type column
  currency            text not null check (char_length(currency) = 3),
  raw_description     text not null,           -- immutable once posted (convention,
                                               -- enforced by sync pipeline)
  normalized_merchant text,                    -- derived; pipeline may rewrite anytime
  provider_category   text,                    -- aggregator's hint; sync-owned
  created_at          timestamptz not null default now(),  -- first import of this row

  -- idempotent sync
  unique (account_id, provider_tx_id)
);


-- ------------------------------------------------------------
-- 3. INTERPRETED CHAIN: subscription -> subscription_run -> charge
-- ------------------------------------------------------------

create table public.subscription (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references public.profiles (id) on delete cascade,
  service_name   text not null,
  nickname       text,                         -- user-owned
  merchant_key   text not null,                -- matching attribute; NON-unique
  dedupe_key     text not null,                -- identity; engine-assigned
  category       text,                         -- seeded by detection, user-editable
  logo_url       text,
  identification text not null default 'auto'
                 check (identification in ('auto', 'user_confirmed', 'user_renamed')),
  ignored        boolean not null default false,
  created_at     timestamptz not null default now(),  -- first detected = tracking since

  unique (user_id, dedupe_key)
);

create table public.subscription_run (
  id                 uuid primary key default gen_random_uuid(),
  subscription_id    uuid not null references public.subscription (id) on delete cascade,
  start_date         date not null,            -- corrected retroactively by R2 backfill
  end_date           date,                     -- null = active; paid-through semantics
  billing_interval   text not null
                     check (billing_interval in ('monthly', 'annual')),
  status             text not null
                     check (status in ('possible', 'active', 'overdue', 'ended')),
  next_expected_date date,                     -- engine cache; powers renewal alerts
  created_at         timestamptz not null default now()
);

create table public.charge (
  id             uuid primary key default gen_random_uuid(),
  run_id         uuid not null references public.subscription_run (id) on delete cascade,

  -- THE BRIDGE: the only place the two chains meet.
  -- SET NULL is what makes "delete bank link, preserve history" work:
  -- the charge survives, self-described by the duplicated columns below.
  transaction_id uuid references public.transaction (id) on delete set null,

  date           date not null,                -- duplicated on purpose
  amount         numeric not null,             -- duplicated on purpose
  currency       text not null check (char_length(currency) = 3),
  card_label     text,                         -- snapshot at billing time
  created_at     timestamptz not null default now(),

  -- no double-count: a transaction backs at most one charge
  -- (plain UNIQUE: Postgres allows unlimited NULLs)
  unique (transaction_id)
);


-- ------------------------------------------------------------
-- 4. ROW LEVEL SECURITY
--
-- Posture: RLS enabled everywhere. Clients (authenticated role) may
-- SELECT their own rows; UPDATE only user-owned columns (via column
-- grants below); never INSERT or DELETE. Sync pipeline and detection
-- engine use the service role, which bypasses RLS.
-- ------------------------------------------------------------

alter table public.profiles          enable row level security;
alter table public.connection        enable row level security;
alter table public.bank_account      enable row level security;
alter table public.transaction       enable row level security;
alter table public.subscription      enable row level security;
alter table public.subscription_run  enable row level security;
alter table public.charge            enable row level security;

-- ---- direct-ownership tables ----

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

-- ---- indirect tables: ownership via joins ----

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


-- ------------------------------------------------------------
-- 5. PRIVILEGES: make the RLS posture real
--
-- Supabase's default grants give anon/authenticated full table
-- privileges (RLS then filters rows). We tighten to: authenticated
-- gets SELECT everywhere + UPDATE on user-owned columns only;
-- anon gets nothing.
-- ------------------------------------------------------------

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

-- user-owned columns only ("sync-owned vs user-owned never overlap",
-- now enforced as a permission boundary, not a convention)
grant update (display_name)                on public.profiles     to authenticated;
grant update (nickname)                    on public.bank_account to authenticated;
grant update (nickname, category, ignored) on public.subscription to authenticated;


-- ------------------------------------------------------------
-- 6. INDEXES
--
-- Postgres does not auto-index FK columns. These support the cascades,
-- the RLS join policies, and ordinary chain-walking queries. The
-- transaction index is widened to (account_id, date): one index serves
-- both FK support and the detection engine's fundamental scan
-- ("posted outflows for this account, in date order").
-- Everything else (normalized_merchant, next_expected_date, partial
-- status indexes) is deliberately deferred until real query patterns exist.
-- ------------------------------------------------------------

create index bank_account_connection_id_idx on public.bank_account (connection_id);
create index transaction_account_id_date_idx on public.transaction (account_id, date);
create index subscription_run_subscription_id_idx on public.subscription_run (subscription_id);
create index charge_run_id_idx on public.charge (run_id);