
export function cents(amount: number | string): number {
  const n = typeof amount === 'string' ? Number(amount) : amount
  if (!Number.isFinite(n)) throw new Error(`not a finite amount: ${amount}`)
  return Math.round(Math.abs(n) * 100)
}

export interface Money {
  amount: number | string
  currency: string
}

function normalizeCurrency(c: string | null | undefined): string {
  return (c ?? '').trim().toUpperCase()
}

export function sameMoney(a: Money, b: Money): boolean {
  return (
    normalizeCurrency(a.currency) === normalizeCurrency(b.currency) &&
    cents(a.amount) === cents(b.amount)
  )
}

export function moneyKey(m: Money): string {
  return `${normalizeCurrency(m.currency)}:${cents(m.amount)}`
}

export function fromCents(c: number): number {
  return Math.round(c) / 100
}
