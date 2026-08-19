// Rules for the sync-time decisions. The withdrawal one is here because it can
// destroy user assertions if it is wrong, and until v71 it lived inline in
// `pluggy-sync/index.ts` where no CI job could reach it.

import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import { type Held, withdrawalDecision } from './sync.ts'

function held(...ids: string[]): Held[] {
  return ids.map((p) => ({ id: `row-${p}`, provider_tx_id: p }))
}

Deno.test('rows missing from a non-empty feed are withdrawn', () => {
  // The case withdrawal exists for: a content hash changed, or the bank dropped
  // the row for a day, so it is absent under its old id.
  const d = withdrawalDecision(['a', 'c'], held('a', 'b', 'c'), false)
  assertEquals(d, { kind: 'withdraw', ids: ['row-b'] })
})

Deno.test('a feed that still lists every held row withdraws nothing', () => {
  const d = withdrawalDecision(['a', 'b'], held('a', 'b'), false)
  assertEquals(d.kind, 'noop')
})

Deno.test('a truncated response withdraws nothing, even where rows are missing', () => {
  // Pre-existing behaviour, previously untested: the `if (!truncated)` gate was
  // the whole rule and nothing checked it.
  const d = withdrawalDecision(['a'], held('a', 'b', 'c'), true)
  assertEquals(d.kind, 'noop')
})

Deno.test('THE GUARD: an empty feed against held rows is refused, not obeyed', () => {
  // A revoked Open Finance consent returns 200 with zero transactions. Obeying it
  // marks all three withdrawn, which empties the candidate set, which lets
  // delete_run_ids remove every non-frozen run along with its assertions.
  const d = withdrawalDecision([], held('a', 'b', 'c'), false)
  assertEquals(d.kind, 'refuse')
  if (d.kind !== 'refuse') return
  assertEquals(d.reason.includes('3 held row(s)'), true, 'the count is what makes the log useful')
})

Deno.test('an empty feed with nothing held is ordinary, not a failure', () => {
  // A new account, or a genuinely quiet window. Refusing here would make first
  // sync on a fresh connection report an error.
  const d = withdrawalDecision([], [], false)
  assertEquals(d.kind, 'noop')
})

Deno.test('an empty feed AND truncation reads as truncation', () => {
  // Order matters: a truncated feed can arrive empty, and then incompleteness is
  // the honest explanation rather than a revoked consent.
  const d = withdrawalDecision([], held('a'), true)
  assertEquals(d.kind, 'noop')
})

Deno.test('DELIBERATE LIMIT: a nearly-empty feed is trusted', () => {
  // One row where two hundred were held withdraws the other 199. Documented as a
  // decision: no threshold separates a partial revocation from a quiet month
  // without inventing a number, so only total silence is refused.
  const rows = held(...Array.from({ length: 200 }, (_, i) => `t${i}`))
  const d = withdrawalDecision(['t0'], rows, false)
  assertEquals(d.kind, 'withdraw')
  if (d.kind !== 'withdraw') return
  assertEquals(d.ids.length, 199)
})
