-- Migration #16 — a storefront is not a subscription
-- Source of truth: subscription-tracker-data-model.md (v63, 2026-08-17)
--
-- DATA ONLY. No table, column, constraint, index, policy or grant is touched: three
-- `patterns` arrays narrowed, three rows added.
--
-- FOUND BY WIRING R4, WHICH IS THE POINT OF WIRING IT
--
-- `subscription_only` sat inert from v38 until v63 — nothing read it, so nothing
-- tested whether it was TRUE of the rows carrying it. Three were wrong, and the table
-- that holds them says why this matters, verbatim from Migration #8:
--
--   "Getting this wrong in the true direction manufactures suggestions out of one-off
--    spending."
--
-- | row                    | patterns                  | subscription_only |
-- |------------------------|---------------------------|-------------------|
-- | PlayStation Plus       | playstation, psn          | true              |
-- | Xbox Game Pass         | xbox, game pass           | true              |
-- | Nintendo Switch Online | nintendo                  | true              |
--
-- Every one of those patterns names a **storefront**. `PLAYSTATION NETWORK`, `XBOX`
-- and `NINTENDO` are what a one-off GAME purchase looks like on a statement, so R4
-- would have proposed a subscription for every game the user ever bought. This is the
-- identical reasoning Migration #13 recorded for Steam, which is correctly `false`:
-- "R4's trigger. True here would eventually promote every game bought."
--
-- THE FIX USES LONGEST-PATTERN-WINS RATHER THAN A NEW COLUMN
--
-- `subscription_only` is a property of a ROW, but the truth here is a property of a
-- PATTERN: `XBOX GAME PASS` is always a subscription, `XBOX` is not. The tempting fix
-- is a per-pattern flag — a schema change to encode what the existing matching rule
-- already expresses.
--
-- So each brand becomes TWO rows instead: a storefront carrying the broad patterns
-- (`subscription_only = false`) and the subscription carrying the specific ones
-- (`true`). The matcher takes the LONGEST matching pattern — a rule both sides already
-- implement (`BrandCatalog.entry`, `catalogEntryFor`) — so:
--
--   'PLAYSTATION PLUS RENEWAL'  -> 'playstation plus' (16) beats 'playstation' (11) -> subscription, R4 fires
--   'PLAYSTATION NETWORK'       -> 'playstation' only                               -> storefront,   R4 declines
--   'XBOX GAME PASS ULTIMATE'   -> 'game pass' (9) beats 'xbox' (4)                 -> subscription, R4 fires
--   'XBOX 4829112'              -> 'xbox' only                                      -> storefront,   R4 declines
--
-- LOGOS ARE UNAFFECTED, WHICH IS WHY THE BROAD PATTERNS SURVIVE
--
-- Deleting `psn` / `xbox` / `nintendo` outright would have been the smaller diff and
-- the wrong one: the client resolves logos through these same patterns, so a game
-- purchase would have lost its mark and fallen back to a monogram. The storefront rows
-- carry the same `domain`, so every charge that resolved to a logo before still does.
-- `allDomains` deduplicates, so the fetch set — and the privacy property that rests on
-- it being user-independent (v38) — is byte-identical.
--
-- Accepted cost, stated plainly: a PS Plus renewal that bills as the bare string
-- `PLAYSTATION NETWORK` gets no R4 fast path. It is genuinely indistinguishable from a
-- game purchase at that point, and R1 still catches it after the second charge. A
-- missed fast path costs two months; a false suggestion costs the user's trust in every
-- suggestion after it.

-- Narrowed to strings that only appear when the descriptor NAMES the subscription.
update public.brand_catalog
   set patterns = array['playstation plus', 'ps plus', 'psn plus']
 where brand_name = 'PlayStation Plus';

update public.brand_catalog
   set patterns = array['xbox game pass', 'game pass']
 where brand_name = 'Xbox Game Pass';

update public.brand_catalog
   set patterns = array['nintendo switch online', 'switch online']
 where brand_name = 'Nintendo Switch Online';

-- The storefronts. Same domain as their subscription sibling, so logo resolution is
-- unchanged; `subscription_only = false`, so R4 cannot fire on a game purchase.
-- `category` says Games rather than Gaming, matching Steam, which is the row these
-- three now behave like.
insert into public.brand_catalog (brand_name, domain, category, subscription_only, patterns, kind)
values
  ('PlayStation', 'playstation.com', 'Games', false, array['playstation', 'psn', 'sony playstation'], 'service'),
  ('Xbox',        'xbox.com',        'Games', false, array['xbox', 'microsoft xbox'],                 'service'),
  ('Nintendo',    'nintendo.com',    'Games', false, array['nintendo', 'nintendo eshop'],             'service');
