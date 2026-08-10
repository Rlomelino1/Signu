// Rule tests for the detection core.
//
// FIXTURE NOTE: v24 says fixtures are "the real 258 rows captured by v20's
// probe". They cannot be committed -- pluggy-probe-raw.json is gitignored
// because it is real bank history and this repo is public. So each case below is
// the STRUCTURAL equivalent of a finding from the dry run, reduced to the
// minimum rows that reproduce it, and the real-258-row check stays local via
// backend/pluggy-detection-dryrun.py. Every false positive the dry run found has
// a regression test here.
//
// Run:  deno test --allow-none backend/supabase/functions/_shared/detection.test.ts

import { assert, assertEquals, assertFalse } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import { cents, moneyKey, sameMoney } from './money.ts'
import { addMonths, circularDomDistance, daysBetween } from './dates.ts'
import {
  detect,
  filterCandidates,
  isFee,
  isInstallment,
  isInternalTransfer,
  merchantKey,
  type TxRow,
} from './detection.ts'

let seq = 0
function row(over: Partial<TxRow> = {}): TxRow {
  seq++
  return {
    id: over.id ?? `tx-${String(seq).padStart(4, '0')}`,
    provider_tx_id: over.provider_tx_id ?? `p-${String(seq).padStart(4, '0')}`,
    account_id: 'acct-card',
    status: 'posted',
    type: 'DEBIT',
    date: '2026-01-10',
    amount: 39.9,
    currency: 'BRL',
    amount_in_account_currency: null,
    raw_description: 'ACME STREAMING',
    normalized_merchant: 'ACME STREAMING',
    withdrawn_at: null,
    installment_number: null,
    total_installments: null,
    fee_type_additional_info: null,
    provider_merchant_name: null,
    provider_merchant_cnpj: null,
    ...over,
  }
}

const EMPTY = { subscriptions: [], runs: [], charges: [] }

// --------------------------------------------------------------------- money

Deno.test('v23 regression: amounts a cent apart are NOT the same amount', () => {
  assertFalse(sameMoney({ amount: 6.46, currency: 'BRL' }, { amount: 6.45, currency: 'BRL' }))
  assert(Math.abs(6.46 - 6.45) < 0.01, 'the float epsilon that caused the bug still misfires')
  assertEquals(cents(6.45), 645)
  assertEquals(cents(-6.45), 645, 'magnitude, so card and bank sign dialects compare')
})

// ------------------------------------------------------------ candidate filter

Deno.test('fee exclusion is by VALUE, never presence', () => {
  assertFalse(isFee(row({ fee_type_additional_info: null })))
  assertFalse(isFee(row({ fee_type_additional_info: 'NA' })), "'NA' means no fee")
  assertFalse(isFee(row({ fee_type_additional_info: '' })))
  assert(isFee(row({ fee_type_additional_info: 'IOF_COMPRA_INTERNACIONAL' })))
})

Deno.test('presence-based fee filtering would eat the ledger (the v21 bug)', () => {
  // 4 real purchases carrying the 'NA' sentinel + 1 actual fee.
  const rows = [
    row({ fee_type_additional_info: 'NA' }),
    row({ fee_type_additional_info: 'NA' }),
    row({ fee_type_additional_info: 'NA' }),
    row({ fee_type_additional_info: 'NA' }),
    row({ fee_type_additional_info: 'IOF_COMPRA_INTERNACIONAL' }),
  ]
  const { candidates } = filterCandidates(rows)
  assertEquals(candidates.length, 4, 'only the real fee is excluded')
})

Deno.test('installments are excluded by metadata and by descriptor marker', () => {
  assert(isInstallment(row({ installment_number: 2 })))
  assert(isInstallment(row({ total_installments: 12 })))
  assert(isInstallment(row({ raw_description: 'AMAZON MARKETPLACE 1/2' })))
  assertFalse(isInstallment(row({ raw_description: 'ACME STREAMING' })))
  assertFalse(
    isInstallment(row({ raw_description: 'STORE 24H' })),
    'a bare number must not read as a parcel marker',
  )
})

Deno.test('internal transfer: DEBIT matched by a CREDIT on another account', () => {
  const debit = row({ account_id: 'acct-checking', amount: 1405.28, date: '2026-01-10' })
  const credit = row({ account_id: 'acct-card', type: 'CREDIT', amount: 1405.28, date: '2026-01-10' })
  assert(isInternalTransfer(debit, [debit, credit]))

  const sameAccount = row({ account_id: 'acct-checking', type: 'CREDIT', amount: 1405.28 })
  assertFalse(
    isInternalTransfer(debit, [debit, sameAccount]),
    'same account is not a transfer between accounts',
  )
  const centApart = row({ account_id: 'acct-card', type: 'CREDIT', amount: 1405.27, date: '2026-01-10' })
  assertFalse(
    isInternalTransfer(debit, [debit, centApart]),
    'v23: a cent apart is not the same amount, and this direction HIDES rows',
  )
})

// ------------------------------------------------------------------ merchant_key

Deno.test('merchant_key: CNPJ unifies descriptor variants (the v21 miss)', () => {
  const a = row({ raw_description: 'WL *STEAM PURCHASE', normalized_merchant: 'WL *STEAM PURCHASE', provider_merchant_cnpj: 'CNPJ-SYNTHETIC-1' })
  const b = row({ raw_description: 'STEAM PURCHASE', normalized_merchant: 'STEAM PURCHASE', provider_merchant_cnpj: 'CNPJ-SYNTHETIC-1' })
  assertEquals(merchantKey(a), merchantKey(b))
})

Deno.test('merchant_key: aggregator CNPJ does NOT unify unrelated merchants', () => {
  const a = row({ normalized_merchant: 'PAYPAL *RIOTGAMESIN', provider_merchant_cnpj: '10', provider_merchant_name: 'PAYPAL DO BRASIL' })
  const b = row({ normalized_merchant: 'PAYPAL *LOADED COM', provider_merchant_cnpj: '10', provider_merchant_name: 'PAYPAL DO BRASIL' })
  assert(merchantKey(a) !== merchantKey(b), 'else two unrelated buys anchor a phantom run')
})

Deno.test('merchant_key: no digit stripping (v21 rejected it)', () => {
  const a = row({ normalized_merchant: 'LS4246147' })
  const b = row({ normalized_merchant: 'LS4289481' })
  assert(merchantKey(a) !== merchantKey(b))
})

// ------------------------------------------------------------------------- R1

Deno.test('R1 anchors a same-amount monthly pair', () => {
  const rows = [
    row({ date: '2026-01-10', amount: 39.9 }),
    row({ date: '2026-02-09', amount: 39.9 }),
  ]
  const d = detect({ today: '2026-02-20', rows, ...EMPTY })
  assertEquals(d.subscriptions.length, 1)
  assertEquals(d.subscriptions[0].runs[0].detected_by, 'R1')
  assertEquals(d.subscriptions[0].runs[0].charges.length, 2)
  assertEquals(d.subscriptions[0].runs[0].status, 'active')
})

Deno.test('v23 regression: R1 does NOT anchor a cent-apart pair', () => {
  const rows = [
    row({ date: '2026-01-10', amount: 6.46 }),
    row({ date: '2026-02-09', amount: 6.45 }),
  ]
  const d = detect({ today: '2026-02-20', rows, ...EMPTY })
  assertEquals(d.diagnostics.r1_runs, 0, 'this is the false anchor v23 removed')
})

Deno.test('R1 continuation is amount-flexible so a price rise never splits a run', () => {
  const rows = [
    row({ date: '2026-01-10', amount: 39.9 }),
    row({ date: '2026-02-09', amount: 39.9 }),
    row({ date: '2026-03-10', amount: 44.9 }),
  ]
  const d = detect({ today: '2026-03-20', rows, ...EMPTY })
  assertEquals(d.subscriptions[0].runs[0].charges.length, 3)
})

Deno.test('installment rows never reach R1 (Padrao B false positive)', () => {
  // A 12x purchase: identical amount, one month apart -- R1's exact trigger.
  const rows = [
    row({ date: '2026-01-10', amount: 50, installment_number: 1, total_installments: 12 }),
    row({ date: '2026-02-09', amount: 50, installment_number: 2, total_installments: 12 }),
  ]
  const d = detect({ today: '2026-02-20', rows, ...EMPTY })
  assertEquals(d.subscriptions.length, 0)
  assertEquals(d.diagnostics.excluded_installment, 2)
})

Deno.test('the card bill payment never reaches detection (both sides)', () => {
  const cardCredit = row({ account_id: 'acct-card', type: 'CREDIT', amount: 1405.28, date: '2026-01-10' })
  const bankDebit = row({ account_id: 'acct-checking', amount: 1405.28, date: '2026-01-10', raw_description: 'PAGAMENTO DE FATURA', normalized_merchant: 'PAGAMENTO DE FATURA' })
  const cardCredit2 = row({ account_id: 'acct-card', type: 'CREDIT', amount: 1520.79, date: '2026-02-10' })
  const bankDebit2 = row({ account_id: 'acct-checking', amount: 1520.79, date: '2026-02-10', raw_description: 'PAGAMENTO DE FATURA', normalized_merchant: 'PAGAMENTO DE FATURA' })
  const d = detect({ today: '2026-02-20', rows: [cardCredit, bankDebit, cardCredit2, bankDebit2], ...EMPTY })
  assertEquals(d.subscriptions.length, 0)
  assertEquals(d.diagnostics.excluded_credit, 2)
  assertEquals(d.diagnostics.excluded_internal_transfer, 2)
})

Deno.test('withdrawn rows are not candidates, so no charge is derived', () => {
  const rows = [
    row({ date: '2026-01-10', amount: 39.9 }),
    row({ date: '2026-02-09', amount: 39.9, withdrawn_at: '2026-02-10T00:00:00Z' }),
  ]
  const d = detect({ today: '2026-02-20', rows, ...EMPTY })
  assertEquals(d.diagnostics.excluded_withdrawn, 1)
  assertEquals(d.diagnostics.r1_runs, 0)
})

// ------------------------------------------------------------------------- R3

Deno.test('R3 fires on date-aligned varying amounts, and is suggest-only', () => {
  const rows = [
    row({ date: '2026-01-10', amount: 30 }),
    row({ date: '2026-02-10', amount: 41 }),
    row({ date: '2026-03-11', amount: 27 }),
  ]
  const d = detect({ today: '2026-03-20', rows, ...EMPTY })
  assertEquals(d.subscriptions[0].runs[0].detected_by, 'R3')
  assertEquals(d.subscriptions[0].runs[0].status, 'possible', 'never auto-promoted')
})

Deno.test('R3 rejects scattered days-of-month (the loose-reading false positive)', () => {
  const rows = [
    row({ date: '2026-01-03', amount: 10 }),
    row({ date: '2026-01-16', amount: 20 }),
    row({ date: '2026-02-28', amount: 30 }),
    row({ date: '2026-03-14', amount: 40 }),
  ]
  const d = detect({ today: '2026-03-20', rows, ...EMPTY })
  assertEquals(d.diagnostics.r3_runs, 0)
})

Deno.test('circular DOM distance: the 1st and the 30th are near, not 29 apart', () => {
  assertEquals(circularDomDistance(1, 30), 2)
  assertEquals(circularDomDistance(10, 12), 2)
})

// ---------------------------------------------------------------- determinism

Deno.test('determinism: identical inputs produce byte-identical state', () => {
  const rows = [
    row({ id: 'a', provider_tx_id: 'pa', date: '2026-01-10', amount: 39.9 }),
    row({ id: 'b', provider_tx_id: 'pb', date: '2026-02-09', amount: 39.9 }),
    row({ id: 'c', provider_tx_id: 'pc', date: '2026-02-09', amount: 12.0, normalized_merchant: 'OTHER' }),
  ]
  const one = JSON.stringify(detect({ today: '2026-02-20', rows, ...EMPTY }))
  const two = JSON.stringify(detect({ today: '2026-02-20', rows: [...rows].reverse(), ...EMPTY }))
  assertEquals(one, two, 'input order must not change output')
})

Deno.test('sequential charges at one merchant stay ONE run (amount-flexible)', () => {
  // 25, 25, 10, 10 at monthly cadence is a price drop, not two subscriptions.
  // Doctrine: "continuation is amount-flexible (price hikes never split a run)".
  const rows = [
    row({ provider_tx_id: 'a1', date: '2026-01-05', amount: 25 }),
    row({ provider_tx_id: 'a2', date: '2026-02-04', amount: 25 }),
    row({ provider_tx_id: 'z1', date: '2026-03-05', amount: 10 }),
    row({ provider_tx_id: 'z2', date: '2026-04-04', amount: 10 }),
  ]
  const d = detect({ today: '2026-04-20', rows, ...EMPTY })
  assertEquals(d.subscriptions.length, 1)
  assertEquals(d.subscriptions[0].runs[0].charges.length, 4)
})

Deno.test('dedupe_key ordinals follow first-charge date, not discovery order', () => {
  // Genuinely CONCURRENT runs on one merchant -- two charges land in each cycle,
  // which is the case dedupe_key forking exists for. The later-starting run must
  // never take the bare key, or a recompute could re-attach the wrong nickname.
  const rows = [
    row({ id: 'late1', provider_tx_id: 'z1', date: '2026-01-20', amount: 10 }),
    row({ id: 'late2', provider_tx_id: 'z2', date: '2026-02-19', amount: 10 }),
    row({ id: 'early1', provider_tx_id: 'a1', date: '2026-01-05', amount: 25 }),
    row({ id: 'early2', provider_tx_id: 'a2', date: '2026-02-04', amount: 25 }),
  ]
  const d = detect({ today: '2026-02-25', rows, ...EMPTY })
  assertEquals(d.subscriptions.length, 2)
  const bare = d.subscriptions.find((s) => !s.dedupe_key.includes(':'))!
  const forked = d.subscriptions.find((s) => s.dedupe_key.endsWith(':2'))!
  assertEquals(bare.runs[0].start_date, '2026-01-05', 'earliest run holds the bare key')
  assertEquals(forked.runs[0].start_date, '2026-01-20')
})

// ---------------------------------------------------------------- idempotency

Deno.test('idempotency: a second run over the same inputs changes nothing', () => {
  const rows = [
    row({ date: '2026-01-10', amount: 39.9 }),
    row({ date: '2026-02-09', amount: 39.9 }),
  ]
  const first = detect({ today: '2026-02-20', rows, ...EMPTY })
  // Feed the first result back as stored state, the way a real second run sees it.
  const storedSub = {
    id: 'sub-1',
    dedupe_key: first.subscriptions[0].dedupe_key,
    merchant_key: first.subscriptions[0].merchant_key,
    service_name: first.subscriptions[0].service_name,
    identification: 'auto',
    ignored: false,
  }
  const storedRun = {
    id: 'run-1',
    subscription_id: 'sub-1',
    ...first.subscriptions[0].runs[0],
    stored_run_id: undefined,
  } as unknown as Parameters<typeof detect>[0]['runs'][number]
  const storedCharges = first.subscriptions[0].runs[0].charges.map((c, i) => ({
    id: `ch-${i}`,
    run_id: 'run-1',
    transaction_id: c.transaction_id,
    date: c.date,
    amount: c.amount,
    currency: c.currency,
    amount_in_account_currency: c.amount_in_account_currency,
    card_label: null,
  }))

  const second = detect({
    today: '2026-02-20',
    rows,
    subscriptions: [storedSub],
    runs: [storedRun],
    charges: storedCharges,
  })
  assertEquals(second.subscriptions[0].runs[0].stored_run_id, 'run-1', 'run identity by overlap')
  assertEquals(second.delete_run_ids, [], 'nothing deleted on a no-op re-run')
  assertEquals(
    second.subscriptions[0].runs[0].charges.length,
    first.subscriptions[0].runs[0].charges.length,
  )
})

// ------------------------------------------------------------- frozen region

Deno.test('a run holding frozen charges is never deleted', () => {
  // No candidates at all, so nothing is derived; the stored run survives purely
  // because its charge has no raw backing (remove-bank-link history).
  const d = detect({
    today: '2026-02-20',
    rows: [],
    subscriptions: [{ id: 'sub-1', dedupe_key: 'k', merchant_key: 'k', service_name: 'X', identification: 'auto', ignored: false }],
    runs: [{ id: 'run-frozen', subscription_id: 'sub-1', start_date: '2025-01-01', end_date: null, billing_interval: 'monthly', status: 'active', detected_by: 'R1', cancelled_date: null, next_expected_date: null }],
    charges: [{ id: 'ch-frozen', run_id: 'run-frozen', transaction_id: null, date: '2025-01-01', amount: 10, currency: 'BRL', amount_in_account_currency: null, card_label: null }],
  })
  assertEquals(d.delete_run_ids, [], 'frozen charges ARE the run basis')
})

Deno.test('a stored run whose live charges all vanished is deleted', () => {
  const d = detect({
    today: '2026-02-20',
    rows: [],
    subscriptions: [{ id: 'sub-1', dedupe_key: 'k', merchant_key: 'k', service_name: 'X', identification: 'auto', ignored: false }],
    runs: [{ id: 'run-gone', subscription_id: 'sub-1', start_date: '2025-01-01', end_date: null, billing_interval: 'monthly', status: 'active', detected_by: 'R1', cancelled_date: null, next_expected_date: null }],
    charges: [{ id: 'ch-live', run_id: 'run-gone', transaction_id: 'tx-missing', date: '2025-01-01', amount: 10, currency: 'BRL', amount_in_account_currency: null, card_label: null }],
  })
  assertEquals(d.delete_run_ids, ['run-gone'])
})

// ------------------------------------------------------------------ assertions

Deno.test('a cancellation is preserved across recompute', () => {
  const rows = [
    row({ id: 'x1', provider_tx_id: 'x1', date: '2026-01-10', amount: 39.9 }),
    row({ id: 'x2', provider_tx_id: 'x2', date: '2026-02-09', amount: 39.9 }),
  ]
  const d = detect({
    today: '2026-02-20',
    rows,
    subscriptions: [{ id: 'sub-1', dedupe_key: 'ACME STREAMING', merchant_key: 'ACME STREAMING', service_name: 'Acme', identification: 'user_confirmed', ignored: false }],
    runs: [{ id: 'run-1', subscription_id: 'sub-1', start_date: '2026-01-10', end_date: '2026-03-09', billing_interval: 'monthly', status: 'cancelled', detected_by: 'R1', cancelled_date: '2026-02-15', next_expected_date: null }],
    charges: [
      { id: 'c1', run_id: 'run-1', transaction_id: 'x1', date: '2026-01-10', amount: 39.9, currency: 'BRL', amount_in_account_currency: null, card_label: null },
      { id: 'c2', run_id: 'run-1', transaction_id: 'x2', date: '2026-02-09', amount: 39.9, currency: 'BRL', amount_in_account_currency: null, card_label: null },
    ],
  })
  const run = d.subscriptions[0].runs[0]
  assertEquals(run.status, 'cancelled')
  assertEquals(run.cancelled_date, '2026-02-15')
  assertEquals(run.next_expected_date, null, 'cancelled runs never trip overdue')
})

Deno.test('a user-renamed service_name is frozen', () => {
  const rows = [
    row({ id: 'y1', provider_tx_id: 'y1', date: '2026-01-10', amount: 39.9 }),
    row({ id: 'y2', provider_tx_id: 'y2', date: '2026-02-09', amount: 39.9 }),
  ]
  const d = detect({
    today: '2026-02-20',
    rows,
    subscriptions: [{ id: 'sub-1', dedupe_key: 'ACME STREAMING', merchant_key: 'ACME STREAMING', service_name: 'Netflix (mum)', identification: 'user_renamed', ignored: false }],
    runs: [],
    charges: [],
  })
  assertEquals(d.subscriptions[0].service_name, 'Netflix (mum)')
})

// ------------------------------------------------------------------ lifecycle

Deno.test('lifecycle: active -> overdue -> ended at +10, end_date paid-through', () => {
  const rows = [
    row({ date: '2026-01-10', amount: 39.9 }),
    row({ date: '2026-02-09', amount: 39.9 }),
  ]
  const expected = addMonths('2026-02-09', 1) // 2026-03-09
  const active = detect({ today: '2026-03-01', rows, ...EMPTY })
  assertEquals(active.subscriptions[0].runs[0].status, 'active')

  const overdue = detect({ today: '2026-03-16', rows, ...EMPTY })
  assertEquals(overdue.subscriptions[0].runs[0].status, 'overdue')

  const ended = detect({ today: '2026-04-01', rows, ...EMPTY })
  assertEquals(ended.subscriptions[0].runs[0].status, 'ended')
  assertEquals(ended.subscriptions[0].runs[0].end_date, expected, 'paid-through, not last charge')
  assertEquals(daysBetween('2026-02-09', expected), 28)
})

Deno.test('addMonths clamps rather than overflowing the month', () => {
  assertEquals(addMonths('2026-01-31', 1), '2026-02-28')
  assertEquals(addMonths('2026-01-31', 12), '2027-01-31')
})

// ------------------------------------------------------------------- currency

Deno.test('v25: the same number in two currencies is not the same money', () => {
  assertFalse(sameMoney({ amount: 6.45, currency: 'USD' }, { amount: 6.45, currency: 'BRL' }))
  assert(sameMoney({ amount: 6.45, currency: 'usd' }, { amount: 6.45, currency: ' USD ' }), 'case/space tolerant')
  assert(moneyKey({ amount: 6.45, currency: 'USD' }) !== moneyKey({ amount: 6.45, currency: 'BRL' }))
})

Deno.test('v25: R1 does NOT anchor a cross-currency pair', () => {
  // Real exposure: Valve bills under one CNPJ in both BRL and USD.
  const rows = [
    row({ date: '2026-01-10', amount: 6.45, currency: 'USD', provider_merchant_cnpj: 'CNPJ-SYNTHETIC-1' }),
    row({ date: '2026-02-09', amount: 6.45, currency: 'BRL', provider_merchant_cnpj: 'CNPJ-SYNTHETIC-1' }),
  ]
  const d = detect({ today: '2026-02-20', rows, ...EMPTY })
  assertEquals(d.diagnostics.r1_runs, 0, 'same number, different money')
})

Deno.test('v25: R1 still anchors when both charges share a currency', () => {
  // The real Steam subscription: 6.45 USD every month. Must survive the guard.
  const rows = [
    row({ date: '2026-06-19', amount: 6.45, currency: 'USD', provider_merchant_cnpj: 'CNPJ-SYNTHETIC-1' }),
    row({ date: '2026-07-19', amount: 6.45, currency: 'USD', provider_merchant_cnpj: 'CNPJ-SYNTHETIC-1' }),
  ]
  const d = detect({ today: '2026-07-25', rows, ...EMPTY })
  assertEquals(d.diagnostics.r1_runs, 1)
  assertEquals(d.subscriptions[0].runs[0].charges.length, 2)
})

Deno.test('v25: internal-transfer filter does not fire across currencies', () => {
  // This direction HIDES a real transaction, so it is the dangerous one.
  const debit = row({ account_id: 'acct-checking', amount: 100, currency: 'BRL', date: '2026-01-10' })
  const credit = row({ account_id: 'acct-card', type: 'CREDIT', amount: 100, currency: 'USD', date: '2026-01-10' })
  assertFalse(isInternalTransfer(debit, [debit, credit]))

  const sameCur = row({ account_id: 'acct-card', type: 'CREDIT', amount: 100, currency: 'BRL', date: '2026-01-10' })
  assert(isInternalTransfer(debit, [debit, sameCur]), 'and still fires when it should')
})

Deno.test('v25: R3 counts cross-currency amounts as distinct', () => {
  // Three date-aligned charges whose NUMBERS repeat but whose money does not.
  const rows = [
    row({ date: '2026-01-10', amount: 10, currency: 'USD' }),
    row({ date: '2026-02-10', amount: 10, currency: 'BRL' }),
    row({ date: '2026-03-11', amount: 10, currency: 'USD' }),
  ]
  const d = detect({ today: '2026-03-20', rows, ...EMPTY })
  assertEquals(d.diagnostics.r3_runs, 1, 'varying money, so R3 has something to suggest')
})
