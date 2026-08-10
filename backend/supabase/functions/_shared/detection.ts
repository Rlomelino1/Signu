// The detection engine's pure core (v24).
//
// Rules in, desired state out. No database access, no clock reads, no I/O.
// `today` is a parameter, never read inside a rule, so every rule is testable
// against a fixed date. The shell (run-detection/index.ts) does the loading and
// the single atomic write; nothing here knows a database exists.
//
// Recompute is RECONCILE, not rebuild: user assertions are read and never
// written, and charges whose transaction_id is NULL are a frozen region that is
// never recomputed, never deleted and never re-parented.

import { moneyKey, sameMoney } from './money.ts'
import { addInterval, circularDomDistance, daysBetween, type Interval } from './dates.ts'

// ----------------------------------------------------------------------- input

export interface TxRow {
  id: string
  provider_tx_id: string
  account_id: string
  status: string
  type: string
  date: string
  amount: number | string
  currency: string
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

export interface EngineInput {
  today: string
  rows: TxRow[]
  subscriptions: StoredSubscription[]
  runs: StoredRun[]
  charges: StoredCharge[]
}

// ---------------------------------------------------------------------- output

export interface DesiredCharge {
  transaction_id: string
  date: string
  amount: number
  currency: string
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

// --------------------------------------------------------------- candidate pass
//
// Per-USER, never per-account: filter 4 compares a DEBIT against CREDITs on the
// user's OTHER accounts, so sharding by account would silently disable it (v24).

/** NULL / '' / 'NA' / 'N/A' all mean "no fee". Presence carries no information:
 *  fee_type_additional_info is populated on 164 of 165 card rows, 'NA' on 104 of
 *  them. Testing IS NOT NULL excludes 146 of 258 rows and detects nothing (v21). */
const NOT_A_FEE = new Set(['', 'NA', 'N/A'])

export function isFee(r: TxRow): boolean {
  const v = r.fee_type_additional_info
  if (v === null || v === undefined) return false
  return !NOT_A_FEE.has(v.trim().toUpperCase())
}

/** Metadata first; descriptor N/M marker as the documented fallback for banks
 *  that omit the fields. Agreed 7/7 with zero disagreements on real data (v21). */
const PARCEL_IN_DESCRIPTOR = /(^|[^0-9])\d{1,2}\s*\/\s*\d{1,2}([^0-9]|$)/

export function isInstallment(r: TxRow): boolean {
  if (r.installment_number !== null || r.total_installments !== null) return true
  return PARCEL_IN_DESCRIPTOR.test(r.raw_description)
}

/** Paying the credit card writes two rows when both accounts are connected: a
 *  CREDIT on the card and a DEBIT on the checking account. Filter 1 catches the
 *  card side; this catches the other. Structural, not lexical, so it survives
 *  rewording and unseen institutions (v21). Verified 12/12 on real data. */
export function isInternalTransfer(r: TxRow, allRows: TxRow[]): boolean {
  if (r.type !== 'DEBIT') return false
  return allRows.some(
    (c) =>
      c.type === 'CREDIT' &&
      c.account_id !== r.account_id &&
      // Currency-aware: a USD card charge numerically matching a BRL bank
      // credit would wrongly EXCLUDE a real transaction (v25).
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

// ------------------------------------------------------------------ merchant_key
//
// CNPJ where present, normalized descriptor otherwise, with an aggregator
// exception in the other direction (v21).

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
    // One PayPal CNPJ covers five unrelated merchants; keying on it alone would
    // anchor a phantom subscription, so the descriptor suffix is retained.
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
  detected_by: 'R1' | 'R3'
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
      return {
        ...desired,
        status: 'cancelled',
        cancelled_date: stored.cancelled_date,
        end_date: stored.end_date,
        next_expected_date: null,
        detected_by: stored.detected_by,
      }
    }

    // A confirmed suggestion is an assertion: R3/R4 above 'possible' means the
    // user said yes, so the derived lifecycle status is allowed to stand and the
    // suggestion is not demoted back to 'possible'. R1 status is always derived.
    const confirmedSuggestion =
      (stored.detected_by === 'R3' || stored.detected_by === 'R4') &&
      stored.status !== 'possible'

    if (confirmedSuggestion) {
      return {
        ...desired,
        detected_by: stored.detected_by,
        // R4's interval is the confirm flow's authoritative write (v11).
        billing_interval:
          stored.detected_by === 'R4' ? stored.billing_interval : desired.billing_interval,
      }
    }
  }

  // Suggest-only rules are never promoted by the engine -- only the user
  // promotes them. Deliberately OUTSIDE the `stored` branch: a brand-new R3
  // suggestion has no stored row, and an early return here would let it inherit
  // the derived lifecycle status and auto-activate. That defect was live until a
  // test caught it.
  if (desired.detected_by === 'R3' || desired.detected_by === 'R4') {
    return { ...desired, status: 'possible' }
  }
  return desired
}

// ------------------------------------------------------------------ dedupe_key
//
// UNIQUE(user_id, dedupe_key), forking to `key:2` when one merchant hosts two
// concurrent subscriptions. Ordinals are assigned by ASCENDING FIRST-CHARGE
// DATE, tie-broken by provider_tx_id — never discovery order. Discovery-order
// numbering would let a recompute renumber and silently re-attach a user's
// nickname, category and reminders to the WRONG subscription (v24).

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

  // Deterministic group order, so output ordering is stable run to run.
  for (const merchant of [...groups.keys()].sort()) {
    const group = groups.get(merchant)!.slice().sort(compareRows)

    const claimed = new Set<string>()
    const protos = anchorR1(group)
    protos.forEach((p) => p.charges.forEach((c) => claimed.add(c.id)))
    protos.forEach((p) => backfillR2(p, group, claimed))

    if (protos.length === 0) {
      const leftover = group.filter((c) => !claimed.has(c.id))
      const s = suggestR3(leftover)
      if (s) protos.push(s)
    }
    if (protos.length === 0) continue

    r1Runs += protos.filter((p) => p.detected_by === 'R1').length
    r3Runs += protos.filter((p) => p.detected_by === 'R3').length

    const keys = dedupeKeys(merchant, protos)
    const storedSubs = storedByMerchant.get(merchant) ?? []
    const candidateStoredRuns = storedSubs.flatMap((s) => runsBySub.get(s.id) ?? [])
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
          amount: typeof c.amount === 'string' ? Number(c.amount) : c.amount,
          currency: c.currency,
          card_label: null,
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
    diagnostics: { ...diagnostics, r1_runs: r1Runs, r3_runs: r3Runs },
  }
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
