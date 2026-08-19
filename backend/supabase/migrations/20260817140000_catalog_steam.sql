
insert into public.merchant_catalog (service_name, domain, category, subscription_only, patterns) values
  ('Steam', 'steampowered.com', 'Games', false, array['steam', 'valve', 'trueline valve'])
on conflict (service_name) do update
  set domain            = excluded.domain,
      category          = excluded.category,
      subscription_only = excluded.subscription_only,
      patterns          = excluded.patterns;
