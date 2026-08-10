// Date arithmetic on plain YYYY-MM-DD strings, at date granularity only.
//
// No Date-with-timezone anywhere: sync already resolved timestamps to Sao Paulo
// dates on the way in (v22), so the engine works in calendar days and must not
// reintroduce a timezone. Every function here is pure and takes no clock read —
// `today` is an input to the engine, never read inside a rule (v24).

/** Days between two YYYY-MM-DD dates. Positive when b is later. */
export function daysBetween(a: string, b: string): number {
  const [ay, am, ad] = a.split('-').map(Number)
  const [by, bm, bd] = b.split('-').map(Number)
  return Math.round((Date.UTC(by, bm - 1, bd) - Date.UTC(ay, am - 1, ad)) / 86_400_000)
}

export function addDays(d: string, n: number): string {
  const [y, m, day] = d.split('-').map(Number)
  return iso(new Date(Date.UTC(y, m - 1, day + n)))
}

/** Add whole months, clamping to the last day of the target month.
 *  Jan 31 + 1 month is Feb 28/29, not Mar 3 — a subscription billed on the 31st
 *  does not migrate into the following month. */
export function addMonths(d: string, n: number): string {
  const [y, m, day] = d.split('-').map(Number)
  const target = new Date(Date.UTC(y, m - 1 + n, 1))
  const lastDay = new Date(
    Date.UTC(target.getUTCFullYear(), target.getUTCMonth() + 1, 0),
  ).getUTCDate()
  return iso(
    new Date(Date.UTC(target.getUTCFullYear(), target.getUTCMonth(), Math.min(day, lastDay))),
  )
}

export type Interval = 'monthly' | 'annual'

export function addInterval(d: string, interval: Interval, n = 1): string {
  return addMonths(d, interval === 'annual' ? 12 * n : n)
}

function iso(dt: Date): string {
  return dt.toISOString().slice(0, 10)
}

/** Day-of-month distance on a circle, so the 1st and the 30th are 2 apart
 *  rather than 29. Used by R3's alignment test (v21). */
export function circularDomDistance(a: number, b: number): number {
  const raw = Math.abs(a - b)
  return Math.min(raw, 31 - raw)
}
