-- Migration #18 — say out loud what `purchase_date` is for and what reads it
-- Source of truth: subscription-tracker-data-model.md (v67, 2026-08-18)
--
-- COMMENT ONLY. No table, column, constraint, index, policy, grant or row is
-- touched. `comment on column` is metadata; this migration cannot fail on
-- production data and cannot change behaviour.
--
-- WHY A MIGRATION FOR A COMMENT
--
-- The column has a writer and NO READER, which is the mirror of the `card_label`
-- situation v60 fixed (a reader with no writer, so every row carried null and a
-- subtitle rendered "Monthly · " around an absence). A column in that state is not
-- a bug, but it is a trap: the next person to find it will reasonably assume it is
-- populated, and on 327 of 334 production rows it is not.
--
-- The spec already records what the column is FOR. What was missing is what it is
-- doing TODAY, and the database is where someone reading `\d+ transaction` will
-- look first.
--
-- MEASURED, NOT ASSUMED (production, 2026-08-18, 334 transactions)
--
--   purchase_date populated ............ 7
--   installment rows ................... 7
--   populated AND installment .......... 7
--   populated but NOT installment ...... 0
--
-- An exact correlation: Pluggy sends `creditCardMetadata.purchaseDate` only for
-- parcelled purchases. The clearest row in the set is a Gol ticket, parcel 5/5:
-- `date = 2025-11-03` against `purchase_date = 2025-07-02` -- the instalment landed
-- four months after the purchase it belongs to. That gap is the column's entire
-- reason to exist, and it is also why `date` alone cannot group parcels.
--
-- WHAT READS IT TODAY: NOTHING
--
-- Written by `pluggy-sync` (`toSaoPauloDate(ccm.purchaseDate)`), read by no Edge
-- Function and no client code. Its designed purpose -- `(merchant, purchase_date)`
-- groups one purchase across its parcels, which Pluggy's own docs say Open Finance
-- gives no key for -- is unreachable while installments are excluded from detection
-- outright (candidate filter 3, v21). So the column is deliberately stored and
-- deliberately unused: sync stays faithful to the feed, and the day installments
-- become interpretable the grouping key is already there, populated, historical.
--
-- THE CALENDAR USES `date`, NOT THIS
--
-- Asked and answered on 2026-08-18: a charge lands on the calendar under
-- `transaction.date` -- Pluggy's purchase instant converted to a Sao Paulo calendar
-- date -- and forward-looking entries use `next_expected_date`, which is derived
-- from the last charge's `date` plus the interval. Neither reads `purchase_date`,
-- and neither reads Pluggy's `billForecastDate`: a subscription tracker wants the
-- day the money was committed, not the statement it will appear on. Billing-date
-- grouping would have collapsed the June and July renewals into two statement
-- months and R1 would never have measured a monthly cadence at all.

comment on column public.transaction.purchase_date is
  'Original purchase date, from Pluggy''s `creditCardMetadata.purchaseDate`, '
  'converted to a Sao Paulo calendar date. Preserved across every parcel while '
  '`date` shifts per instalment, so `(merchant_key, purchase_date)` groups one '
  'purchase -- the key Pluggy''s docs say Open Finance does not provide. '
  'POPULATED ONLY ON INSTALMENT ROWS: 7 of 334 production rows on 2026-08-18, '
  'correlating exactly with rows carrying installment_number/total_installments. '
  'Do not assume it is set. WRITTEN BY pluggy-sync, READ BY NOTHING as of v67 -- '
  'installments are excluded from detection (candidate filter 3), so the grouping '
  'it enables has no caller yet. Kept because sync stays faithful to the feed and '
  'the key must already be historical the day installments become interpretable. '
  'The calendar and every prediction use `date`, never this column, and never '
  'Pluggy''s billForecastDate.';
