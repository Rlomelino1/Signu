import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import {
  accountKey,
  accountLabel,
  accountType,
  cardLabel,
  lastFour,
  pluggyAccountKey,
} from './accounts.ts'



Deno.test('accountType maps off subtype, not type', () => {
  assertEquals(accountType('CREDIT_CARD'), 'credit_card')
  assertEquals(accountType('CHECKING_ACCOUNT'), 'checking')
  assertEquals(accountType('credit_card'), 'credit_card')
})

Deno.test('accountType refuses to guess anything else', () => {
  for (const subtype of ['SAVINGS_ACCOUNT', 'INVESTMENT', '', null, undefined, 'CREDIT', 'BANK']) {
    assertEquals(accountType(subtype), null, `${subtype} must not be mapped`)
  }
})

// -------------------------------------------------------------------- lastFour

Deno.test('lastFour takes digits only, then the last four', () => {
  // The real shapes: a card arrives pre-truncated, a checking account arrives
  // hyphenated. Slicing characters on the latter yields '81-6', which is why this
  // strips non-digits first.
  assertEquals(lastFour('2049'), '2049')
  // Verified against the stored rows, not reasoned about: production's
  // bank_account holds last4 '3816' for '88120381-6'. The hyphen is a check digit,
  // so the last four DIGITS end with it — '3816', not '0381'.
  assertEquals(lastFour('88120381-6'), '3816')
  assertEquals(lastFour('27311197-3'), '1973')
})

Deno.test('lastFour is null when there is nothing to identify', () => {
  assertEquals(lastFour(null), null)
  assertEquals(lastFour(undefined), null)
  assertEquals(lastFour(''), null)
  assertEquals(lastFour('----'), null)
})

// ------------------------------------------------------------------- accountKey

Deno.test('accountKey needs both halves', () => {
  assertEquals(accountKey('checking', '3816'), 'checking:3816')
  // Null means "not comparable", and callers must not treat it as a match — an
  // unmapped subtype or a missing number cannot be said to collide with anything.
  assertEquals(accountKey(null, '3816'), null)
  assertEquals(accountKey('checking', null), null)
  assertEquals(accountKey(null, null), null)
})

Deno.test('the same account through two items produces the same key', () => {
  // The whole point. Pluggy issues account ids per ITEM, so a bank connected twice
  // has two different ids for one account; the key must see through that.
  const first = { id: 'acct-from-item-A', subtype: 'CHECKING_ACCOUNT', number: '88120381-6' }
  const second = { id: 'acct-from-item-B', subtype: 'CHECKING_ACCOUNT', number: '88120381-6' }
  assertEquals(pluggyAccountKey(first), pluggyAccountKey(second))
  assertEquals(pluggyAccountKey(first), 'checking:3816')
})

Deno.test('different banks behind one aggregator login do NOT collide', () => {
  // The case that was broken: two MeuPluggy items, Nubank in one and C6 in the
  // other. Same connector, same credentials, different accounts — must pass.
  const nubank = { subtype: 'CHECKING_ACCOUNT', number: '88120381-6' }
  const c6 = { subtype: 'CHECKING_ACCOUNT', number: '27311197-3' }
  assertEquals(pluggyAccountKey(nubank) === pluggyAccountKey(c6), false)
})

Deno.test('a card and a checking account with the same digits do not collide', () => {
  assertEquals(pluggyAccountKey({ subtype: 'CREDIT_CARD', number: '2049' }), 'credit_card:2049')
  assertEquals(
    pluggyAccountKey({ subtype: 'CHECKING_ACCOUNT', number: '2049' }),
    'checking:2049',
  )
})

Deno.test('an unidentifiable account yields null rather than a bare type', () => {
  assertEquals(pluggyAccountKey({ subtype: 'CREDIT_CARD', number: null }), null)
  assertEquals(pluggyAccountKey({ subtype: 'SAVINGS_ACCOUNT', number: '1234' }), null)
  assertEquals(pluggyAccountKey(null), null)
  assertEquals(pluggyAccountKey(undefined), null)
})

// ----------------------------------------------------------------- accountLabel

Deno.test('accountLabel is what the user recognises, never the key', () => {
  assertEquals(
    accountLabel('Nu Pagamentos S.A. - Instituição de Pagamento', '3816'),
    'Nu Pagamentos S.A. - Instituição de Pagamento ···· 3816',
  )
  assertEquals(accountLabel('platinum', '2049'), 'platinum ···· 2049')
})

Deno.test('accountLabel degrades rather than rendering half a sentence', () => {
  assertEquals(accountLabel('platinum', null), 'platinum')
  assertEquals(accountLabel(null, '2049'), '···· 2049')
  assertEquals(accountLabel(null, null), 'an account')
  assertEquals(accountLabel('   ', null), 'an account')
})

// --------------------------------------------------------------- cardLabel (v60)

Deno.test('cardLabel renders the label the column documents', () => {
  // The column's own comment gives 'Visa 4821' as the example, so the value is a
  // label rather than raw provider data.
  assertEquals(cardLabel('MASTERCARD', '2049'), 'Master 2049')
  assertEquals(cardLabel('VISA', '4821'), 'Visa 4821')
})

Deno.test('an unmapped network reads as itself, not as a guess', () => {
  assertEquals(cardLabel('elo', '7730'), 'Elo 7730')
  assertEquals(cardLabel('HIPERCARD', '1234'), 'Hipercard 1234')
})

Deno.test('cardLabel is null when there is no card to name', () => {
  // A checking account has no brand. 'Account 3816' would be inventing one, and the
  // subtitle drops the separator rather than printing punctuation around nothing.
  assertEquals(cardLabel(null, '3816'), null)
  assertEquals(cardLabel('MASTERCARD', null), null)
  assertEquals(cardLabel('', '2049'), null)
  assertEquals(cardLabel('MASTERCARD', '   '), null)
  assertEquals(cardLabel(undefined, undefined), null)
})
