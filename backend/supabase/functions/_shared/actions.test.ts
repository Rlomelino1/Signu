import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import {
  attributedSubscriptionIds,
  cancellation,
  type CancelRun,
  confirmation,
  type ConfirmRun,
  type ConfirmSubscription,
} from './actions.ts'

const TODAY = '2026-08-12'

function run(over: Partial<ConfirmRun> = {}): ConfirmRun {
  return {
    id: 'run-1',
    subscription_id: 'sub-1',
    status: 'possible',
    detected_by: 'R3',
    billing_interval: 'monthly',
    ...over,
  }
}

function sub(over: Partial<ConfirmSubscription> = {}): ConfirmSubscription {
  return { id: 'sub-1', identification: 'auto', ...over }
}

// ------------------------------------------------------------------- confirm

Deno.test('confirming an R3 suggestion lifts the run out of possible', () => {
  const d = confirmation(run(), sub(), null)
  assertEquals(d.kind, 'write')
  if (d.kind !== 'write') return
  assertEquals(d.write.run.status, 'active')
  assertEquals(d.write.subscription, { identification: 'user_confirmed' })
})

Deno.test('an R3 confirmation does not touch billing_interval', () => {
  // Three date-aligned charges measured the cadence. Writing it again at
  // confirmation would let a client's idea of the interval overwrite a
  // measurement.
  const d = confirmation(run(), sub(), null)
  if (d.kind !== 'write') throw new Error('expected a write')
  assertEquals('billing_interval' in d.write.run, false)
})

Deno.test('an interval sent for an R3 run is refused, not ignored', () => {
  // The client decides whether to ask from `asksIntervalOnTrack`. One arriving
  // here means that flag and this rule have drifted apart, which is worth a 400
  // rather than a silent drop.
  const d = confirmation(run(), sub(), 'annual')
  assertEquals(d.kind, 'refuse')
  if (d.kind === 'refuse') assertEquals(d.status, 400)
})

Deno.test('an R4 confirmation writes the interval the user chose', () => {
  const d = confirmation(run({ detected_by: 'R4' }), sub(), 'annual')
  if (d.kind !== 'write') throw new Error('expected a write')
  assertEquals(d.write.run.billing_interval, 'annual')
})

Deno.test('an R4 confirmation without an interval is refused', () => {
  // R4 creates a run from a single charge and writes a provisional monthly.
  // Letting that provisional value stand as though the user had picked it is
  // exactly what the sheet exists to prevent.
  const d = confirmation(run({ detected_by: 'R4' }), sub(), null)
  assertEquals(d.kind, 'refuse')
  if (d.kind === 'refuse') assertEquals(d.status, 400)
})

Deno.test('confirming an already-confirmed run is a no-op, not an error', () => {
  // Above `possible` on an R3/R4 run IS the stored confirmation. A second tap
  // after a dropped response is a success from where the user sits.
  for (const status of ['active', 'overdue', 'ended'] as const) {
    const d = confirmation(run({ status }), sub({ identification: 'user_confirmed' }), null)
    assertEquals(d.kind, 'noop', status)
  }
})

Deno.test('a cancelled run is not re-confirmable', () => {
  const d = confirmation(run({ status: 'cancelled' }), sub(), null)
  assertEquals(d.kind, 'noop')
})

Deno.test('R1 runs cannot be confirmed', () => {
  // R1 auto-confirms at detection and never appears on the review screen, so a
  // confirm aimed at one would record a decision the user was never offered.
  const d = confirmation(run({ detected_by: 'R1' }), sub(), null)
  assertEquals(d.kind, 'refuse')
  if (d.kind === 'refuse') assertEquals(d.status, 409)
})

Deno.test('confirming a renamed subscription leaves identification alone', () => {
  // `user_renamed` freezes service_name against the engine. Demoting it to
  // `user_confirmed` would unfreeze the name and let the next detection pass
  // overwrite what the user typed.
  const d = confirmation(run(), sub({ identification: 'user_renamed' }), null)
  if (d.kind !== 'write') throw new Error('expected a write')
  assertEquals(d.write.subscription, null)
  assertEquals(d.write.run.status, 'active')
})

Deno.test('a run belonging to another subscription is refused', () => {
  const d = confirmation(run({ subscription_id: 'sub-2' }), sub(), null)
  assertEquals(d.kind, 'refuse')
  if (d.kind === 'refuse') assertEquals(d.status, 400)
})

// -------------------------------------------------------------------- cancel

function cancelRun(over: Partial<CancelRun> = {}): CancelRun {
  return {
    id: 'run-1',
    status: 'active',
    billing_interval: 'monthly',
    start_date: '2026-01-07',
    ...over,
  }
}

Deno.test('cancelling sets paid-through to one interval past the last charge', () => {
  const d = cancellation(cancelRun(), '2026-08-07', TODAY)
  if (d.kind !== 'write') throw new Error('expected a write')
  assertEquals(d.write.run.status, 'cancelled')
  assertEquals(d.write.run.cancelled_date, TODAY)
  assertEquals(d.write.run.end_date, '2026-09-07')
  assertEquals(d.write.run.next_expected_date, null)
})

Deno.test('end_date is measured from the charge, never from the cancellation', () => {
  // The user keeps the service through the period they already paid for, and
  // "paid through" is a fact about the last charge — not about when they got
  // round to telling us.
  const d = cancellation(cancelRun(), '2026-08-07', '2026-08-30')
  if (d.kind !== 'write') throw new Error('expected a write')
  assertEquals(d.write.run.end_date, '2026-09-07')
})

Deno.test('an annual run is paid through a year past its last charge', () => {
  const d = cancellation(cancelRun({ billing_interval: 'annual' }), '2026-03-31', TODAY)
  if (d.kind !== 'write') throw new Error('expected a write')
  assertEquals(d.write.run.end_date, '2027-03-31')
})

Deno.test('paid-through clamps to the end of a short month', () => {
  // Jan 31 + one month is Feb 28, not Mar 3 — a subscription billed on the 31st
  // does not migrate into the following month.
  const d = cancellation(cancelRun(), '2026-01-31', TODAY)
  if (d.kind !== 'write') throw new Error('expected a write')
  assertEquals(d.write.run.end_date, '2026-02-28')
})

Deno.test('an overdue run can be cancelled', () => {
  // "Mark cancelled" renders on active and overdue alike: the charge that never
  // arrived is often exactly what prompts the user to say they cancelled.
  assertEquals(cancellation(cancelRun({ status: 'overdue' }), '2026-07-07', TODAY).kind, 'write')
})

Deno.test('cancelling twice is a no-op', () => {
  const d = cancellation(cancelRun({ status: 'cancelled' }), '2026-08-07', TODAY)
  assertEquals(d.kind, 'noop')
})

Deno.test('possible and ended runs cannot be cancelled', () => {
  // Nothing was ever tracked in the first case; in the second the engine already
  // observed the death, and overwriting an inference the data supports with an
  // assertion it does not is a downgrade.
  for (const status of ['possible', 'ended'] as const) {
    const d = cancellation(cancelRun({ status }), '2026-08-07', TODAY)
    assertEquals(d.kind, 'refuse', status)
    if (d.kind === 'refuse') assertEquals(d.status, 409, status)
  }
})

Deno.test('a run with no charges falls back to its own start date', () => {
  const d = cancellation(cancelRun(), null, TODAY)
  if (d.kind !== 'write') throw new Error('expected a write')
  assertEquals(d.write.run.end_date, '2026-02-07')
})

// --------------------------------------------------------------- attribution

const ATTR = {
  subscriptionIds: ['sub-1'],
  runs: [{ id: 'run-1', subscription_id: 'sub-1', start_date: '2026-01-07' }],
  charges: [{ id: 'ch-1', run_id: 'run-1', date: '2026-08-07', transaction_id: 'tx-1' }],
  transactionAccount: { 'tx-1': 'acc-1' },
  connectionAccountIds: ['acc-1'],
}

Deno.test('a subscription whose latest charge is on this bank is attributed', () => {
  assertEquals(attributedSubscriptionIds(ATTR), ['sub-1'])
})

Deno.test('attribution follows the latest charge of the latest run only', () => {
  // A subscription that card-hopped away: older charges here, the newest one
  // elsewhere. Not attributed — and its old charges survive either path with
  // transaction_id NULLed.
  const out = attributedSubscriptionIds({
    ...ATTR,
    runs: [
      { id: 'run-old', subscription_id: 'sub-1', start_date: '2025-01-07' },
      { id: 'run-1', subscription_id: 'sub-1', start_date: '2026-01-07' },
    ],
    charges: [
      { id: 'ch-old', run_id: 'run-old', date: '2025-06-07', transaction_id: 'tx-1' },
      { id: 'ch-1', run_id: 'run-1', date: '2026-07-07', transaction_id: 'tx-9' },
      { id: 'ch-2', run_id: 'run-1', date: '2026-08-07', transaction_id: 'tx-elsewhere' },
    ],
    transactionAccount: { 'tx-1': 'acc-1', 'tx-9': 'acc-1', 'tx-elsewhere': 'acc-other' },
  })
  assertEquals(out, [])
})

Deno.test('mixed evidence counts when the newest charge landed here', () => {
  // Accepted with eyes open when the rule was locked: "Delete them too" then
  // erases that subscription's other-bank charges as well, which is why 13a
  // exists as the pre-delete view.
  const out = attributedSubscriptionIds({
    ...ATTR,
    charges: [
      { id: 'ch-0', run_id: 'run-1', date: '2026-06-07', transaction_id: 'tx-other' },
      { id: 'ch-1', run_id: 'run-1', date: '2026-08-07', transaction_id: 'tx-1' },
    ],
    transactionAccount: { 'tx-1': 'acc-1', 'tx-other': 'acc-other' },
  })
  assertEquals(out, ['sub-1'])
})

Deno.test('a charge whose transaction is already gone is not attributed', () => {
  // transaction_id NULL is a charge that survived an earlier bank removal. It
  // describes itself and belongs to no connection.
  const out = attributedSubscriptionIds({
    ...ATTR,
    charges: [{ id: 'ch-1', run_id: 'run-1', date: '2026-08-07', transaction_id: null }],
  })
  assertEquals(out, [])
})

Deno.test('every card of the connection attributes, not just the first', () => {
  const out = attributedSubscriptionIds({
    ...ATTR,
    transactionAccount: { 'tx-1': 'acc-2' },
    connectionAccountIds: ['acc-1', 'acc-2'],
  })
  assertEquals(out, ['sub-1'])
})

Deno.test('same-day charges resolve by id, so two calls agree', () => {
  // Date alone is not a total order. A server that picks differently on two
  // calls would attribute a subscription to one bank and then the other.
  const charges = [
    { id: 'ch-a', run_id: 'run-1', date: '2026-08-07', transaction_id: 'tx-here' },
    { id: 'ch-b', run_id: 'run-1', date: '2026-08-07', transaction_id: 'tx-elsewhere' },
  ]
  const input = {
    ...ATTR,
    charges,
    transactionAccount: { 'tx-here': 'acc-1', 'tx-elsewhere': 'acc-other' },
  }
  assertEquals(attributedSubscriptionIds(input), [])
  assertEquals(attributedSubscriptionIds({ ...input, charges: [...charges].reverse() }), [])
})

Deno.test('a subscription with no runs or no charges is not attributed', () => {
  assertEquals(attributedSubscriptionIds({ ...ATTR, runs: [] }), [])
  assertEquals(attributedSubscriptionIds({ ...ATTR, charges: [] }), [])
})

Deno.test('dismissed subscriptions are attributed like any other', () => {
  // The caller passes every subscription including `ignored` ones, because the
  // count in the sheet includes them — no invisible ghost data.
  assertEquals(
    attributedSubscriptionIds({ ...ATTR, subscriptionIds: ['sub-1', 'sub-dismissed'] }),
    ['sub-1'],
  )
})
