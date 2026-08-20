
import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import { type Held, withdrawalDecision } from './sync.ts'

function held(...ids: string[]): Held[] {
  return ids.map((p) => ({ id: `row-${p}`, provider_tx_id: p }))
}

Deno.test('rows missing from a non-empty feed are withdrawn', () => {
  const d = withdrawalDecision(['a', 'c'], held('a', 'b', 'c'), false)
  assertEquals(d, { kind: 'withdraw', ids: ['row-b'] })
})

Deno.test('a feed that still lists every held row withdraws nothing', () => {
  const d = withdrawalDecision(['a', 'b'], held('a', 'b'), false)
  assertEquals(d.kind, 'noop')
})

Deno.test('a truncated response withdraws nothing, even where rows are missing', () => {
  const d = withdrawalDecision(['a'], held('a', 'b', 'c'), true)
  assertEquals(d.kind, 'noop')
})

Deno.test('THE GUARD: an empty feed against held rows is refused, not obeyed', () => {
  const d = withdrawalDecision([], held('a', 'b', 'c'), false)
  assertEquals(d.kind, 'refuse')
  if (d.kind !== 'refuse') return
  assertEquals(d.reason.includes('3 held row(s)'), true, 'the count is what makes the log useful')
})

Deno.test('an empty feed with nothing held is ordinary, not a failure', () => {
  const d = withdrawalDecision([], [], false)
  assertEquals(d.kind, 'noop')
})

Deno.test('an empty feed AND truncation reads as truncation', () => {
  const d = withdrawalDecision([], held('a'), true)
  assertEquals(d.kind, 'noop')
})

Deno.test('DELIBERATE LIMIT: a nearly-empty feed is trusted', () => {
  const rows = held(...Array.from({ length: 200 }, (_, i) => `t${i}`))
  const d = withdrawalDecision(['t0'], rows, false)
  assertEquals(d.kind, 'withdraw')
  if (d.kind !== 'withdraw') return
  assertEquals(d.ids.length, 199)
})
