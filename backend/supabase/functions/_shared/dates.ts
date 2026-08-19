
export function daysBetween(a: string, b: string): number {
  const [ay, am, ad] = a.split('-').map(Number)
  const [by, bm, bd] = b.split('-').map(Number)
  return Math.round((Date.UTC(by, bm - 1, bd) - Date.UTC(ay, am - 1, ad)) / 86_400_000)
}

export function addDays(d: string, n: number): string {
  const [y, m, day] = d.split('-').map(Number)
  return iso(new Date(Date.UTC(y, m - 1, day + n)))
}

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

export function circularDomDistance(a: number, b: number): number {
  const raw = Math.abs(a - b)
  return Math.min(raw, 31 - raw)
}
