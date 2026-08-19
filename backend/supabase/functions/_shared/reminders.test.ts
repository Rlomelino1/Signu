import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import {
  chargeMoney,
  dueReminders,
  moneyText,
  type ReminderRow,
  wantsEmail,
  whenText,
} from './reminders.ts'

const TODAY = '2026-08-11'

function row(over: Partial<ReminderRow> = {}): ReminderRow {
  return {
    run_id: 'run-1',
    subscription_id: 'sub-1',
    service_name: 'Netflix',
    nickname: null,
    remind_before_days: 2,
    ignored: false,
    status: 'active',
    next_expected_date: '2026-08-13',
    last_reminded_for_date: null,
    billing_interval: 'monthly',
    amount: 44.9,
    currency: 'BRL',
    ...over,
  }
}

Deno.test('a renewal inside the lead time is due', () => {
  assertEquals(dueReminders([row()], TODAY).length, 1)
})

Deno.test('a renewal beyond the lead time is not', () => {
  assertEquals(dueReminders([row({ next_expected_date: '2026-08-16' })], TODAY).length, 0)
})

Deno.test('null remind_before_days means reminders are off', () => {
  assertEquals(dueReminders([row({ remind_before_days: null })], TODAY).length, 0)
})

Deno.test('remind_before_days of 0 still fires on the day', () => {
  assertEquals(dueReminders([row({ remind_before_days: 0, next_expected_date: TODAY })], TODAY).length, 1)
  assertEquals(dueReminders([row({ remind_before_days: 0, next_expected_date: '2026-08-12' })], TODAY).length, 0)
})

Deno.test('a dismissed subscription is never reminded about', () => {
  assertEquals(dueReminders([row({ ignored: true })], TODAY).length, 0)
})

Deno.test('no next_expected_date means nothing to remind about', () => {
  assertEquals(dueReminders([row({ next_expected_date: null })], TODAY).length, 0)
})

Deno.test('only active and overdue runs are reminded about', () => {
  for (const status of ['active', 'overdue']) {
    assertEquals(dueReminders([row({ status })], TODAY).length, 1, status)
  }
  for (const status of ['possible', 'ended', 'cancelled']) {
    assertEquals(dueReminders([row({ status })], TODAY).length, 0, status)
  }
})

Deno.test('a reminder already sent for THIS date is not resent', () => {
  assertEquals(
    dueReminders([row({ last_reminded_for_date: '2026-08-13' })], TODAY).length,
    0,
  )
})

Deno.test('a reminder sent for a PREVIOUS date does not suppress the next one', () => {
  assertEquals(
    dueReminders([row({ last_reminded_for_date: '2026-07-13' })], TODAY).length,
    1,
  )
})

Deno.test('a renewal that MOVED re-arms the reminder by itself', () => {
  const moved = row({ last_reminded_for_date: '2026-08-12', next_expected_date: '2026-08-13' })
  assertEquals(dueReminders([moved], TODAY).length, 1)
})

Deno.test('a past due date is never reminded about', () => {
  assertEquals(
    dueReminders([row({ status: 'overdue', next_expected_date: '2026-08-08' })], TODAY).length,
    0,
  )
})

Deno.test('a missed day still sends rather than skipping the renewal', () => {
  assertEquals(dueReminders([row({ next_expected_date: TODAY })], TODAY).length, 1)
})

Deno.test('the nickname wins over the detected service name', () => {
  const [due] = dueReminders([row({ nickname: 'Mum’s Netflix' })], TODAY)
  assertEquals(due.displayName, 'Mum’s Netflix')
})

Deno.test('due reminders come out soonest first, then alphabetical', () => {
  const rows = [
    row({ run_id: 'c', service_name: 'Spotify', next_expected_date: '2026-08-13' }),
    row({ run_id: 'a', service_name: 'Disney+', next_expected_date: '2026-08-12' }),
    row({ run_id: 'b', service_name: 'Globoplay', next_expected_date: '2026-08-13' }),
  ]
  assertEquals(dueReminders(rows, TODAY).map((d) => d.runId), ['a', 'b', 'c'])
})

Deno.test('push alone opts out of email; both opts in', () => {
  assertEquals(wantsEmail('email'), true)
  assertEquals(wantsEmail('both'), true)
  assertEquals(wantsEmail('push'), false)
})

Deno.test('relative copy matches the vocabulary the app already uses', () => {
  assertEquals(whenText(0), 'today')
  assertEquals(whenText(1), 'tomorrow')
  assertEquals(whenText(3), 'in 3 days')
})

Deno.test('money renders Brazilian, with a thousands separator', () => {
  assertEquals(moneyText(44.9, 'BRL'), 'R$ 44,90')
  assertEquals(moneyText('44.90', 'BRL'), 'R$ 44,90')
  assertEquals(moneyText(1412.8, 'BRL'), 'R$ 1.412,80')
  assertEquals(moneyText(6.45, 'USD'), 'USD 6,45')
  assertEquals(moneyText(null, 'BRL'), null)
  assertEquals(moneyText(44.9, null), '44,90')
})


Deno.test('a foreign charge is stated in the account currency, not the bank\'s', () => {
  const m = chargeMoney(
    { amount: 6.45, currency: 'USD', amount_in_account_currency: 34.33 },
    'BRL',
  )
  assertEquals(m.amount, 34.33)
  assertEquals(m.currency, 'BRL')
  assertEquals(moneyText(m.amount, m.currency), 'R$ 34,33')
})

Deno.test('a domestic charge keeps its own currency', () => {
  const m = chargeMoney(
    { amount: 44.9, currency: 'BRL', amount_in_account_currency: null },
    'BRL',
  )
  assertEquals(m.amount, 44.9)
  assertEquals(m.currency, 'BRL')
  assertEquals(moneyText(m.amount, m.currency), 'R$ 44,90')
})

Deno.test('an orphaned charge keeps its stored currency rather than guessing', () => {
  const m = chargeMoney(
    { amount: 6.45, currency: 'USD', amount_in_account_currency: 34.33 },
    null,
  )
  assertEquals(m.amount, 34.33)
  assertEquals(m.currency, 'USD')
})

Deno.test('a run with no charge yet still renders, without money', () => {
  const m = chargeMoney({ amount: null, currency: null, amount_in_account_currency: null }, 'BRL')
  assertEquals(m.amount, null)
  assertEquals(moneyText(m.amount, m.currency), null)
})

Deno.test('string numerics from PostgREST survive the resolution', () => {
  const m = chargeMoney(
    { amount: '6.45', currency: 'USD', amount_in_account_currency: '34.33' },
    'BRL',
  )
  assertEquals(moneyText(m.amount, m.currency), 'R$ 34,33')
})
