
import { cardLabel } from './accounts.ts'
import { moneyKey, sameMoney } from './money.ts'
import { addInterval, circularDomDistance, daysBetween, type Interval } from './dates.ts'


export interface TxRow {
  id: string
  provider_tx_id: string
  account_id: string
  status: string
  type: string
  date: string
  amount: number | string
  currency: string
  amount_in_account_currency: number | string | null
  raw_description: string
  normalized_merchant: string | null
  withdrawn_at: string | null
  installment_number: number | null
  total_installments: number | null
  fee_type_additional_info: string | null
  provider_merchant_name: string | null
  provider_merchant_cnpj: string | null
}

export interface StoredCharge {
  id: string
  run_id: string
  transaction_id: string | null
  date: string
  amount: number | string
  currency: string
  amount_in_account_currency: number | string | null
  card_label: string | null
}

export interface StoredRun {
  id: string
  subscription_id: string
  start_date: string
  end_date: string | null
  billing_interval: Interval
  status: string
  detected_by: string
  cancelled_date: string | null
  next_expected_date: string | null
}

export interface StoredSubscription {
  id: string
  dedupe_key: string
  merchant_key: string
  service_name: string
  identification: string
  ignored: boolean
}

export interface AccountRow {
  id: string
  brand: string | null
  last4: string | null
}

export interface CatalogRow {
  brand_name: string
  patterns: string[] | null
  subscription_only: boolean
  kind: string
}

export interface EngineInput {
  today: string
  rows: TxRow[]
  subscriptions: StoredSubscription[]
  runs: StoredRun[]
  charges: StoredCharge[]
  accounts?: AccountRow[]
  catalog?: CatalogRow[]
}


export interface DesiredCharge {
  transaction_id: string
  date: string
  amount: number
  currency: string
  amount_in_account_currency: number | null
  card_label: string | null
}

export interface DesiredRun {
  stored_run_id: string | null
  start_date: string
  end_date: string | null
  billing_interval: Interval
  status: string
  detected_by: string
  cancelled_date: string | null
  next_expected_date: string | null
  charges: DesiredCharge[]
}

export interface DesiredSubscription {
  stored_id: string | null
  dedupe_key: string
  merchant_key: string
  service_name: string
  runs: DesiredRun[]
}

export interface DesiredState {
  subscriptions: DesiredSubscription[]
  delete_run_ids: string[]
  diagnostics: Record<string, number>
}


const NOT_A_FEE = new Set(['', 'NA', 'N/A'])

export function isFee(r: TxRow): boolean {
  const v = r.fee_type_additional_info
  if (v === null || v === undefined) return false
  return !NOT_A_FEE.has(v.trim().toUpperCase())
}

const PARCEL_IN_DESCRIPTOR = /(^|[^0-9])\d{1,2}\s*\/\s*\d{1,2}([^0-9]|$)/

export function isInstallment(r: TxRow): boolean {
  if (r.installment_number !== null || r.total_installments !== null) return true
  return PARCEL_IN_DESCRIPTOR.test(r.raw_description)
}

export function isInternalTransfer(r: TxRow, allRows: TxRow[]): boolean {
  if (r.type !== 'DEBIT') return false
  return allRows.some(
    (c) =>
      c.type === 'CREDIT' &&
      c.account_id !== r.account_id &&
      sameMoney(c, r) &&
      Math.abs(daysBetween(c.date, r.date)) <= 3,
  )
}

export function filterCandidates(rows: TxRow[]): {
  candidates: TxRow[]
  diagnostics: Record<string, number>
} {
  const d: Record<string, number> = {
    input: rows.length,
    excluded_withdrawn: 0,
    excluded_credit: 0,
    excluded_fee: 0,
    excluded_installment: 0,
    excluded_internal_transfer: 0,
  }
  const candidates: TxRow[] = []
  for (const r of rows) {
    if (r.withdrawn_at !== null) { d.excluded_withdrawn++; continue }
    if (r.type === 'CREDIT') { d.excluded_credit++; continue }
    if (isFee(r)) { d.excluded_fee++; continue }
    if (isInstallment(r)) { d.excluded_installment++; continue }
    if (isInternalTransfer(r, rows)) { d.excluded_internal_transfer++; continue }
    candidates.push(r)
  }
  d.candidates = candidates.length
  return { candidates, diagnostics: d }
}


const AGGREGATOR_NAME_PATTERNS = [/PAYPAL/]

export function isAggregator(r: TxRow): boolean {
  const name = (r.provider_merchant_name ?? '').toUpperCase()
  return AGGREGATOR_NAME_PATTERNS.some((p) => p.test(name))
}

export function merchantKey(r: TxRow): string {
  const descriptor = (r.normalized_merchant ?? r.raw_description)
    .replace(/\s+/g, ' ')
    .trim()
    .toUpperCase()
  const cnpj = r.provider_merchant_cnpj
  if (cnpj) {
    return isAggregator(r) ? `${cnpj}:${descriptor}` : cnpj
  }
  return descriptor
}

// ------------------------------------------------------------------- ordering
//
// TOTAL order. Date alone is not total — Pluggy's within-day `order` field is
// not stored — and an unstable sort makes anchor selection nondeterministic.

export function compareRows(a: TxRow, b: TxRow): number {
  if (a.date !== b.date) return a.date < b.date ? -1 : 1
  return a.provider_tx_id < b.provider_tx_id ? -1 : a.provider_tx_id > b.provider_tx_id ? 1 : 0
}

// ----------------------------------------------------------------------- rules

// Anchor band: doctrine's "monthly = 28-33d, +/-3d window".
const MONTHLY_MIN = 25
const MONTHLY_MAX = 36
const MATCH_WINDOW = 3
const OVERDUE_GRACE = 10
const R3_MIN_CHARGES = 3
const R3_ALIGNED_FRACTION = 0.8

interface ProtoRun {
  charges: TxRow[]
  detected_by: 'R1' | 'R3' | 'R4'
  interval: Interval
}

/** R1 — anchor. Two charges, same merchant and SAME amount, one cadence apart.
 *  Continuation is amount-flexible so a price rise never splits a run. */
function anchorR1(group: TxRow[]): ProtoRun[] {
  const runs: ProtoRun[] = []
  const claimed = new Set<string>()

  for (let i = 0; i < group.length; i++) {
    if (claimed.has(group[i].id)) continue
    for (let j = i + 1; j < group.length; j++) {
      if (claimed.has(group[j].id)) continue
      const gap = daysBetween(group[i].date, group[j].date)
      if (gap > MONTHLY_MAX) break
      if (gap < MONTHLY_MIN) continue
      // Same money, not same number: one merchant bills in two currencies
      // in real data, so an amount-only test anchors a phantom run (v25).
      if (!sameMoney(group[i], group[j])) continue

      const run: ProtoRun = { charges: [group[i], group[j]], detected_by: 'R1', interval: 'monthly' }
      claimed.add(group[i].id)
      claimed.add(group[j].id)

      // Extend, amount-flexible, around each successive expected date.
      for (;;) {
        const last = run.charges[run.charges.length - 1]
        const expected = addInterval(last.date, run.interval)
        const next = group.find(
          (c) =>
            !claimed.has(c.id) &&
            c.date > last.date &&
            Math.abs(daysBetween(expected, c.date)) <= MATCH_WINDOW,
        )
        if (!next) break
        run.charges.push(next)
        claimed.add(next.id)
      }
      runs.push(run)
      break
    }
  }
  return runs
}

/** R3 — cadence beats amount. 3+ date-aligned charges with varying amounts.
 *  Alignment is >=80% within +/-3 days of the CIRCULAR median day-of-month; the
 *  loose reading fires on 26 Steam purchases spread over 16 days (v21). */
function suggestR3(group: TxRow[]): ProtoRun | null {
  if (group.length < R3_MIN_CHARGES) return null
  // Keyed on currency+cents so a cross-currency pair counts as two values
  // rather than collapsing into one (v25).
  const amounts = new Set(group.map((c) => moneyKey(c)))
  if (amounts.size < 2) return null

  const doms = group.map((c) => Number(c.date.slice(8, 10))).sort((a, b) => a - b)
  const median = doms[Math.floor(doms.length / 2)]
  const aligned = doms.filter((d) => circularDomDistance(d, median) <= MATCH_WINDOW).length
  if (aligned / doms.length < R3_ALIGNED_FRACTION) return null

  return { charges: [...group], detected_by: 'R3', interval: 'monthly' }
}

// ------------------------------------------------------------------------- R4
//
// The catalog fast path, contract-only since the engine was written (v11) and
// unwired through v62 because MERCHANT_CATALOG did not exist, then because nothing
// taught the engine to read it. Both blockers are gone.
//
// R4 exists for the case R1 and R3 structurally cannot reach: a subscription with
// ONE charge so far. R1 needs two charges a cadence apart; R3 needs three. A user
// who subscribes to Netflix today waits two months to see it — unless something
// already knows that a charge from Netflix is never a one-off. That knowledge is
// `brand_catalog.subscription_only`, and it is a claim about the MERCHANT.

/** Case- and accent-insensitive, trimmed. Mirrors `BrandCatalog.normalise` in the
 *  client (`BrandCatalog.swift`), which folds case and diacritics and trims —
 *  nothing more. Note its doc comment claims punctuation-insensitivity it does not
 *  implement; this matches the CODE, because two implementations that disagree are
 *  worse than one that is less clever than its comment. */
export function normaliseBrand(text: string): string {
  // \u0300-\u036f is the combining-marks block: NFD splits 'ã' into 'a' + a
  // combining tilde, and this drops the tilde. Written as escapes on purpose --
  // literal combining characters in a source file are invisible and unreviewable.
  return text.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().trim()
}

/** Name first, patterns second, longest pattern wins — `BrandCatalog.entry`'s rule,
 *  reimplemented because Swift and TypeScript cannot share it.
 *
 *  `kind` is scoped to 'service' by every caller here and that is load-bearing, not
 *  tidiness: 'NU PAGAMENTOS' appears on Brazilian statements as the ACQUIRER, so an
 *  unscoped lookup would match the Nubank institution row for a subscription merely
 *  billed through Nubank. Institutions are seeded `subscription_only = false`, so
 *  today that is belt and braces — but a single future edit to that column would
 *  otherwise turn every Nubank-acquired charge into a suggested subscription. */
export function catalogEntryFor(
  name: string | null,
  catalog: CatalogRow[],
  kind = 'service',
): CatalogRow | null {
  const needle = normaliseBrand(name ?? '')
  if (!needle) return null
  const rows = catalog.filter((c) => c.kind === kind)

  const exact = rows.find((c) => normaliseBrand(c.brand_name) === needle)
  if (exact) return exact

  // Longest pattern first, so 'amazon prime' beats 'amazon' when both are present.
  // Without the ordering the answer depends on row order, which is a database
  // detail rather than a rule.
  let best: CatalogRow | null = null
  let bestLength = 0
  for (const row of rows) {
    for (const raw of row.patterns ?? []) {
      const pattern = normaliseBrand(raw)
      if (!pattern || !needle.includes(pattern)) continue
      if (pattern.length > bestLength) {
        best = row
        bestLength = pattern.length
      }
    }
  }
  return best
}

/** R4 — catalog fast path. One charge from a known subscription-only merchant is a
 *  'possible' run immediately. Suggest-only: `applyAssertions` forces the status, so
 *  nothing here can auto-activate a subscription.
 *
 *  THE INTERVAL IS PROVISIONAL AND THAT IS THE WHOLE DESIGN (spec, locked
 *  2026-07-15). A single charge cannot measure cadence, so the engine writes
 *  'monthly' to keep the column NOT NULL and `next_expected_date` renderable, and the
 *  confirm flow asks the user monthly-or-annual and overwrites it. R3 confirmations
 *  never ask, because three date-aligned charges already MEASURED the cadence.
 *
 *  Recognition is attempted against the merchant name first, then the normalized
 *  descriptor, then the raw one — most trustworthy to least, since `patterns` exists
 *  precisely to catch descriptors like 'trueline valve'. The FIRST string that
 *  resolves to any entry decides, and if that entry is not subscription-only the rule
 *  declines. It deliberately does NOT keep trying further strings hoping for a yes:
 *  the strongest available signal has already said this merchant's charges are not
 *  always subscriptions, and "ask every name until one agrees" is a false-positive
 *  generator. */
function suggestR4(
  group: TxRow[],
  catalog: CatalogRow[],
  today: string,
  confirmedR4Exists: boolean,
): ProtoRun | null {
  if (!group.length || !catalog.length) return null
  const first = group[0]

  let entry: CatalogRow | null = null
  for (const needle of [first.provider_merchant_name, first.normalized_merchant, first.raw_description]) {
    entry = catalogEntryFor(needle, catalog)
    if (entry) break
  }
  if (!entry || !entry.subscription_only) return null

  // Every charge in the group, not just the first. Usually there IS only one -- that
  // is the case R4 exists for -- but when R1 and R3 have both declined a handful of
  // charges from a merchant whose every charge is a subscription, they belong to one
  // suggestion rather than being dropped on the floor. "Generous to extend."
  const proto: ProtoRun = { charges: [...group], detected_by: 'R4', interval: 'monthly' }

  // FRESHNESS, AND IT GATES CREATION ONLY (v64).
  //
  // R4's first firing in production proposed a subscription whose single charge was
  // FIVE MONTHS old: the derived lifecycle had already ended it, so the run carried an
  // `end_date`, no `next_expected_date`, and an invitation to track something that was
  // over. With a year of replayed history, every long-dead single charge from a catalog
  // merchant becomes a standing suggestion, and a `possible` run is re-derived forever
  // -- it never ages out on its own.
  //
  // `confirmedR4Exists` is why this is not simply "refuse ended runs". A CONFIRMED R4
  // run that never receives a second charge must die THROUGH the lifecycle -- active,
  // overdue, ended -- which the spec requires explicitly and a test pins. Declining to
  // regenerate it would delete the run instead of ending it, and with it the user's
  // confirmation. So: an assertion is always continued; a suggestion nobody has acted
  // on is only ever CREATED while it could still be alive.
  //
  // A stale `possible` run left over from before this rule is not regenerated, so it
  // leaves through `delete_run_ids` on the next pass. Suggestions clean themselves up;
  // assertions never do.
  if (!confirmedR4Exists && lifecycle(proto, today).status === 'ended') return null

  return proto
}

/** R2 — backfill. On a confirmed run, claim an unclaimed same-merchant charge
 *  about one interval before the start, ANY amount, and correct start_date.
 *
 *  Not an event. Under recompute this is re-derived every run: confirmation
 *  state is preserved, so the precondition holds and the backfill re-applies,
 *  reproducing the same start_date. Nothing remembers that R2 fired (v24). */
function backfillR2(run: ProtoRun, group: TxRow[], claimed: Set<string>): void {
  const first = run.charges[0]
  const expected = addInterval(first.date, run.interval, -1)
  const prior = group
    .filter(
      (c) =>
        !claimed.has(c.id) &&
        c.date < first.date &&
        Math.abs(daysBetween(expected, c.date)) <= MATCH_WINDOW,
    )
    .sort(compareRows)
    .pop()
  if (prior) {
    run.charges.unshift(prior)
    claimed.add(prior.id)
  }
}

// ------------------------------------------------------------------------- R5
//
// A cancelled run holds AT MOST ONE charge dated after its `cancelled_date`.
// Claiming that charge extends paid-through by one interval; a SECOND matching
// charge un-claims it, and the post-cancellation charges anchor a new run through
// standard R1 -- a resubscription, not a resurrection.
//
// This is the only place a charge ever moves between runs, and it is the reason
// `matchRuns` resolves identity by descending overlap: the cancelled run overlaps
// itself on many charges while the new run overlaps it on one, so the cancelled run
// keeps its id and the resubscription is correctly new.
//
// The cap is measured from `cancelled_date`, which is an assertion, and never from
// the run's last claimed charge -- that version ratchets forward one charge per
// sync, which is the unlimited-swallowing bug wearing a limit. Every part of this is
// a derivation from (raw, assertions, today), so incremental sync and full replay
// converge on identical state.

/** The live transaction ids a stored run holds. Frozen charges are excluded for the
 *  same reason `matchRuns` excludes them: no raw backing, no identity evidence. */
function claimedIds(runId: string, storedCharges: StoredCharge[]): Set<string> {
  const out = new Set<string>()
  for (const c of storedCharges) {
    if (c.run_id === runId && c.transaction_id !== null) out.add(c.transaction_id)
  }
  return out
}

/** R5 — trailing charge on cancelled runs. Applied to `protos` in place; returns
 *  what fired, because a rule that silently never fires reads as a rule that works
 *  and this project has now paid for that lesson three times. */
function trailingR5(
  protos: ProtoRun[],
  claimed: Set<string>,
  cancelledRuns: StoredRun[],
  storedCharges: StoredCharge[],
): { trailing: number; unclaimed: number } {
  let trailing = 0
  let unclaimed = 0

  for (const run of cancelledRuns) {
    const cancelledDate = run.cancelled_date
    if (!cancelledDate) continue
    const ids = claimedIds(run.id, storedCharges)
    if (ids.size === 0) continue

    // Which proto IS this cancelled run, by the same greedy-overlap rule `matchRuns`
    // applies later. Resolved here rather than reusing that pass because the split
    // has to happen before identity is assigned: matching first would hand the
    // over-extended proto the cancelled run's id and there would be nothing left to
    // split off.
    let host: ProtoRun | undefined
    let bestOverlap = 0
    for (const p of protos) {
      const overlap = p.charges.reduce((n, c) => n + (ids.has(c.id) ? 1 : 0), 0)
      if (overlap > bestOverlap) {
        host = p
        bestOverlap = overlap
      }
    }
    if (!host) continue

    const after = host.charges.filter((c) => c.date > cancelledDate)
    if (after.length === 0) continue

    const keep = host.charges.filter((c) => c.date <= cancelledDate)
    // Nothing survives the cancellation date, so the pre-cancellation charges were
    // withdrawn out from under the run. Truncating would leave a proto with no
    // charges at all; leave this one to the normal delete-and-rederive path.
    if (keep.length === 0) continue

    if (after.length === 1) {
      trailing++
      continue
    }

    // A resubscription exists only if the post-cancellation charges anchor on their
    // own, through the same R1 as any other run. When they cannot -- a price change
    // between them means no same-amount pair -- the cap decides instead: the run
    // keeps its one trailing charge and the rest go back to being unclaimed charges.
    // Better one truthful trailing charge than a resubscription the evidence does not
    // support. "Strict to create."
    const fresh = anchorR1(after)
    if (fresh.length === 0) {
      host.charges = [...keep, after[0]]
      for (const c of after.slice(1)) claimed.delete(c.id)
      trailing++
      continue
    }

    host.charges = keep
    const anchored = new Set(fresh.flatMap((f) => f.charges.map((c) => c.id)))
    for (const c of after) if (!anchored.has(c.id)) claimed.delete(c.id)
    protos.push(...fresh)
    unclaimed++
  }

  return { trailing, unclaimed }
}

// ------------------------------------------------------------------- lifecycle

function lifecycle(
  run: ProtoRun,
  today: string,
): { status: string; end_date: string | null; next_expected_date: string | null } {
  const last = run.charges[run.charges.length - 1]
  const expected = addInterval(last.date, run.interval)
  const overdueSince = addDaysSafe(expected, MATCH_WINDOW)

  if (daysBetween(today, expected) >= -MATCH_WINDOW) {
    return { status: 'active', end_date: null, next_expected_date: expected }
  }
  if (daysBetween(overdueSince, today) <= OVERDUE_GRACE) {
    return { status: 'overdue', end_date: null, next_expected_date: expected }
  }
  // end_date is paid-through: last charge + one interval, not the last charge.
  return { status: 'ended', end_date: expected, next_expected_date: null }
}

function addDaysSafe(d: string, n: number): string {
  const [y, m, day] = d.split('-').map(Number)
  return new Date(Date.UTC(y, m - 1, day + n)).toISOString().slice(0, 10)
}

// --------------------------------------------------------------- run identity
//
// A stored run and a desired run are the same run when they share at least one
// claimed transaction, matched GREEDILY BY DESCENDING OVERLAP. No stored anchor
// column: a frozen derived pointer is what this project keeps refusing.
//
// R5 un-claiming is the case that needs the ordering. The trailing charge moves
// to a new run, so the new run overlaps the cancelled run on exactly one charge
// while the cancelled run overlaps itself on many. Highest overlap wins, so the
// cancelled run keeps its identity and the new run is correctly new.

export function matchRuns(
  desired: { charges: TxRow[] }[],
  stored: StoredRun[],
  storedCharges: StoredCharge[],
): Map<number, string> {
  const byRun = new Map<string, Set<string>>()
  for (const c of storedCharges) {
    if (c.transaction_id === null) continue // frozen: not identity evidence
    if (!byRun.has(c.run_id)) byRun.set(c.run_id, new Set())
    byRun.get(c.run_id)!.add(c.transaction_id)
  }

  const pairs: { di: number; runId: string; overlap: number }[] = []
  desired.forEach((d, di) => {
    const ids = new Set(d.charges.map((c) => c.id))
    for (const s of stored) {
      const stored_ids = byRun.get(s.id)
      if (!stored_ids) continue
      let overlap = 0
      for (const id of ids) if (stored_ids.has(id)) overlap++
      if (overlap > 0) pairs.push({ di, runId: s.id, overlap })
    }
  })

  // Descending overlap, then stable by (desired index, run id) so equal overlaps
  // resolve identically on every run.
  pairs.sort((a, b) =>
    b.overlap - a.overlap || a.di - b.di || (a.runId < b.runId ? -1 : 1)
  )

  const out = new Map<number, string>()
  const usedRuns = new Set<string>()
  for (const p of pairs) {
    if (out.has(p.di) || usedRuns.has(p.runId)) continue
    out.set(p.di, p.runId)
    usedRuns.add(p.runId)
  }
  return out
}

// ------------------------------------------------------------------- assertions

/** Which stored values survive a recompute. `detected_by` alone distinguishes a
 *  derived status from an asserted one, so no extra column is needed (v24). */
function applyAssertions(
  desired: DesiredRun,
  stored: StoredRun | undefined,
): DesiredRun {
  if (stored) {
    // A cancellation is a user assertion, preserved regardless of detected_by.
    // next_expected_date stays null so a cancelled run never appears in "Coming
    // up" and can never trip overdue.
    if (stored.status === 'cancelled') {
      // Paid-through is DERIVED, not frozen: R5's trailing charge extends it by an
      // interval and un-claiming has to restore it. Both are `last claimed charge +
      const last = desired.charges[desired.charges.length - 1]
      return {
        ...desired,
        status: 'cancelled',
        cancelled_date: stored.cancelled_date,
        end_date: last ? addInterval(last.date, desired.billing_interval) : stored.end_date,
        next_expected_date: null,
        detected_by: stored.detected_by,
      }
    }

    const confirmedSuggestion =
      (stored.detected_by === 'R3' || stored.detected_by === 'R4') &&
      stored.status !== 'possible'

    if (confirmedSuggestion) {
      return {
        ...desired,
        detected_by: stored.detected_by,
        billing_interval:
          stored.detected_by === 'R4' ? stored.billing_interval : desired.billing_interval,
      }
    }
  }

  if (desired.detected_by === 'R3' || desired.detected_by === 'R4') {
    return { ...desired, status: 'possible' }
  }
  return desired
}


function dedupeKeys(merchant: string, runs: ProtoRun[]): string[] {
  const order = runs
    .map((r, i) => ({ i, first: r.charges[0] }))
    .sort((a, b) => compareRows(a.first, b.first))
  const keys = new Array<string>(runs.length)
  order.forEach((o, ordinal) => {
    keys[o.i] = ordinal === 0 ? merchant : `${merchant}:${ordinal + 1}`
  })
  return keys
}

// ----------------------------------------------------------------------- engine

export function detect(input: EngineInput): DesiredState {
  const { candidates, diagnostics } = filterCandidates(input.rows)

  // Account id -> 'Master 2049', for the charge snapshot (v60). Built once: a charge
  // is labelled by the account its transaction sits on, and `TxRow` already carries
  // `account_id`, so nothing new has to be threaded through the pass itself.
  const labels = new Map<string, string>()
  for (const a of input.accounts ?? []) {
    const label = cardLabel(a.brand, a.last4)
    if (label) labels.set(a.id, label)
  }
  const labelFor = (accountId: string): string | null => labels.get(accountId) ?? null

  const groups = new Map<string, TxRow[]>()
  for (const r of candidates) {
    const k = merchantKey(r)
    if (!groups.has(k)) groups.set(k, [])
    groups.get(k)!.push(r)
  }

  const storedByMerchant = new Map<string, StoredSubscription[]>()
  for (const s of input.subscriptions) {
    if (!storedByMerchant.has(s.merchant_key)) storedByMerchant.set(s.merchant_key, [])
    storedByMerchant.get(s.merchant_key)!.push(s)
  }
  const runsBySub = new Map<string, StoredRun[]>()
  for (const r of input.runs) {
    if (!runsBySub.has(r.subscription_id)) runsBySub.set(r.subscription_id, [])
    runsBySub.get(r.subscription_id)!.push(r)
  }
  const storedRunById = new Map(input.runs.map((r) => [r.id, r]))

  const subscriptions: DesiredSubscription[] = []
  const keptRunIds = new Set<string>()
  let r1Runs = 0
  let r3Runs = 0
  let r4Runs = 0
  let r5Trailing = 0
  let r5Unclaimed = 0

  // Deterministic group order, so output ordering is stable run to run.
  for (const merchant of [...groups.keys()].sort()) {
    const group = groups.get(merchant)!.slice().sort(compareRows)

    // Resolved before the rules, not after: R4 needs to know whether an assertion
    // already exists for this merchant (see `suggestR4`).
    const storedSubs = storedByMerchant.get(merchant) ?? []
    const candidateStoredRuns = storedSubs.flatMap((s) => runsBySub.get(s.id) ?? [])
    const confirmedR4Exists = candidateStoredRuns.some(
      (r) => r.detected_by === 'R4' && r.status !== 'possible',
    )

    const claimed = new Set<string>()
    const protos = anchorR1(group)
    protos.forEach((p) => p.charges.forEach((c) => claimed.add(c.id)))
    protos.forEach((p) => backfillR2(p, group, claimed))

    // R5 last of the auto rules, over finished protos: continuation built them blind
    // to cancellation, and this is where a cancelled run gives back what it should
    // never have swallowed. Cannot run before R1 -- there is no run to cap yet -- and
    // must run before the R3/R4 gates, which only fire when nothing was detected.
    const r5 = trailingR5(
      protos,
      claimed,
      candidateStoredRuns.filter((r) => r.status === 'cancelled'),
      input.charges,
    )
    r5Trailing += r5.trailing
    r5Unclaimed += r5.unclaimed

    if (protos.length === 0) {
      const leftover = group.filter((c) => !claimed.has(c.id))
      const s = suggestR3(leftover)
      if (s) protos.push(s)
    }
    // R4 last, and only when nothing else claimed anything for this merchant. The
    // ordering is the rule's precedence: a measured cadence always beats a catalog
    // assumption, so R4 never competes with R1 or R3 -- it fills the gap where
    // neither CAN fire. Deliberately scoped to "no runs at all for this merchant"
    // rather than "unclaimed charges remain": a stray charge alongside a real run is
    // R1 continuation's business, and a second 'possible' run for a merchant the user
    // already tracks is noise. "Strict to create."
    if (protos.length === 0) {
      const s = suggestR4(group, input.catalog ?? [], input.today, confirmedR4Exists)
      if (s) protos.push(s)
    }
    if (protos.length === 0) continue

    r1Runs += protos.filter((p) => p.detected_by === 'R1').length
    r3Runs += protos.filter((p) => p.detected_by === 'R3').length
    r4Runs += protos.filter((p) => p.detected_by === 'R4').length

    const keys = dedupeKeys(merchant, protos)
    const matches = matchRuns(protos, candidateStoredRuns, input.charges)

    protos.forEach((proto, idx) => {
      const storedRunId = matches.get(idx) ?? null
      const stored = storedRunId ? storedRunById.get(storedRunId) : undefined
      if (storedRunId) keptRunIds.add(storedRunId)

      const life = lifecycle(proto, input.today)
      let run: DesiredRun = {
        stored_run_id: storedRunId,
        start_date: proto.charges[0].date,
        end_date: life.end_date,
        billing_interval: proto.interval,
        status: life.status,
        detected_by: proto.detected_by,
        cancelled_date: null,
        next_expected_date: life.next_expected_date,
        charges: proto.charges.map((c) => ({
          transaction_id: c.id,
          date: c.date,
          amount: num(c.amount),
          currency: c.currency,
          amount_in_account_currency:
            c.amount_in_account_currency === null ? null : num(c.amount_in_account_currency),
          // The snapshot, taken from the account this transaction actually sits on
          // (v60). Was hardcoded null since the engine was written, which left a
          // column with a reader and no writer.
          card_label: labelFor(c.account_id),
        })),
      }
      run = applyAssertions(run, stored)

      const dedupe_key = stored
        ? (storedSubs.find((s) => (runsBySub.get(s.id) ?? []).some((r) => r.id === stored.id))
            ?.dedupe_key ?? keys[idx])
        : keys[idx]
      const storedSub = storedSubs.find((s) => s.dedupe_key === dedupe_key)

      subscriptions.push({
        stored_id: storedSub?.id ?? null,
        dedupe_key,
        merchant_key: merchant,
        // Engine-seeded, frozen once the user renamed it. Resolved here rather
        // than in the applier, which stays dumb.
        service_name:
          storedSub && storedSub.identification === 'user_renamed'
            ? storedSub.service_name
            : deriveServiceName(proto.charges[0]),
        runs: [run],
      })
    })
  }

  // A stored run whose every LIVE charge has vanished is deleted, even if it
  // carried an assertion — its basis is gone. A run holding frozen charges
  // always survives, because those are its basis.
  const frozenRunIds = new Set(
    input.charges.filter((c) => c.transaction_id === null).map((c) => c.run_id),
  )
  const delete_run_ids = input.runs
    .filter((r) => !keptRunIds.has(r.id) && !frozenRunIds.has(r.id))
    .map((r) => r.id)
    .sort()

  return {
    subscriptions: mergeByDedupeKey(subscriptions),
    delete_run_ids,
    diagnostics: {
      ...diagnostics,
      r1_runs: r1Runs,
      r3_runs: r3Runs,
      r4_runs: r4Runs,
      r5_trailing: r5Trailing,
      r5_unclaimed: r5Unclaimed,
    },
  }
}

function num(v: number | string): number {
  return typeof v === 'string' ? Number(v) : v
}

function deriveServiceName(first: TxRow): string {
  return (first.provider_merchant_name ?? first.raw_description).trim().slice(0, 120)
}

/** One entry per dedupe_key, runs collected under it. */
function mergeByDedupeKey(list: DesiredSubscription[]): DesiredSubscription[] {
  const out = new Map<string, DesiredSubscription>()
  for (const s of list) {
    const existing = out.get(s.dedupe_key)
    if (existing) existing.runs.push(...s.runs)
    else out.set(s.dedupe_key, { ...s, runs: [...s.runs] })
  }
  return [...out.values()].sort((a, b) => (a.dedupe_key < b.dedupe_key ? -1 : 1))
}
