begin;
create extension if not exists pgtap with schema extensions;
select plan(6);

insert into auth.users (id, email, raw_user_meta_data)
values ('11111111-1111-1111-1111-11111111ee01', 'sticky@example.test', '{}'::jsonb);

insert into public.connection (id, user_id, provider_connection_id, institution_id, institution_name, status)
values ('22222222-2222-2222-2222-22222222ee01', '11111111-1111-1111-1111-11111111ee01',
        'item-sticky', '200', 'MeuPluggy', 'active');

insert into public.bank_account (id, connection_id, provider_account_id, type, brand, last4, official_name, status)
values ('33333333-3333-3333-3333-33333333ee01', '22222222-2222-2222-2222-22222222ee01',
        'acct-sticky', 'credit_card', 'MASTERCARD', '2049', 'platinum', 'active');

insert into public.transaction
  (id, account_id, provider_tx_id, status, type, date, amount, currency, raw_description,
   provider_merchant_name, provider_merchant_cnpj)
values
  ('44444444-4444-4444-4444-44444444ee01', '33333333-3333-3333-3333-33333333ee01',
   'p-sticky-1', 'posted', 'DEBIT', '2026-07-19', 6.45, 'USD', 'Steam Purchase',
   'TRUELINE VALVE CORPORATION', '08057063000196');

update public.transaction
   set provider_merchant_name = null, provider_merchant_cnpj = null
 where id = '44444444-4444-4444-4444-44444444ee01';

select is(
  (select provider_merchant_cnpj from public.transaction
    where id = '44444444-4444-4444-4444-44444444ee01'),
  '08057063000196',
  'THE GUARD: a null from a degraded provider cannot erase a known CNPJ'
);

select is(
  (select provider_merchant_name from public.transaction
    where id = '44444444-4444-4444-4444-44444444ee01'),
  'TRUELINE VALVE CORPORATION',
  'nor a known merchant name'
);

update public.transaction
   set provider_merchant_name = 'VALVE CORPORATION', provider_merchant_cnpj = '08057063000197'
 where id = '44444444-4444-4444-4444-44444444ee01';

select is(
  (select provider_merchant_name from public.transaction
    where id = '44444444-4444-4444-4444-44444444ee01'),
  'VALVE CORPORATION',
  'a non-null rename is a correction, not a downgrade, and is honoured'
);

select is(
  (select provider_merchant_cnpj from public.transaction
    where id = '44444444-4444-4444-4444-44444444ee01'),
  '08057063000197',
  'same for the CNPJ'
);

insert into public.transaction
  (id, account_id, provider_tx_id, status, type, date, amount, currency, raw_description)
values
  ('44444444-4444-4444-4444-44444444ee02', '33333333-3333-3333-3333-33333333ee01',
   'p-sticky-2', 'posted', 'DEBIT', '2026-08-20', 34.32, 'BRL', 'Steamgames.Com');

update public.transaction
   set provider_merchant_name = 'TRUELINE VALVE CORPORATION', provider_merchant_cnpj = '08057063000196'
 where id = '44444444-4444-4444-4444-44444444ee02';

select is(
  (select provider_merchant_cnpj from public.transaction
    where id = '44444444-4444-4444-4444-44444444ee02'),
  '08057063000196',
  'null -> value is how the backfill repairs history, and it flows freely'
);

update public.transaction set status = 'pending'
 where id = '44444444-4444-4444-4444-44444444ee01';

select is(
  (select status from public.transaction
    where id = '44444444-4444-4444-4444-44444444ee01'),
  'pending',
  'the trigger narrows nothing else about an update'
);

select * from finish();
rollback;
