-- Migration #2 — Pluggy reality catch-up
-- Source of truth: subscription-tracker-data-model.md (v20, 2026-08-10)
--
-- ADDITIVE ONLY. Migration #1 is applied to the remote, so in-place correction
-- is closed (v17: "in-place correction is safe only before first apply").
--
-- Every column below is SYNC-OWNED. No RLS grant changes are needed: the
-- `authenticated` role holds column-scoped UPDATE on user-owned columns only,
-- and none of these are user-owned. Writers state every value explicitly —
-- no defaults, per the writer-states-everything doctrine.
--
-- Each column exists because live data proved it exists and proved it carries
-- signal. Fields Pluggy documents but this account's banks did not return
-- (totalAmount, payeeMCC, cardNumber, otherCreditsType) are deliberately
-- absent — see v20 for the reasoning and the watch list.

alter table public.transaction

  -- Pluggy deletes and recreates a transaction under a NEW id when its content
  -- changes enough to break Pluggy's identity hash, and also when a bank
  -- transiently stops returning a row for 1-3 days. Two causes, one code path.
  -- We never hard-delete: the row is evidence for a replayable interpreted
  -- chain, and the deletion is frequently temporary. Detection reads only
  -- `withdrawn_at is null`. charge.transaction_id keeps ON DELETE SET NULL for
  -- connection deletion, where it was designed to fire; it never fires here.
  add column withdrawn_at             timestamptz,

  -- Installment metadata. Load-bearing for R1: a Padrao-B bank posts a 12x
  -- purchase as one same-amount charge per month, which is exactly R1's
  -- trigger. Presence of either column DISQUALIFIES a row from R1.
  -- Verified populated on all 7 installment rows observed.
  add column installment_number       integer,
  add column total_installments       integer,

  -- The grouping key Pluggy's docs say Open Finance does not provide. `date`
  -- shifts to the bill-posting date for parcels 2..N while purchase_date is
  -- preserved across every parcel, so (merchant, purchase_date) groups one
  -- purchase exactly. date, not timestamptz, per date-granularity doctrine.
  add column purchase_date            date,

  -- IOF exclusion. `feeType` is 'OTHER' on 164/165 rows and carries no signal;
  -- the signal lives entirely in this field ('IOF_COMPRA_INTERNACIONAL' on 60
  -- of 165 card rows). Stored RAW, never as a derived is_fee boolean: the set
  -- of fee-indicating values will grow, and a stored boolean would freeze
  -- today's reading into the immutable raw chain and defeat replay.
  add column fee_type_additional_info text,

  -- Enriched merchant identity, populated on ~40% of card rows. Stored now
  -- because raw evidence not captured is evidence lost — Pluggy retains only
  -- 12 months, and detection cannot be replayed over data never written.
  -- Storing is NOT adopting: merchant_key derivation is unchanged by this
  -- migration and remains a separate, unlocked decision (v20).
  add column provider_merchant_name   text,
  add column provider_merchant_cnpj   text;

-- No new index. The existing (account_id, date) index still serves the
-- engine's fundamental scan, and per Migration #1 doctrine further indexes
-- wait until real query patterns exist. `withdrawn_at is null` will appear in
-- every detection query; revisit with a partial index only if measurement
-- shows it matters.