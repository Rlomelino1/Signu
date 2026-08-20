
import { daysBetween } from './dates.ts'

export interface ReminderRow {
  run_id: string
  subscription_id: string
  service_name: string
  nickname: string | null
  remind_before_days: number | null
  ignored: boolean
  status: string
  next_expected_date: string | null
  last_reminded_for_date: string | null
  billing_interval: string
  amount: string | number | null
  currency: string | null
}

export interface DueReminder {
  runId: string
  subscriptionId: string
  displayName: string
  dueDate: string
  daysUntil: number
  amount: string | number | null
  currency: string | null
  billingInterval: string
}

export function wantsEmail(reminderChannels: string): boolean {
  return reminderChannels === 'email' || reminderChannels === 'both'
}

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

  return due.sort((a, b) =>
    a.dueDate === b.dueDate ? a.displayName.localeCompare(b.displayName) : a.dueDate.localeCompare(b.dueDate)
  )
}

export function whenText(daysUntil: number): string {
  if (daysUntil === 0) return 'today'
  if (daysUntil === 1) return 'tomorrow'
  return `in ${daysUntil} days`
}

export interface ChargeMoneyRow {
  amount: string | number | null
  currency: string | null
  amount_in_account_currency: string | number | null
}

export function chargeMoney(
  charge: ChargeMoneyRow,
  accountCurrency: string | null,
): { amount: string | number | null; currency: string | null } {
  const isForeign = charge.amount_in_account_currency !== null &&
    charge.amount_in_account_currency !== undefined
  return {
    amount: isForeign ? charge.amount_in_account_currency : charge.amount,
    currency: isForeign ? (accountCurrency ?? charge.currency) : charge.currency,
  }
}

export function moneyText(amount: string | number | null, currency: string | null): string | null {
  if (amount === null) return null
  const n = typeof amount === 'string' ? Number(amount) : amount
  if (!Number.isFinite(n)) return null
  const digits = n.toFixed(2).replace('.', ',').replace(/\B(?=(\d{3})+(?!\d))/g, '.')
  if (!currency) return digits
  return currency === 'BRL' ? `R$ ${digits}` : `${currency} ${digits}`
}
