-- Merchant enrichment is preserve-once-known.
--
-- When the Pluggy trial lapsed (2026-08-25), transactions kept flowing but
-- arrived with merchant: null — and the daily full-window re-upsert overwrote
-- every stored provider_merchant_name / provider_merchant_cnpj with null.
-- merchant_key is derived from the CNPJ, so detection's groups shattered and
-- every run was deleted (2026-08-31 incident). This trigger closes the class:
-- a provider that STOPS knowing a merchant can no longer make us forget it.
-- A non-null correction (a rename, a fixed CNPJ) still lands; only a
-- non-null -> null downgrade is refused, column by column.

create or replace function public.keep_known_merchant_enrichment()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.provider_merchant_name := coalesce(new.provider_merchant_name, old.provider_merchant_name);
  new.provider_merchant_cnpj := coalesce(new.provider_merchant_cnpj, old.provider_merchant_cnpj);
  return new;
end;
$$;

drop trigger if exists keep_known_merchant_enrichment on public.transaction;
create trigger keep_known_merchant_enrichment
  before update on public.transaction
  for each row
  execute function public.keep_known_merchant_enrichment();
