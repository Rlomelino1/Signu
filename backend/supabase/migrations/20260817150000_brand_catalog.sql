
alter table public.merchant_catalog rename to brand_catalog;

alter index  merchant_catalog_pkey             rename to brand_catalog_pkey;
alter index  merchant_catalog_patterns_idx     rename to brand_catalog_patterns_idx;
alter index  merchant_catalog_service_name_key rename to brand_catalog_brand_name_key;
alter policy "read the merchant catalog" on public.brand_catalog
  rename to "read the brand catalog";

alter table public.brand_catalog rename column service_name to brand_name;

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
