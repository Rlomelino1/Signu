
import { assert, assertEquals, assertFalse } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import { cents, moneyKey, sameMoney } from './money.ts'
import { addMonths, circularDomDistance, daysBetween } from './dates.ts'
import {
  catalogEntryFor,
  type CatalogRow,
  detect,
  filterCandidates,
  isFee,
  isInstallment,
  isInternalTransfer,
  merchantKey,
  normaliseBrand,
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


Deno.test('v23 regression: amounts a cent apart are NOT the same amount', () => {
  assertFalse(sameMoney({ amount: 6.46, currency: 'BRL' }, { amount: 6.45, currency: 'BRL' }))
  assert(Math.abs(6.46 - 6.45) < 0.01, 'the float epsilon that caused the bug still misfires')
  assertEquals(cents(6.45), 645)
  assertEquals(cents(-6.45), 645, 'magnitude, so card and bank sign dialects compare')
})


Deno.test('fee exclusion is by VALUE, never presence', () => {
  assertFalse(isFee(row({ fee_type_additional_info: null })))
  assertFalse(isFee(row({ fee_type_additional_info: 'NA' })), "'NA' means no fee")
  assertFalse(isFee(row({ fee_type_additional_info: '' })))
  assert(isFee(row({ fee_type_additional_info: 'IOF_COMPRA_INTERNACIONAL' })))
})

Deno.test('presence-based fee filtering would eat the ledger (the v21 bug)', () => {
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

Deno.test('v88 regression: R1 continuation takes the NEAREST charge, not the first', () => {
  const rows = [
    row({ date: '2026-06-19', amount: 6.45, currency: 'USD', amount_in_account_currency: 34.51 }),
    row({ date: '2026-07-19', amount: 6.45, currency: 'USD', amount_in_account_currency: 34.33 }),
    row({ date: '2026-08-16', amount: 4.48, currency: 'USD', amount_in_account_currency: 24.34 }),
    row({ date: '2026-08-18', amount: 6.34, currency: 'USD', amount_in_account_currency: 35.52 }),
  ]
  const d = detect({ today: '2026-08-21', rows, ...EMPTY })
  const run = d.subscriptions[0].runs[0]
  assertEquals(run.detected_by, 'R1')
  assertEquals(run.charges.length, 3)
  assertEquals(
    run.charges[2].date,
    '2026-08-18',
    'the renewal is 1 day from expected; the stranger is 3 — nearest wins, not first-in-date-order',
  )
  assertEquals(run.next_expected_date, '2026-09-18', 'and the next date follows the right charge')
})

Deno.test('v88: an amount that matches the run beats a nearer stranger', () => {
  const rows = [
    row({ date: '2026-01-10', amount: 39.9 }),
    row({ date: '2026-02-09', amount: 39.9 }),
    row({ date: '2026-03-10', amount: 12.0 }),
    row({ date: '2026-03-12', amount: 39.9 }),
  ]
  const d = detect({ today: '2026-03-20', rows, ...EMPTY })
  const run = d.subscriptions[0].runs[0]
  assertEquals(
    run.charges[2].date,
    '2026-03-12',
    "the run's own price outranks date proximity when both sit in the window",
  )
})

Deno.test('installment rows never reach R1 (Padrao B false positive)', () => {
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


Deno.test('idempotency: a second run over the same inputs changes nothing', () => {
  const rows = [
    row({ date: '2026-01-10', amount: 39.9 }),
    row({ date: '2026-02-09', amount: 39.9 }),
  ]
  const first = detect({ today: '2026-02-20', rows, ...EMPTY })
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


Deno.test('a run holding frozen charges is never deleted', () => {
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


Deno.test('lifecycle: the grace runs from expected + MATCH_WINDOW, so dead is +13', () => {
  const rows = [
    row({ date: '2026-01-10', amount: 39.9 }),
    row({ date: '2026-02-09', amount: 39.9 }),
  ]
  const expected = addMonths('2026-02-09', 1)
  assertEquals(expected, '2026-03-09')
  assertEquals(daysBetween('2026-02-09', expected), 28)

  const statusOn = (today: string) =>
    detect({ today, rows, ...EMPTY }).subscriptions[0].runs[0].status

  assertEquals(statusOn('2026-03-01'), 'active', 'before the expected date')
  assertEquals(statusOn('2026-03-12'), 'active', 'expected +3 is still inside the match window')
  assertEquals(statusOn('2026-03-13'), 'overdue', 'expected +4 is the first overdue day')
  assertEquals(statusOn('2026-03-22'), 'overdue', 'expected +13 is the LAST overdue day')
  assertEquals(statusOn('2026-03-23'), 'ended', 'expected +14 is the first dead day')

  const ended = detect({ today: '2026-03-23', rows, ...EMPTY }).subscriptions[0].runs[0]
  assertEquals(ended.end_date, expected, 'paid-through, not last charge')

  const previous = detect({ today: '2026-04-01', rows, ...EMPTY }).subscriptions[0].runs[0]
  assertEquals(previous.status, 'ended', 'and it stays ended')
})

Deno.test('addMonths clamps rather than overflowing the month', () => {
  assertEquals(addMonths('2026-01-31', 1), '2026-02-28')
  assertEquals(addMonths('2026-01-31', 12), '2027-01-31')
})


Deno.test('v25: the same number in two currencies is not the same money', () => {
  assertFalse(sameMoney({ amount: 6.45, currency: 'USD' }, { amount: 6.45, currency: 'BRL' }))
  assert(sameMoney({ amount: 6.45, currency: 'usd' }, { amount: 6.45, currency: ' USD ' }), 'case/space tolerant')
  assert(moneyKey({ amount: 6.45, currency: 'USD' }) !== moneyKey({ amount: 6.45, currency: 'BRL' }))
})

Deno.test('v25: R1 does NOT anchor a cross-currency pair', () => {
  const rows = [
    row({ date: '2026-01-10', amount: 6.45, currency: 'USD', provider_merchant_cnpj: 'CNPJ-SYNTHETIC-1' }),
    row({ date: '2026-02-09', amount: 6.45, currency: 'BRL', provider_merchant_cnpj: 'CNPJ-SYNTHETIC-1' }),
  ]
  const d = detect({ today: '2026-02-20', rows, ...EMPTY })
  assertEquals(d.diagnostics.r1_runs, 0, 'same number, different money')
})

Deno.test('v25: R1 still anchors when both charges share a currency', () => {
  const rows = [
    row({ date: '2026-06-19', amount: 6.45, currency: 'USD', provider_merchant_cnpj: 'CNPJ-SYNTHETIC-1' }),
    row({ date: '2026-07-19', amount: 6.45, currency: 'USD', provider_merchant_cnpj: 'CNPJ-SYNTHETIC-1' }),
  ]
  const d = detect({ today: '2026-07-25', rows, ...EMPTY })
  assertEquals(d.diagnostics.r1_runs, 1)
  assertEquals(d.subscriptions[0].runs[0].charges.length, 2)
})

Deno.test('v25: internal-transfer filter does not fire across currencies', () => {
  const debit = row({ account_id: 'acct-checking', amount: 100, currency: 'BRL', date: '2026-01-10' })
  const credit = row({ account_id: 'acct-card', type: 'CREDIT', amount: 100, currency: 'USD', date: '2026-01-10' })
  assertFalse(isInternalTransfer(debit, [debit, credit]))

  const sameCur = row({ account_id: 'acct-card', type: 'CREDIT', amount: 100, currency: 'BRL', date: '2026-01-10' })
  assert(isInternalTransfer(debit, [debit, sameCur]), 'and still fires when it should')
})

Deno.test('v25: R3 counts cross-currency amounts as distinct', () => {
  const rows = [
    row({ date: '2026-01-10', amount: 10, currency: 'USD' }),
    row({ date: '2026-02-10', amount: 10, currency: 'BRL' }),
    row({ date: '2026-03-11', amount: 10, currency: 'USD' }),
  ]
  const d = detect({ today: '2026-03-20', rows, ...EMPTY })
  assertEquals(d.diagnostics.r3_runs, 1, 'varying money, so R3 has something to suggest')
})


Deno.test('v60: a charge carries the card it was billed to', () => {
  const rows = [
    row({ date: '2026-01-10', amount: 39.9 }),
    row({ date: '2026-02-10', amount: 39.9 }),
  ]
  const d = detect({
    today: '2026-02-20',
    rows,
    ...EMPTY,
    accounts: [{ id: 'acct-card', brand: 'MASTERCARD', last4: '2049' }],
  })
  const charges = d.subscriptions[0].runs[0].charges
  assertEquals(charges.length, 2)
  assertEquals(charges.every((c) => c.card_label === 'Master 2049'), true)
})

Deno.test('v60: an account the engine was not told about yields null, not a guess', () => {
  const rows = [
    row({ date: '2026-01-10', amount: 39.9 }),
    row({ date: '2026-02-10', amount: 39.9 }),
  ]
  const withoutAccounts = detect({ today: '2026-02-20', rows, ...EMPTY })
  assertEquals(withoutAccounts.subscriptions[0].runs[0].charges[0].card_label, null)

  const otherAccount = detect({
    today: '2026-02-20',
    rows,
    ...EMPTY,
    accounts: [{ id: 'acct-somewhere-else', brand: 'VISA', last4: '4821' }],
  })
  assertEquals(otherAccount.subscriptions[0].runs[0].charges[0].card_label, null)
})

Deno.test('v60: a charge on a checking account is not given an invented card', () => {
  const rows = [
    row({ account_id: 'acct-checking', date: '2026-01-10', amount: 39.9 }),
    row({ account_id: 'acct-checking', date: '2026-02-10', amount: 39.9 }),
  ]
  const d = detect({
    today: '2026-02-20',
    rows,
    ...EMPTY,
    accounts: [{ id: 'acct-checking', brand: null, last4: '3816' }],
  })
  assertEquals(d.subscriptions[0].runs[0].charges[0].card_label, null)
})


function catalogRow(over: Partial<CatalogRow> = {}): CatalogRow {
  return {
    brand_name: 'Netflix',
    patterns: ['netflix'],
    subscription_only: true,
    kind: 'service',
    ...over,
  }
}

const CATALOG: CatalogRow[] = [
  catalogRow(),
  catalogRow({ brand_name: 'Amazon Prime', patterns: ['amazon prime'] }),
  catalogRow({ brand_name: 'Kindle Unlimited', patterns: ['amazon', 'kindle unlimited'] }),
  catalogRow({ brand_name: 'Estadão', patterns: ['estadao'] }),
  catalogRow({
    brand_name: 'Steam',
    patterns: ['steam', 'valve', 'trueline valve'],
    subscription_only: false,
  }),
  catalogRow({
    brand_name: 'Nubank',
    patterns: ['nubank', 'nu pagamentos'],
    subscription_only: false,
    kind: 'institution',
  }),
]

Deno.test('R4 matching mirrors the client: name first, then longest pattern', () => {
  assertEquals(catalogEntryFor('Netflix', CATALOG)?.brand_name, 'Netflix')
  assertEquals(catalogEntryFor('NETFLIX.COM BRASIL', CATALOG)?.brand_name, 'Netflix')
  assertEquals(catalogEntryFor('AMAZON PRIME BR', CATALOG)?.brand_name, 'Amazon Prime')
  assertEquals(catalogEntryFor('AMAZON SERVICES', CATALOG)?.brand_name, 'Kindle Unlimited')
  assertEquals(catalogEntryFor('Padaria do Zé', CATALOG), null)
  assertEquals(catalogEntryFor('', CATALOG), null)
  assertEquals(catalogEntryFor(null, CATALOG), null)
})

Deno.test('R4 matching folds case and accents like the client does', () => {
  assertEquals(normaliseBrand('ESTADÃO'), 'estadao')
  assertEquals(normaliseBrand('  Netflix '), 'netflix')
  assertEquals(catalogEntryFor('estadao', CATALOG)?.brand_name, 'Estadão')
  assertEquals(catalogEntryFor('ESTADÃO ASSINATURA', CATALOG)?.brand_name, 'Estadão')
})

Deno.test('R4 never reads an institution row', () => {
  assertEquals(catalogEntryFor('NU PAGAMENTOS 12345 SOMESHOP', CATALOG), null)
  assertEquals(catalogEntryFor('Nubank', CATALOG), null)
  assertEquals(catalogEntryFor('Nubank', CATALOG, 'institution')?.brand_name, 'Nubank')
})

Deno.test('R4: one charge from a subscription-only merchant is a possible run', () => {
  const out = detect({
    today: '2026-01-20',
    rows: [row({ date: '2026-01-10', raw_description: 'NETFLIX.COM', normalized_merchant: 'NETFLIX.COM' })],
    ...EMPTY,
    catalog: CATALOG,
  })
  assertEquals(out.subscriptions.length, 1)
  const run = out.subscriptions[0].runs[0]
  assertEquals(run.detected_by, 'R4')
  assertEquals(run.status, 'possible')
  assertEquals(run.charges.length, 1)
  assertEquals(run.billing_interval, 'monthly')
  assertEquals(run.next_expected_date, '2026-02-10')
  assertEquals(out.diagnostics.r4_runs, 1)
})

Deno.test('R4 does not fire without a catalog, which was every version before v63', () => {
  const rows = [row({ raw_description: 'NETFLIX.COM', normalized_merchant: 'NETFLIX.COM' })]
  assertEquals(detect({ today: '2026-01-20', rows, ...EMPTY }).subscriptions.length, 0)
  assertEquals(detect({ today: '2026-01-20', rows, ...EMPTY, catalog: [] }).subscriptions.length, 0)
})

Deno.test('R4 refuses a merchant whose charges are not always subscriptions', () => {
  const out = detect({
    today: '2026-01-20',
    rows: [row({ raw_description: 'TRUELINE VALVE CORPORATION', normalized_merchant: 'TRUELINE VALVE CORPORATION' })],
    ...EMPTY,
    catalog: CATALOG,
  })
  assertEquals(out.subscriptions.length, 0)
  assertEquals(out.diagnostics.r4_runs, 0)
})

Deno.test('a measured cadence beats the catalog: two Netflix charges are R1, not R4', () => {
  const out = detect({
    today: '2026-02-20',
    rows: [
      row({ date: '2026-01-10', raw_description: 'NETFLIX.COM', normalized_merchant: 'NETFLIX.COM' }),
      row({ date: '2026-02-09', raw_description: 'NETFLIX.COM', normalized_merchant: 'NETFLIX.COM' }),
    ],
    ...EMPTY,
    catalog: CATALOG,
  })
  const run = out.subscriptions[0].runs[0]
  assertEquals(run.detected_by, 'R1')
  assertEquals(run.status, 'active')
  assertEquals(out.diagnostics.r4_runs, 0)
})

Deno.test('R4 claims every leftover charge of the merchant, not just the first', () => {
  const out = detect({
    today: '2026-03-01',
    rows: [
      row({ date: '2026-01-10', raw_description: 'NETFLIX.COM', normalized_merchant: 'NETFLIX.COM' }),
      row({ date: '2026-02-19', raw_description: 'NETFLIX.COM', normalized_merchant: 'NETFLIX.COM' }),
    ],
    ...EMPTY,
    catalog: CATALOG,
  })
  const run = out.subscriptions[0].runs[0]
  assertEquals(run.detected_by, 'R4')
  assertEquals(run.charges.length, 2)
  assertEquals(run.start_date, '2026-01-10')
})

Deno.test('R4 is recognised through the merchant NAME when the descriptor is opaque', () => {
  const out = detect({
    today: '2026-01-20',
    rows: [row({
      raw_description: 'PAG*8829911',
      normalized_merchant: 'PAG*8829911',
      provider_merchant_name: 'Netflix',
    })],
    ...EMPTY,
    catalog: CATALOG,
  })
  assertEquals(out.subscriptions[0].runs[0].detected_by, 'R4')
})

Deno.test('the strongest name decides: a non-subscription merchant is not overruled', () => {
  const out = detect({
    today: '2026-01-20',
    rows: [row({
      provider_merchant_name: 'Steam',
      raw_description: 'NETFLIX.COM',
      normalized_merchant: 'NETFLIX.COM',
    })],
    ...EMPTY,
    catalog: CATALOG,
  })
  assertEquals(out.subscriptions.length, 0)
})

Deno.test('R4 obeys the candidate filter like every other rule', () => {
  const out = detect({
    today: '2026-01-20',
    rows: [row({
      raw_description: 'NETFLIX.COM 03/12',
      normalized_merchant: 'NETFLIX.COM',
      total_installments: 12,
    })],
    ...EMPTY,
    catalog: CATALOG,
  })
  assertEquals(out.subscriptions.length, 0)
})

Deno.test('a confirmed R4 keeps the interval the user stated', () => {
  const out = detect({
    today: '2026-01-20',
    rows: [row({ id: 'tx-r4a', date: '2026-01-10', raw_description: 'NETFLIX.COM', normalized_merchant: 'NETFLIX.COM' })],
    subscriptions: [{
      id: 'sub-1',
      dedupe_key: 'netflix.com',
      merchant_key: 'NETFLIX.COM',
      service_name: 'Netflix',
      identification: 'user_confirmed',
      ignored: false,
    }],
    runs: [{
      id: 'run-1',
      subscription_id: 'sub-1',
      start_date: '2026-01-10',
      end_date: null,
      billing_interval: 'annual',
      status: 'active',
      detected_by: 'R4',
      cancelled_date: null,
      next_expected_date: '2027-01-10',
    }],
    charges: [{
      id: 'ch-1',
      run_id: 'run-1',
      transaction_id: 'tx-r4a',
      date: '2026-01-10',
      amount: 39.9,
      currency: 'BRL',
      amount_in_account_currency: null,
      card_label: null,
    }],
    catalog: CATALOG,
  })
  const run = out.subscriptions[0].runs[0]
  assertEquals(run.stored_run_id, 'run-1')
  assertEquals(run.billing_interval, 'annual', 'the user\'s answer is authoritative')
  assertEquals(run.status, 'active')
})

Deno.test('THE SPEC-FLAGGED CASE: a confirmed R4 that never repeats dies quietly', () => {
  const storedFor = (today: string) => ({
    today,
    rows: [row({ id: 'tx-r4b', date: '2026-01-10', raw_description: 'NETFLIX.COM', normalized_merchant: 'NETFLIX.COM' })],
    subscriptions: [{
      id: 'sub-1',
      dedupe_key: 'netflix.com',
      merchant_key: 'NETFLIX.COM',
      service_name: 'Netflix',
      identification: 'user_confirmed',
      ignored: false,
    }],
    runs: [{
      id: 'run-1',
      subscription_id: 'sub-1',
      start_date: '2026-01-10',
      end_date: null,
      billing_interval: 'monthly' as const,
      status: 'active',
      detected_by: 'R4',
      cancelled_date: null,
      next_expected_date: '2026-02-10',
    }],
    charges: [{
      id: 'ch-1',
      run_id: 'run-1',
      transaction_id: 'tx-r4b',
      date: '2026-01-10',
      amount: 39.9,
      currency: 'BRL',
      amount_in_account_currency: null,
      card_label: null,
    }],
    catalog: CATALOG,
  })

  assertEquals(detect(storedFor('2026-02-12')).subscriptions[0].runs[0].status, 'active')
  const overdue = detect(storedFor('2026-02-20')).subscriptions[0].runs[0]
  assertEquals(overdue.status, 'overdue')
  assertEquals(overdue.next_expected_date, '2026-02-10')
  const ended = detect(storedFor('2026-04-01')).subscriptions[0].runs[0]
  assertEquals(ended.status, 'ended')
  assertEquals(ended.end_date, '2026-02-10')
  assertEquals(ended.next_expected_date, null)
  assertEquals(ended.detected_by, 'R4')
})


const GAMING: CatalogRow[] = [
  catalogRow({ brand_name: 'PlayStation', patterns: ['playstation', 'psn', 'sony playstation'], subscription_only: false }),
  catalogRow({ brand_name: 'PlayStation Plus', patterns: ['playstation plus', 'ps plus', 'psn plus'], subscription_only: true }),
  catalogRow({ brand_name: 'Xbox', patterns: ['xbox', 'microsoft xbox'], subscription_only: false }),
  catalogRow({ brand_name: 'Xbox Game Pass', patterns: ['xbox game pass', 'game pass'], subscription_only: true }),
]

Deno.test('a storefront descriptor resolves to the storefront, not the subscription', () => {
  assertEquals(catalogEntryFor('PLAYSTATION NETWORK', GAMING)?.brand_name, 'PlayStation')
  assertEquals(catalogEntryFor('PSN 4829112', GAMING)?.brand_name, 'PlayStation')
  assertEquals(catalogEntryFor('XBOX 8829911', GAMING)?.brand_name, 'Xbox')
  assertFalse(catalogEntryFor('XBOX 8829911', GAMING)!.subscription_only)
})

Deno.test('a descriptor that NAMES the subscription beats the storefront', () => {
  assertEquals(catalogEntryFor('PLAYSTATION PLUS RENEWAL', GAMING)?.brand_name, 'PlayStation Plus')
  assertEquals(catalogEntryFor('XBOX GAME PASS ULTIMATE', GAMING)?.brand_name, 'Xbox Game Pass')
  assert(catalogEntryFor('XBOX GAME PASS ULTIMATE', GAMING)!.subscription_only)
})

Deno.test('R4 declines a game purchase and accepts the subscription', () => {
  const one = (desc: string) =>
    detect({
      today: '2026-01-20',
      rows: [row({ date: '2026-01-10', raw_description: desc, normalized_merchant: desc })],
      ...EMPTY,
      catalog: GAMING,
    })

  assertEquals(one('PLAYSTATION NETWORK').subscriptions.length, 0)
  assertEquals(one('XBOX 8829911').subscriptions.length, 0)

  const plus = one('PLAYSTATION PLUS RENEWAL')
  assertEquals(plus.subscriptions.length, 1)
  assertEquals(plus.subscriptions[0].runs[0].detected_by, 'R4')
  assertEquals(plus.subscriptions[0].runs[0].status, 'possible')
})

Deno.test('both rows carry the same domain, so no charge loses its logo', () => {
  const store = catalogEntryFor('PSN 4829112', GAMING)
  const sub = catalogEntryFor('PS PLUS', GAMING)
  assertEquals(store?.brand_name, 'PlayStation')
  assertEquals(sub?.brand_name, 'PlayStation Plus')
})


function claudeCase(today: string, stored?: { status: string }) {
  const tx = row({
    id: 'tx-claude',
    date: '2026-03-05',
    amount: 20.97,
    currency: 'USD',
    raw_description: 'Claude.Ai Subscription',
    normalized_merchant: 'Claude.Ai Subscription',
  })
  const catalog = [catalogRow({ brand_name: 'Claude', patterns: ['claude.ai', 'claude'] })]
  if (!stored) return { today, rows: [tx], ...EMPTY, catalog }
  return {
    today,
    rows: [tx],
    subscriptions: [{
      id: 'sub-c',
      dedupe_key: 'claude.ai subscription',
      merchant_key: 'CLAUDE.AI SUBSCRIPTION',
      service_name: 'Claude.Ai Subscription',
      identification: 'auto',
      ignored: false,
    }],
    runs: [{
      id: 'run-c',
      subscription_id: 'sub-c',
      start_date: '2026-03-05',
      end_date: null,
      billing_interval: 'monthly' as const,
      status: stored.status,
      detected_by: 'R4',
      cancelled_date: null,
      next_expected_date: '2026-04-05',
    }],
    charges: [{
      id: 'ch-c',
      run_id: 'run-c',
      transaction_id: 'tx-claude',
      date: '2026-03-05',
      amount: 20.97,
      currency: 'USD',
      amount_in_account_currency: null,
      card_label: null,
    }],
    catalog,
  }
}

Deno.test('PRODUCTION CASE: R4 does not suggest a subscription that is already over', () => {
  const out = detect(claudeCase('2026-08-17'))
  assertEquals(out.subscriptions.length, 0)
  assertEquals(out.diagnostics.r4_runs, 0)
})

Deno.test('R4 still fires while the run could plausibly be alive', () => {
  const out = detect(claudeCase('2026-04-06'))
  assertEquals(out.subscriptions.length, 1)
  assertEquals(out.subscriptions[0].runs[0].detected_by, 'R4')
  assertEquals(out.subscriptions[0].runs[0].status, 'possible')
  assertEquals(out.subscriptions[0].runs[0].next_expected_date, '2026-04-05')
})

Deno.test('a stale suggestion nobody acted on cleans itself up', () => {
  const out = detect(claudeCase('2026-08-17', { status: 'possible' }))
  assertEquals(out.subscriptions.length, 0)
  assertEquals(out.delete_run_ids, ['run-c'])
})

Deno.test('but a CONFIRMED R4 is continued, never deleted by the freshness gate', () => {
  const out = detect(claudeCase('2026-08-17', { status: 'active' }))
  assertEquals(out.delete_run_ids, [], 'a confirmed run is never deleted for being old')
  const run = out.subscriptions[0].runs[0]
  assertEquals(run.stored_run_id, 'run-c')
  assertEquals(run.detected_by, 'R4')
  assertEquals(run.status, 'ended')
  assertEquals(run.end_date, '2026-04-05')
})

Deno.test('a cancelled R4 is likewise continued', () => {
  const out = detect(claudeCase('2026-08-17', { status: 'cancelled' }))
  assertEquals(out.delete_run_ids, [])
  assertEquals(out.subscriptions[0].runs[0].status, 'cancelled')
})


function cancelledCase(opts: {
  today: string
  after?: TxRow[]
  claimed?: string[]
  endDate?: string
}) {
  const x1 = row({ id: 'x1', provider_tx_id: 'x1', date: '2026-01-10', amount: 39.9 })
  const x2 = row({ id: 'x2', provider_tx_id: 'x2', date: '2026-02-09', amount: 39.9 })
  const after = opts.after ?? []
  const claimed = opts.claimed ?? []
  const held = [x1, x2, ...after.filter((r) => claimed.includes(r.id))]
  return {
    today: opts.today,
    rows: [x1, x2, ...after],
    subscriptions: [{
      id: 'sub-1',
      dedupe_key: 'ACME STREAMING',
      merchant_key: 'ACME STREAMING',
      service_name: 'Acme',
      identification: 'user_confirmed',
      ignored: false,
    }],
    runs: [{
      id: 'run-1',
      subscription_id: 'sub-1',
      start_date: '2026-01-10',
      end_date: opts.endDate ?? '2026-03-09',
      billing_interval: 'monthly' as const,
      status: 'cancelled',
      detected_by: 'R1',
      cancelled_date: '2026-02-15',
      next_expected_date: null,
    }],
    charges: held.map((r, i) => ({
      id: `c${i + 1}`,
      run_id: 'run-1',
      transaction_id: r.id,
      date: r.date,
      amount: r.amount,
      currency: r.currency,
      amount_in_account_currency: null,
      card_label: null,
    })),
  }
}

Deno.test('R5: a cancelled run claims ONE trailing charge and extends paid-through', () => {
  const x3 = row({ id: 'x3', provider_tx_id: 'x3', date: '2026-03-11', amount: 39.9 })
  const out = detect(cancelledCase({ today: '2026-03-20', after: [x3] }))

  assertEquals(out.subscriptions.length, 1, 'a trailing charge is not a new subscription')
  const run = out.subscriptions[0].runs[0]
  assertEquals(run.stored_run_id, 'run-1')
  assertEquals(run.status, 'cancelled', 'a trailing charge never revives a cancelled run')
  assertEquals(run.cancelled_date, '2026-02-15')
  assertEquals(run.charges.map((c) => c.transaction_id), ['x1', 'x2', 'x3'])
  assertEquals(run.end_date, '2026-04-11', 'paid-through = trailing charge + one interval')
  assertEquals(run.next_expected_date, null, 'cancelled runs stay out of Coming up')
  assertEquals(out.delete_run_ids, [])
})

Deno.test('R5: the trailing charge is amount-flexible, like any continuation', () => {
  const x3 = row({ id: 'x3', provider_tx_id: 'x3', date: '2026-03-11', amount: 44.9 })
  const out = detect(cancelledCase({ today: '2026-03-20', after: [x3] }))

  const run = out.subscriptions[0].runs[0]
  assertEquals(run.charges.map((c) => c.transaction_id), ['x1', 'x2', 'x3'])
  assertEquals(run.end_date, '2026-04-11', 'a price change does not change paid-through')
})

Deno.test('R5: replay does not ratchet paid-through forward', () => {
  const x3 = row({ id: 'x3', provider_tx_id: 'x3', date: '2026-03-11', amount: 39.9 })
  const out = detect(
    cancelledCase({ today: '2026-03-25', after: [x3], claimed: ['x3'], endDate: '2026-04-11' }),
  )

  const run = out.subscriptions[0].runs[0]
  assertEquals(run.end_date, '2026-04-11')
  assertEquals(run.charges.length, 3)
})

Deno.test('R5: the cap is ONE — a cancelled run does not keep swallowing charges', () => {
  const x3 = row({ id: 'x3', provider_tx_id: 'x3', date: '2026-03-11', amount: 39.9 })
  const x4 = row({ id: 'x4', provider_tx_id: 'x4', date: '2026-04-10', amount: 44.9 })
  const out = detect(
    cancelledCase({ today: '2026-04-20', after: [x3, x4], claimed: ['x3'], endDate: '2026-04-11' }),
  )

  assertEquals(out.subscriptions.length, 1)
  assertEquals(out.subscriptions[0].runs.length, 1, 'one unanchorable charge is not a run')
  const run = out.subscriptions[0].runs[0]
  assertEquals(run.charges.map((c) => c.transaction_id), ['x1', 'x2', 'x3'])
  assertEquals(run.end_date, '2026-04-11', 'paid-through follows the trailing charge, not x4')
})

Deno.test('R5: a SECOND matching charge un-claims the trailing one and anchors a new run', () => {
  const x3 = row({ id: 'x3', provider_tx_id: 'x3', date: '2026-03-11', amount: 39.9 })
  const x4 = row({ id: 'x4', provider_tx_id: 'x4', date: '2026-04-10', amount: 39.9 })
  const out = detect(
    cancelledCase({ today: '2026-04-20', after: [x3, x4], claimed: ['x3'], endDate: '2026-04-11' }),
  )

  assertEquals(out.subscriptions.map((s) => s.dedupe_key), ['ACME STREAMING', 'ACME STREAMING:2'])

  const cancelled = out.subscriptions[0].runs[0]
  assertEquals(cancelled.stored_run_id, 'run-1', 'highest overlap keeps the identity')
  assertEquals(cancelled.status, 'cancelled')
  assertEquals(cancelled.cancelled_date, '2026-02-15')
  assertEquals(cancelled.charges.map((c) => c.transaction_id), ['x1', 'x2'], 'the trailing charge left')
  assertEquals(
    cancelled.end_date,
    '2026-03-09',
    'the original paid-through is restored by derivation, not by remembering it',
  )

  const fresh = out.subscriptions[1].runs[0]
  assertEquals(fresh.stored_run_id, null, 'a resubscription is a new run, not a resurrection')
  assertEquals(fresh.detected_by, 'R1')
  assertEquals(fresh.status, 'active')
  assertEquals(fresh.charges.map((c) => c.transaction_id), ['x3', 'x4'])
  assertEquals(fresh.start_date, '2026-03-11')
  assertEquals(fresh.next_expected_date, '2026-05-10')
  assertEquals(out.delete_run_ids, [], 'nothing is deleted here; a charge moved')
})

Deno.test('R5: the un-claim converges whether the pair arrives together or apart', () => {
  const pair = () => [
    row({ id: 'x3', provider_tx_id: 'x3', date: '2026-03-11', amount: 39.9 }),
    row({ id: 'x4', provider_tx_id: 'x4', date: '2026-04-10', amount: 39.9 }),
  ]
  const incremental = detect(
    cancelledCase({ today: '2026-04-20', after: pair(), claimed: ['x3'], endDate: '2026-04-11' }),
  )
  const replay = detect(cancelledCase({ today: '2026-04-20', after: pair() }))

  assertEquals(JSON.stringify(replay.subscriptions), JSON.stringify(incremental.subscriptions))
})

Deno.test('R5: beyond one cadence, a post-cancel charge just waits for R1', () => {
  const x3 = row({ id: 'x3', provider_tx_id: 'x3', date: '2026-06-15', amount: 39.9 })
  const out = detect(cancelledCase({ today: '2026-06-20', after: [x3] }))

  assertEquals(out.subscriptions.length, 1)
  const run = out.subscriptions[0].runs[0]
  assertEquals(run.charges.map((c) => c.transaction_id), ['x1', 'x2'], 'not a trailing charge')
  assertEquals(run.end_date, '2026-03-09', 'paid-through untouched')
})

Deno.test('R5 is cancelled-only: an uncancelled run still continues without limit', () => {
  const out = detect({
    today: '2026-04-20',
    rows: [
      row({ id: 'a1', provider_tx_id: 'a1', date: '2026-01-10', amount: 39.9 }),
      row({ id: 'a2', provider_tx_id: 'a2', date: '2026-02-09', amount: 39.9 }),
      row({ id: 'a3', provider_tx_id: 'a3', date: '2026-03-11', amount: 39.9 }),
      row({ id: 'a4', provider_tx_id: 'a4', date: '2026-04-10', amount: 39.9 }),
    ],
    subscriptions: [{
      id: 'sub-a',
      dedupe_key: 'ACME STREAMING',
      merchant_key: 'ACME STREAMING',
      service_name: 'Acme',
      identification: 'auto',
      ignored: false,
    }],
    runs: [{
      id: 'run-a',
      subscription_id: 'sub-a',
      start_date: '2026-01-10',
      end_date: null,
      billing_interval: 'monthly',
      status: 'active',
      detected_by: 'R1',
      cancelled_date: null,
      next_expected_date: '2026-03-09',
    }],
    charges: [
      { id: 'ca1', run_id: 'run-a', transaction_id: 'a1', date: '2026-01-10', amount: 39.9, currency: 'BRL', amount_in_account_currency: null, card_label: null },
      { id: 'ca2', run_id: 'run-a', transaction_id: 'a2', date: '2026-02-09', amount: 39.9, currency: 'BRL', amount_in_account_currency: null, card_label: null },
    ],
  })

  assertEquals(out.subscriptions.length, 1)
  assertEquals(out.subscriptions[0].runs.length, 1)
  assertEquals(out.subscriptions[0].runs[0].charges.length, 4)
  assertEquals(out.subscriptions[0].runs[0].status, 'active')
})
