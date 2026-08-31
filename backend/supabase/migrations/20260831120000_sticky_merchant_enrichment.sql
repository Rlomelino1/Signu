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
