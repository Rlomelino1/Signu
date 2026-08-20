
export function accountType(subtype: unknown): 'credit_card' | 'checking' | null {
  const sub = String(subtype ?? '').toUpperCase()
  if (sub === 'CREDIT_CARD') return 'credit_card'
  if (sub === 'CHECKING_ACCOUNT') return 'checking'
  return null
}

export function lastFour(number: unknown): string | null {
  if (number == null) return null
  const digits = String(number).replace(/\D/g, '')
  return digits.length ? digits.slice(-4) : null
}

export function accountKey(type: string | null, last4: string | null): string | null {
  if (!type || !last4) return null
  return `${type}:${last4}`
}

export function pluggyAccountKey(
  account: { subtype?: unknown; number?: unknown } | null | undefined,
): string | null {
  return accountKey(accountType(account?.subtype), lastFour(account?.number))
}

export function accountLabel(officialName: string | null, last4: string | null): string {
  const name = (officialName ?? '').trim()
  if (name && last4) return `${name} ···· ${last4}`
  if (name) return name
  return last4 ? `···· ${last4}` : 'an account'
}

export function cardLabel(
  brand: string | null | undefined,
  last4: string | null | undefined,
): string | null {
  const digits = (last4 ?? '').trim()
  const raw = (brand ?? '').trim()
  if (!digits || !raw) return null
  const name = raw.toUpperCase() === 'MASTERCARD'
    ? 'Master'
    : raw.charAt(0).toUpperCase() + raw.slice(1).toLowerCase()
  return `${name} ${digits}`
}
