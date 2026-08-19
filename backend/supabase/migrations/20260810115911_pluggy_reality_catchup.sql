
alter table public.transaction

  add column withdrawn_at             timestamptz,

  add column installment_number       integer,
  add column total_installments       integer,

  add column purchase_date            date,

  add column fee_type_additional_info text,

  add column provider_merchant_name   text,
  add column provider_merchant_cnpj   text;
