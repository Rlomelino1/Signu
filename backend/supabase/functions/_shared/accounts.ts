
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

/** `accountKey` for a Pluggy account payload, mapped exactly as `pluggy-sync`
 *  stores it, so the two sides of the comparison cannot disagree. */
export function pluggyAccountKey(
  account: { subtype?: unknown; number?: unknown } | null | undefined,
): string | null {
  return accountKey(accountType(account?.subtype), lastFour(account?.number))
}

/** What the user is shown when a key collides. Never the key itself: 'checking:0381'
 *  explains nothing, while 'Nu Pagamentos S.A. ···· 0381' is the row they recognise
 *  from their own Settings screen. */
export function accountLabel(officialName: string | null, last4: string | null): string {
  const name = (officialName ?? '').trim()
  if (name && last4) return `${name} ···· ${last4}`
  if (name) return name
  return last4 ? `···· ${last4}` : 'an account'
}

/** The label stored on a charge: brand plus last four, e.g. 'Master 2049'.
 *
 *  WHY THE ENGINE WRITES THIS AT ALL (v60)
 *
 *  `charge.card_label` is documented as a snapshot at billing time and had a reader on
 *  every subscription row while `detection.ts` hardcoded `card_label: null` — a column
 *  with no writer, so the UI drew a separator around an absence for as long as the app
 *  has existed.
 *
 *  The client can derive the same string from the account a charge resolves to, and
 *  does (v59) — but derivation answers a different question. It says which card the
 *  transaction sits behind NOW; a snapshot says which card was charged THEN. A card
 *  replaced next year must not rewrite this year's history, which is the whole reason
 *  the column exists.
 *
 *  'Master' rather than 'MASTERCARD' because the value is a label: the column's own
 *  comment gives 'Visa 4821' as the example. Brands otherwise keep their given
 *  spelling with a leading capital, so an unmapped network reads as itself rather than
 *  as a guess.
 *
 *  Null when the account cannot name a card — a checking account has no brand, and
 *  'Account 3816' would be inventing one. */
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
