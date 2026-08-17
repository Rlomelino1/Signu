// Which reminders are due — the pure core (v28).
//
// Same split as detection (v24): every rule lives here, takes `today` as an
// input, reads no clock and touches no database, so it is testable without
// either. `send-reminders/index.ts` is the shell that loads rows, calls this, and
// sends what comes back.
//
// Dates are plain YYYY-MM-DD strings throughout, for the reason dates.ts gives:
// sync already resolved timestamps to São Paulo calendar days on the way in
// (v22), and reintroducing a timezone here would let a reminder fire on the wrong
// day for the same reason 37 of 258 rows once shifted.

import { daysBetween } from './dates.ts'

/** A candidate run, joined to the subscription that owns it. */
export interface ReminderRow {
  run_id: string
  subscription_id: string
  service_name: string
  nickname: string | null
  /** null = reminders off for this subscription. */
  remind_before_days: number | null
  ignored: boolean
  status: string
  next_expected_date: string | null
  /** The `next_expected_date` a reminder was last sent for. */
  last_reminded_for_date: string | null
  billing_interval: string
  /** Cost shown in the email; already in the account's currency (v26). */
  amount: string | number | null
  currency: string | null
}

export interface DueReminder {
  runId: string
  subscriptionId: string
  /** What the user calls it: their nickname wins over the detected name. */
  displayName: string
  dueDate: string
  daysUntil: number
  amount: string | number | null
  currency: string | null
  billingInterval: string
}

/** Channels that mean "send an email". `push` alone opts out — push does not
 *  exist (v9 downgraded it to a maybe), so treating it as email would deliver
 *  something the user did not ask for, and treating `both` as push-only would
 *  deliver nothing at all. */
export function wantsEmail(reminderChannels: string): boolean {
  return reminderChannels === 'email' || reminderChannels === 'both'
}

/**
 * The runs a reminder is due for today.
 *
 * Five exclusions, each with a reason a reminder would otherwise be wrong:
 *
 *  1. `remind_before_days` null — reminders are off. The nullable column IS the
 *     switch (v5), so there is no separate enabled flag to disagree with.
 *  2. `ignored` — the user said this is not a subscription. Reminding about it
 *     contradicts a user assertion, which the engine may never do (v24).
 *  3. no `next_expected_date` — nothing to remind about. Cancelled runs always
 *     have it null by contract, so this covers them without naming them.
 *  4. status not active or overdue — `possible` has not been confirmed and
 *     reminding would pre-empt the review screen; `ended` and `cancelled` are
 *     not going to be charged again.
 *  5. already reminded for THIS date. Not "reminded recently": storing the date
 *     rather than a timestamp means a renewal that moves re-arms the reminder by
 *     itself, and detection rewrites `next_expected_date` on every run.
 *
 * A due date in the past is excluded too. An overdue run keeps its
 * `next_expected_date` while the charge has not landed, and "renews in -3 days"
 * is not a reminder — it is a bug report.
 */
export function dueReminders(rows: ReminderRow[], today: string): DueReminder[] {
  const due: DueReminder[] = []

  for (const row of rows) {
    if (row.remind_before_days === null) continue
    if (row.ignored) continue
    if (!row.next_expected_date) continue
    if (row.status !== 'active' && row.status !== 'overdue') continue
    if (row.last_reminded_for_date === row.next_expected_date) continue

    const daysUntil = daysBetween(today, row.next_expected_date)
    if (daysUntil < 0) continue
    // `<=`, not `===`: a job that missed a day must still send rather than skip
    // the renewal silently. Combined with exclusion 5 this sends exactly once.
    if (daysUntil > row.remind_before_days) continue

    due.push({
      runId: row.run_id,
      subscriptionId: row.subscription_id,
      displayName: row.nickname ?? row.service_name,
      dueDate: row.next_expected_date,
      daysUntil,
      amount: row.amount,
      currency: row.currency,
      billingInterval: row.billing_interval,
    })
  }

  // Soonest first, so the email reads in the order the charges will land.
  return due.sort((a, b) =>
    a.dueDate === b.dueDate ? a.displayName.localeCompare(b.displayName) : a.dueDate.localeCompare(b.dueDate)
  )
}

/** "today" / "tomorrow" / "in 3 days" — the same vocabulary the app uses for
 *  relative renewal copy, so an email and the screen never describe one date
 *  differently. */
export function whenText(daysUntil: number): string {
  if (daysUntil === 0) return 'today'
  if (daysUntil === 1) return 'tomorrow'
  return `in ${daysUntil} days`
}

/** A charge row as the reminder query reads it, with the account reached through
 *  the transaction — the only route a charge has to one. */
export interface ChargeMoneyRow {
  amount: string | number | null
  currency: string | null
  amount_in_account_currency: string | number | null
}

/** v26's dual amounts, resolved into ONE amount and the currency that actually
 *  describes it.
 *
 *  The bug this exists to prevent shipped a real email on 2026-08-17 reading
 *  **"USD 34,33"** — a number that was neither figure. The amount coalesced to
 *  `amount_in_account_currency` (34.33 BRL) while the currency was taken from the
 *  charge unconditionally (USD, the currency the bank charged in). Half of each
 *  pair. It only misreports on CROSS-CURRENCY charges, which is why it survived:
 *  the one subscription in production happens to be Steam, billed in USD.
 *
 *  `amountInAccountCurrency != null` IS the foreign test — it is populated exactly
 *  when the transaction was foreign, verified across all 258 real rows at v26.
 *
 *  This deliberately mirrors `ChargeRow.domain(accountCurrency:)` in the client's
 *  `SupabaseRows.swift`, which already had it right. Two implementations of one
 *  rule is the thing this codebase keeps paying for, and the email and the screen
 *  disagreeing about a price is exactly the failure the reminder query's own
 *  comment claimed was impossible. */
export function chargeMoney(
  charge: ChargeMoneyRow,
  accountCurrency: string | null,
): { amount: string | number | null; currency: string | null } {
  const isForeign = charge.amount_in_account_currency !== null &&
    charge.amount_in_account_currency !== undefined
  return {
    amount: isForeign ? charge.amount_in_account_currency : charge.amount,
    // An orphaned charge cannot reach an account, so it keeps its stored
    // currency: the best statement available about it, and still honest.
    currency: isForeign ? (accountCurrency ?? charge.currency) : charge.currency,
  }
}

/** Brazilian formatting, because every renewal in this app is stated in it:
 *  `R$ 44,90`. Falls back to bare digits when the currency is unknown rather
 *  than inventing a symbol. */
export function moneyText(amount: string | number | null, currency: string | null): string | null {
  if (amount === null) return null
  const n = typeof amount === 'string' ? Number(amount) : amount
  if (!Number.isFinite(n)) return null
  const digits = n.toFixed(2).replace('.', ',').replace(/\B(?=(\d{3})+(?!\d))/g, '.')
  if (!currency) return digits
  return currency === 'BRL' ? `R$ ${digits}` : `${currency} ${digits}`
}
