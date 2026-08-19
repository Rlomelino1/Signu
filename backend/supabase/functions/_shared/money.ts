
export function cents(amount: number | string): number {
  const n = typeof amount === 'string' ? Number(amount) : amount
  if (!Number.isFinite(n)) throw new Error(`not a finite amount: ${amount}`)
  // Math.round, not trunc: 6.45 * 100 is 644.9999999999999 in binary floating
  // point, and truncation would yield 644.
  return Math.round(Math.abs(n) * 100)
}

export interface Money {
  amount: number | string
  currency: string
}

function normalizeCurrency(c: string | null | undefined): string {
  return (c ?? '').trim().toUpperCase()
}

/** The ONLY equality test for money: same currency AND same cents.
 *
 *  There is deliberately no amount-only comparison exported. Comparing cents
 *  alone is unsound the moment one merchant bills in two currencies, and that is
 *  already true in real data: Valve charges under a single CNPJ in both BRL and
 *  USD across 47 debits. 6.45 USD and 6.45 BRL are not the same money, and an
 *  amount-only test would (a) let R1 anchor a phantom subscription across them
 *  and (b) let the internal-transfer filter pair a USD card charge with a BRL
 *  bank credit, which HIDES a real transaction — the same dangerous direction as
 *  the v23 epsilon bug.
 *
 *  A cents-only helper existed here and was removed rather than deprecated: a
 *  footgun left in a shared module gets picked up by the next call site. */
export function sameMoney(a: Money, b: Money): boolean {
  return (
    normalizeCurrency(a.currency) === normalizeCurrency(b.currency) &&
    cents(a.amount) === cents(b.amount)
  )
}

/** Stable identity for "distinct amounts" counting, so a cross-currency pair
 *  counts as two values rather than collapsing into one. */
export function moneyKey(m: Money): string {
  return `${normalizeCurrency(m.currency)}:${cents(m.amount)}`
}

/** Back to a decimal for writing. Kept here so rounding lives in one file. */
export function fromCents(c: number): number {
  return Math.round(c) / 100
}
