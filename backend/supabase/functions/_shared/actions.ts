
import { addInterval, type Interval } from './dates.ts'

export type { Interval }

export type RunStatus = 'possible' | 'active' | 'overdue' | 'ended' | 'cancelled'
export type DetectedBy = 'R1' | 'R3' | 'R4'
export type Identification = 'auto' | 'user_confirmed' | 'user_renamed'

export type Decision<W> =
  | { kind: 'write'; write: W }
  | { kind: 'noop'; reason: string }
  | { kind: 'refuse'; reason: string; status: number }


export type ConfirmRun = {
  id: string
  subscription_id: string
  status: RunStatus
  detected_by: DetectedBy
  billing_interval: Interval
}

export type ConfirmSubscription = {
  id: string
  identification: Identification
}

export type ConfirmWrite = {
  runId: string
  run: { status: 'active'; billing_interval?: Interval }
  subscriptionId: string
  subscription: { identification: 'user_confirmed' } | null
}

export function confirmation(
  run: ConfirmRun,
  subscription: ConfirmSubscription,
  interval: Interval | null,
): Decision<ConfirmWrite> {
  if (run.subscription_id !== subscription.id) {
    return { kind: 'refuse', reason: 'run does not belong to that subscription', status: 400 }
  }

  if (run.detected_by === 'R1') {
    return { kind: 'refuse', reason: 'R1 runs are tracked at detection, never confirmed', status: 409 }
  }

  if (run.status !== 'possible') {
    return { kind: 'noop', reason: `run is already confirmed (status ${run.status})` }
  }

  if (run.detected_by !== 'R4' && interval !== null) {
    return {
      kind: 'refuse',
      reason: `billing interval supplied for a ${run.detected_by} run, whose cadence was measured`,
      status: 400,
    }
  }

  // R4 creates a run from a single charge and writes a provisional monthly, so
  // the confirm flow's answer is the authoritative write (v11). Missing means
  // the client skipped the sheet; writing the provisional value as though the
  // user had chosen it is exactly the dishonesty the sheet exists to prevent.
  if (run.detected_by === 'R4' && interval === null) {
    return { kind: 'refuse', reason: 'R4 confirmation must state monthly or annual', status: 400 }
  }

  return {
    kind: 'write',
    write: {
      runId: run.id,
      run: interval === null ? { status: 'active' } : { status: 'active', billing_interval: interval },
      subscriptionId: subscription.id,
      // `user_renamed` is the stronger assertion — it freezes `service_name`
      // against the engine — so confirming a subscription the user has already
      // renamed must not demote it. Both values mean "the user has spoken about
      // this row"; only one of them also means "do not touch the name".
      subscription: subscription.identification === 'auto' ? { identification: 'user_confirmed' } : null,
    },
  }
}

// -------------------------------------------------------------------- cancel

export type CancelRun = {
  id: string
  status: RunStatus
  billing_interval: Interval
  start_date: string
}

export type CancelWrite = {
  runId: string
  run: {
    status: 'cancelled'
    cancelled_date: string
    end_date: string
    next_expected_date: null
  }
}

/**
 * The detail screen's *Mark cancelled* — the user asserting "I cancelled this",
 * which is a different fact from the engine inferring death at +10 (`ended`).
 * The UI copy differs for that reason, so the two statuses must not merge.
 *
 * `end_date` stays paid-through (last charge + one interval), NOT the
 * cancellation date: the user keeps the service until the period they already
 * paid for runs out, and the detail screen renders that date as "paid through".
 * `next_expected_date` is NULLed and stays null even if an R5 trailing charge
 * appends, so a cancelled run can never reappear in "Coming up" or trip
 * overdue.
 */
export function cancellation(
  run: CancelRun,
  latestChargeDate: string | null,
  today: string,
): Decision<CancelWrite> {
  if (run.status === 'cancelled') {
    return { kind: 'noop', reason: 'run is already cancelled' }
  }

  // `showMarkCancelled` renders on exactly these two states. A `possible` run
  // has not been confirmed, so there is nothing the user could have cancelled;
  // an `ended` run already stopped being charged, and overwriting its
  // engine-inferred death with an assertion would rewrite a fact the data
  // supports with one it does not.
  if (run.status !== 'active' && run.status !== 'overdue') {
    return { kind: 'refuse', reason: `a ${run.status} run cannot be cancelled`, status: 409 }
  }

  // A run exists because charges exist, so the fallback should be unreachable —
  // it is here because `end_date` is NOT NULL-able in meaning if not in schema,
  // and a paid-through date derived from the run's own start is still honest
  // where a null would render as blank.
  const paidFrom = latestChargeDate ?? run.start_date

  return {
    kind: 'write',
    write: {
      runId: run.id,
      run: {
        status: 'cancelled',
        cancelled_date: today,
        end_date: addInterval(paidFrom, run.billing_interval),
        next_expected_date: null,
      },
    },
  }
}

// --------------------------------------------------------------- attribution

export type AttrRun = { id: string; subscription_id: string; start_date: string }
export type AttrCharge = { run_id: string; date: string; id: string; transaction_id: string | null }

export type AttributionInput = {
  subscriptionIds: string[]
  runs: AttrRun[]
  charges: AttrCharge[]
  /** transaction id → bank_account id, for the transactions charges point at. */
  transactionAccount: Record<string, string>
  /** bank_account ids belonging to the connection being removed. */
  connectionAccountIds: string[]
}

/**
 * "Found via this bank" (12c, locked v8): a subscription is attributed to a
 * connection iff the **latest charge of its latest run** resolves through
 * `transaction_id` to a transaction under that connection. Most-recent-charge
 * wins, the data decides — the same rule the card row on the detail screen uses,
 * and deliberately not "has any charge here".
 *
 * Consequences, both accepted with eyes open when the rule was locked: a
 * mixed-evidence subscription whose latest charge landed here IS attributed, so
 * "Delete them too" takes its other-bank charges as well; a subscription that
 * card-hopped away is NOT attributed, and its old charges under this connection
 * survive either path as `transaction_id = NULL` + `card_label`.
 *
 * This is the third implementation of one rule — the app renders it on 12b and
 * 13a — and the count it produces must equal what those screens showed, or the
 * sheet promises to delete a different number of things than it deletes.
 * Ordering is therefore total here, tie-broken by id: two rows sharing a date is
 * unlikely and a server that resolves it differently on two calls is worse.
 */
export function attributedSubscriptionIds(input: AttributionInput): string[] {
  const accounts = new Set(input.connectionAccountIds)
  const latestRuns = latestRunPerSubscription(input.runs)
  const latestCharges = latestChargePerRun(input.charges)

  const attributed: string[] = []
  for (const subId of input.subscriptionIds) {
    const latestRun = latestRuns.get(subId)
    if (!latestRun) continue
    const latestCharge = latestCharges.get(latestRun.id)
    if (!latestCharge?.transaction_id) continue
    const accountId = input.transactionAccount[latestCharge.transaction_id]
    if (accountId && accounts.has(accountId)) attributed.push(subId)
  }
  return attributed
}

/** Exported because the caller narrows its queries with the same two steps the
 *  rule takes: loading every run and every charge of an account to find one
 *  transaction each would eventually cross PostgREST's 1000-row ceiling and
 *  return a *quietly* shorter answer — a truncated attribution reads exactly
 *  like a smaller bank. Re-running them inside the rule is idempotent, so the
 *  narrowing cannot change the verdict. */
export function latestRunPerSubscription(runs: AttrRun[]): Map<string, AttrRun> {
  const out = new Map<string, AttrRun>()
  for (const r of runs) {
    const held = out.get(r.subscription_id)
    if (!held || compare(held.start_date, held.id, r.start_date, r.id) < 0) out.set(r.subscription_id, r)
  }
  return out
}

export function latestChargePerRun(charges: AttrCharge[]): Map<string, AttrCharge> {
  const out = new Map<string, AttrCharge>()
  for (const c of charges) {
    const held = out.get(c.run_id)
    if (!held || compare(held.date, held.id, c.date, c.id) < 0) out.set(c.run_id, c)
  }
  return out
}

/** Total order on (date, id) — date alone is not one, and an unstable pick
 *  would make the same account attribute differently on two calls. */
function compare(dateA: string, idA: string, dateB: string, idB: string): number {
  if (dateA !== dateB) return dateA < dateB ? -1 : 1
  if (idA === idB) return 0
  return idA < idB ? -1 : 1
}
