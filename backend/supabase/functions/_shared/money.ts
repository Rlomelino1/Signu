// The only place amounts are compared or added. Every rule calls into here and
// no rule performs its own arithmetic on amounts (v24).
//
// This exists because the identical bug has already shipped once: the dry-run
// harness compared amounts with `abs(a - b) < 0.01`, and abs(6.46 - 6.45) is
// 0.009999999999999787 in IEEE float, which slips under that threshold. Two
// amounts a cent apart compared EQUAL and R1 invented a pair (v23). Moving the
// rules into a second language re-opens exactly that hole, so the discipline is
// centralised rather than restated at each call site.

/** Amount as integer cents. The only representation the rules compare. */
export function cents(amount: number | string): number {
  const n = typeof amount === 'string' ? Number(amount) : amount
  if (!Number.isFinite(n)) throw new Error(`not a finite amount: ${amount}`)
  // Math.round, not trunc: 6.45 * 100 is 644.9999999999999 in binary floating
  // point, and truncation would yield 644.
  return Math.round(Math.abs(n) * 100)
}

/** Magnitudes equal to the cent. NEVER an epsilon — see the note above. */
export function sameAmount(a: number | string, b: number | string): boolean {
  return cents(a) === cents(b)
}

/** Back to a decimal for writing. Kept here so rounding lives in one file. */
export function fromCents(c: number): number {
  return Math.round(c) / 100
}
