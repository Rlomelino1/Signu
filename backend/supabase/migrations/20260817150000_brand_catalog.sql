-- Migration #14 — merchant_catalog becomes brand_catalog, and learns what a row IS
-- Source of truth: subscription-tracker-data-model.md (v58, 2026-08-17)
--
-- ADDITIVE AND RENAMING. One table renamed with its index, policy and constraints;
-- one column renamed; one column added with a default that makes every existing row
-- correct; nine rows inserted. No row is deleted and no column dropped.
--
-- WHY RENAME AT ALL
--
-- The table is about to hold banks. 'merchant_catalog' stops being true the moment it
-- does: Nubank is not a merchant this user subscribes to, and `service_name` is not
-- what a bank's name is. A table whose name misdescribes half its rows is the kind of
-- thing that reads as fine for a year and then teaches someone the wrong model.
--
-- 'brand_catalog' is neutral about what the brand sells, which is exactly the job the
-- new `kind` column now does.
--
-- THE PREVIOUS MIGRATIONS ARE NOT EDITED
--
-- #8 creates `merchant_catalog` and #13 inserts into it. Both are applied, and v44's
-- lesson is that editing an applied migration leaves the repo and the database
-- disagreeing with nothing to report it. They keep the old name, this renames it, and
-- a from-scratch rebuild passes through both states in order.
--
-- THIS IS A HARD CUTOVER FOR CLIENTS
--
-- The table name IS the PostgREST endpoint, so `/rest/v1/merchant_catalog` stops
-- existing the moment this applies. The client change ships with it. A compatibility
-- view was considered and skipped deliberately: with one user it is ceremony, and a
-- permanent alias would leave two names for one table — the ambiguity this migration
-- exists to remove.
--
-- WHY `kind` RATHER THAN A SECOND TABLE
--
-- The alternative was `institution_catalog` alongside this one. Rejected because the
-- logo prefetch's privacy property depends on fetching EVERY domain in the catalog
-- (v38): two tables means two fetches that must both be complete, and a future change
-- that forgets one turns the request set into a description of the user. One table,
-- one fetch, one discriminator.
--
-- What the discriminator buys is the thing that made adding banks unsafe: `patterns`
-- are matched against transaction descriptors, and 'NU PAGAMENTOS' appears on
-- statements as the ACQUIRER. Without a kind, a Nubank-acquired charge could match the
-- bank row and wear the bank's logo — and once R4 reads `patterns`, worse. Scoping the
-- lookup by kind removes that by construction rather than by writing careful patterns.

alter table public.merchant_catalog rename to brand_catalog;

-- The index, policy and constraints keep their old names through a table rename, which
-- leaves 'merchant_catalog_%' identifiers on a table that no longer has that name.
-- Cosmetic, and worth doing while the reason is fresh.
alter index  merchant_catalog_pkey             rename to brand_catalog_pkey;
alter index  merchant_catalog_patterns_idx     rename to brand_catalog_patterns_idx;
alter index  merchant_catalog_service_name_key rename to brand_catalog_brand_name_key;
alter policy "read the merchant catalog" on public.brand_catalog
  rename to "read the brand catalog";

-- `service_name` is wrong for a bank for the same reason the table name was.
alter table public.brand_catalog rename column service_name to brand_name;

-- What a row IS. Defaulted to 'service' so every existing row is correct without an
-- update statement: all 62 are subscription services, which is what the table held.
alter table public.brand_catalog
  add column if not exists kind text not null default 'service'
    check (kind in ('service', 'institution'));

comment on column public.brand_catalog.kind is
  'What this brand is. ''service'' rows are matched against subscription descriptors; '
  '''institution'' rows against a connection''s derived bank label. The scoping is not '
  'cosmetic: patterns like ''nu pagamentos'' appear on statements as the ACQUIRER, so '
  'an unscoped lookup would give a Nubank-acquired subscription the bank''s logo.';

comment on table public.brand_catalog is
  'Shared reference data: a brand, how to recognise it in a descriptor, and where its '
  'logo lives. Formerly merchant_catalog (v58), renamed when it began holding '
  'financial institutions as well as subscription services.';

-- The institutions. Every domain below was verified against logo.dev before being
-- written here (200, image/png), because a row whose logo does not resolve is a row
-- that quietly does nothing.
--
-- `subscription_only` is false for all of them and the column is meaningless for an
-- institution: you do not subscribe to your bank. It is not nullable, so false is the
-- honest value rather than a claim.
--
-- Patterns are matched against the label the app DERIVES for a connection (v43), which
-- for this account is 'Nu Pagamentos S.A.' and 'C6 BANK' — the checking account's
-- official name, not the connector's. Hence 'nu pagamentos' rather than only 'nubank'.
insert into public.brand_catalog
  (brand_name, domain, category, subscription_only, patterns, kind) values
  ('Nubank',        'nubank.com.br',    'Bank', false, array['nubank', 'nu pagamentos', 'nu bank'],        'institution'),
  ('C6 Bank',       'c6bank.com.br',    'Bank', false, array['c6 bank', 'banco c6', 'c6 standard'],        'institution'),
  ('Itaú',          'itau.com.br',      'Bank', false, array['itau', 'itau unibanco', 'banco itau'],       'institution'),
  ('Bradesco',      'bradesco.com.br',  'Bank', false, array['bradesco', 'banco bradesco'],               'institution'),
  ('Banco do Brasil','bb.com.br',       'Bank', false, array['banco do brasil', 'bb.com.br'],             'institution'),
  ('Santander',     'santander.com.br', 'Bank', false, array['santander', 'banco santander'],             'institution'),
  ('Inter',         'inter.co',         'Bank', false, array['banco inter', 'inter s.a', 'intermedium'],   'institution'),
  ('PicPay',        'picpay.com',       'Bank', false, array['picpay'],                                    'institution'),
  ('Mercado Pago',  'mercadopago.com.br','Bank', false, array['mercado pago', 'mercadopago'],             'institution')
on conflict (brand_name) do update
  set domain            = excluded.domain,
      category          = excluded.category,
      subscription_only = excluded.subscription_only,
      patterns          = excluded.patterns,
      kind              = excluded.kind;
