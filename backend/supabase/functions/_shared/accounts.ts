// How an account is identified across two connections, and the two field mappings
// that identification depends on.
//
// WHY THIS IS SHARED WHEN `_shared/pluggy.ts` DELIBERATELY IS NOT
//
// That file records a tolerated duplication: `pluggy-sync` keeps its own copy of
// the request helpers because drifting copies of "call Pluggy" fail loudly. These
// two mappings are different in kind. `register-connection` compares the accounts
// of a NEW item against the accounts already stored by a PREVIOUS sync, so the two
// sides must agree about what `type` and `last4` mean. If they drift, the
// comparison stops matching and the duplicate check silently passes everything —
// a safety check that fails open and says nothing, which is the failure mode this
// codebase keeps being bitten by.
//
// So this is shared precisely because drift here is invisible.

/** `bank_account.type`, whose CHECK is ('credit_card','checking').
 *
 *  The mapping is off Pluggy's `subtype` (CREDIT_CARD / CHECKING_ACCOUNT), NOT its
 *  `type` (CREDIT / BANK) — two different vocabularies at the same field name.
 *  Anything else (savings, investment) returns null and is skipped rather than
 *  guessed. */
export function accountType(subtype: unknown): 'credit_card' | 'checking' | null {
  const sub = String(subtype ?? '').toUpperCase()
  if (sub === 'CREDIT_CARD') return 'credit_card'
  if (sub === 'CHECKING_ACCOUNT') return 'checking'
  return null
}

/** Pluggy's `number` is already 4 digits on cards ('2049') but a full hyphenated
 *  account number on checking ('88120381-6'), where slicing the last 4 CHARACTERS
 *  yields '81-6'. Digits only, then last 4. */
export function lastFour(number: unknown): string | null {
  if (number == null) return null
  const digits = String(number).replace(/\D/g, '')
  return digits.length ? digits.slice(-4) : null
}

/** The key two connections are compared on: account type plus last four digits.
 *
 *  WHAT IS DELIBERATELY NOT IN THE KEY, AND WHY
 *
 *  Not the provider's account id: Pluggy issues those per ITEM, so the same bank
 *  connected twice produces two different ids. Keying on them would make the check
 *  match nothing, which is the one outcome worse than no check.
 *
 *  Not the account name either, though it is tempting and available. `official_name`
 *  is `marketingName ?? name`, and Pluggy has changed marketing names before ('Conta
 *  Pré-paga' arrived as a suffix at some point). A name in the key means a renamed
 *  account stops matching itself, and the duplicate slips through silently.
 *
 *  THE TRADE-OFF THIS ACCEPTS. Type plus last4 can collide across banks — a
 *  Mastercard ending 2049 at one bank and another ending 2049 elsewhere. That
 *  produces a FALSE POSITIVE: a legitimate second bank is refused. Chosen
 *  deliberately over the alternative, because a false positive is loud and legible
 *  (the message names the account it collided with, and the user can say it is
 *  wrong) while a false negative double-counts every transaction on that account
 *  and says nothing at all. Visible over silent, the same call v40 made.
 *
 *  Null when the account cannot be identified — an unmapped subtype or a missing
 *  number. Callers must treat null as "not comparable" and never as a match. */
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
