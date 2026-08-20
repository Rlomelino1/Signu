
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

  if (run.detected_by === 'R4' && interval === null) {
    return { kind: 'refuse', reason: 'R4 confirmation must state monthly or annual', status: 400 }
  }

  return {
    kind: 'write',
    write: {
      runId: run.id,
      run: interval === null ? { status: 'active' } : { status: 'active', billing_interval: interval },
      subscriptionId: subscription.id,
      subscription: subscription.identification === 'auto' ? { identification: 'user_confirmed' } : null,
    },
  }
}


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

export function cancellation(
  run: CancelRun,
  latestChargeDate: string | null,
  today: string,
): Decision<CancelWrite> {
  if (run.status === 'cancelled') {
    return { kind: 'noop', reason: 'run is already cancelled' }
  }

  if (run.status !== 'active' && run.status !== 'overdue') {
    return { kind: 'refuse', reason: `a ${run.status} run cannot be cancelled`, status: 409 }
  }

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


export type AttrRun = { id: string; subscription_id: string; start_date: string }
export type AttrCharge = { run_id: string; date: string; id: string; transaction_id: string | null }

export type AttributionInput = {
  subscriptionIds: string[]
  runs: AttrRun[]
  charges: AttrCharge[]
  transactionAccount: Record<string, string>
  connectionAccountIds: string[]
}

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

function compare(dateA: string, idA: string, dateB: string, idB: string): number {
  if (dateA !== dateB) return dateA < dateB ? -1 : 1
  if (idA === idB) return 0
  return idA < idB ? -1 : 1
}
