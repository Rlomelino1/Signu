-- Migration #13 — Steam in the merchant catalog
-- Source of truth: subscription-tracker-data-model.md (v56, 2026-08-17)
--
-- ADDITIVE ONLY: one row of reference data. No table, column, constraint, index,
-- policy or grant is touched.
--
-- WHY THIS ROW EXISTS
--
-- The first real subscription this app ever detected renders with a monogram,
-- because the catalog seeded in Migration #8 has no Steam or Valve entry at all —
-- 61 rows, zero matches for steam, valve or trueline.
--
-- AND A NAME-ONLY ENTRY WOULD NOT HAVE FIXED IT
--
-- The descriptor on the statement is `TRUELINE VALVE CORPORATION`, Valve's
-- Brazilian billing entity. `MerchantCatalog.entry` matches by canonical name and
-- then by pattern containment, and 'steam' is not a substring of that descriptor.
-- So the patterns carry the work, which is exactly what the column was added for:
-- Disney's row already reads array['disney', 'disneyplus', 'disney plus'] for the
-- same reason.
--
-- 'trueline valve' is listed as well as 'valve'. Redundant today, since 'valve'
-- already matches, and kept because it is the descriptor actually observed: if a
-- future acquirer ships 'VALVE CORP' the broad pattern still catches it, and if
-- 'valve' ever has to be narrowed the observed string survives the change.
--
-- WHY subscription_only IS false, AGAINST MOST OF THE CATALOG
--
-- Netflix is true because every Netflix charge IS a subscription. Steam is mostly
-- one-off game purchases. `subscription_only` is R4's trigger — "a charge from this
-- merchant is always a subscription" — so marking Steam true would, once R4 is
-- wired, promote every game bought to a subscription. The R$34,33 monthly charge on
-- this account recurs because of what was bought, not because the merchant only
-- sells subscriptions, and the catalog must describe the merchant.
--
-- WHY steampowered.com AND NOT valvesoftware.com
--
-- Both resolve at logo.dev (verified: 200, image/png, 10,496 and 3,838 bytes), so
-- this is a choice about recognition rather than availability. The charge says
-- Valve and the product is Steam; the row is read in a list of the user's
-- subscriptions, where Steam's mark is the one they recognise.
--
-- `on conflict (service_name)` because the unique constraint is on that column and
-- a reset must converge rather than fail the second time.

insert into public.merchant_catalog (service_name, domain, category, subscription_only, patterns) values
  ('Steam', 'steampowered.com', 'Games', false, array['steam', 'valve', 'trueline valve'])
on conflict (service_name) do update
  set domain            = excluded.domain,
      category          = excluded.category,
      subscription_only = excluded.subscription_only,
      patterns          = excluded.patterns;
