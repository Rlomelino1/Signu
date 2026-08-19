
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
