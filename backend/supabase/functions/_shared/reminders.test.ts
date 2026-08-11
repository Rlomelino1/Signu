import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import { dueReminders, moneyText, type ReminderRow, wantsEmail, whenText } from './reminders.ts'

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
  // 5 days out with a 2-day lead.
  assertEquals(dueReminders([row({ next_expected_date: '2026-08-16' })], TODAY).length, 0)
})

Deno.test('null remind_before_days means reminders are off', () => {
  // The nullable column IS the switch (v5) — there is no separate flag that
  // could disagree with it.
  assertEquals(dueReminders([row({ remind_before_days: null })], TODAY).length, 0)
})

Deno.test('remind_before_days of 0 still fires on the day', () => {
  // 0 is not null. Reading it as "off" would silently disable the setting for
  // anyone who chose same-day.
  assertEquals(dueReminders([row({ remind_before_days: 0, next_expected_date: TODAY })], TODAY).length, 1)
  assertEquals(dueReminders([row({ remind_before_days: 0, next_expected_date: '2026-08-12' })], TODAY).length, 0)
})

Deno.test('a dismissed subscription is never reminded about', () => {
  // The user said this is not a subscription. Reminding contradicts a user
  // assertion, which the engine may never do (v24).
  assertEquals(dueReminders([row({ ignored: true })], TODAY).length, 0)
})

Deno.test('no next_expected_date means nothing to remind about', () => {
  // Cancelled runs always have it null by contract, so this covers them without
  // naming the status.
  assertEquals(dueReminders([row({ next_expected_date: null })], TODAY).length, 0)
})

Deno.test('only active and overdue runs are reminded about', () => {
  for (const status of ['active', 'overdue']) {
    assertEquals(dueReminders([row({ status })], TODAY).length, 1, status)
  }
  // `possible` has not been confirmed — reminding would pre-empt the review
  // screen and present a guess as a fact.
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
  // The whole reason the column stores a date and not a boolean or a timestamp:
  // last month's reminder must not silence this month's.
  assertEquals(
    dueReminders([row({ last_reminded_for_date: '2026-07-13' })], TODAY).length,
    1,
  )
})

Deno.test('a renewal that MOVED re-arms the reminder by itself', () => {
  // Detection rewrites next_expected_date on every pass. If it shifts after a
  // reminder went out, the stored date no longer matches and the user hears
  // about the new date — no extra bookkeeping.
  const moved = row({ last_reminded_for_date: '2026-08-12', next_expected_date: '2026-08-13' })
  assertEquals(dueReminders([moved], TODAY).length, 1)
})

Deno.test('a past due date is never reminded about', () => {
  // An overdue run keeps its next_expected_date while the charge has not landed.
  // "Renews in -3 days" is not a reminder.
  assertEquals(
    dueReminders([row({ status: 'overdue', next_expected_date: '2026-08-08' })], TODAY).length,
    0,
  )
})

Deno.test('a missed day still sends rather than skipping the renewal', () => {
  // Lead time 2, renewal today: the job did not run yesterday. `<=` rather than
  // `===` on the lead time is what stops a whole renewal being skipped in
  // silence, and the sent-date check is what keeps it to one send.
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
  // Push does not exist (v9 downgraded it to a maybe). Treating `push` as email
  // would deliver something the user did not ask for; treating `both` as
  // push-only would deliver nothing at all.
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
  // A foreign charge is already converted into the account currency by the time
  // it reaches a charge row (v26), so this is the unusual case — but naming the
  // currency beats inventing a symbol for it.
  assertEquals(moneyText(6.45, 'USD'), 'USD 6,45')
  assertEquals(moneyText(null, 'BRL'), null)
  assertEquals(moneyText(44.9, null), '44,90')
})
