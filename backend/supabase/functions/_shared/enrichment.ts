
// Local merchant enrichment: the workaround for the lapsed Pluggy trial.
//
// Merchant enrichment (`transaction.merchant` — businessName + CNPJ) is a paid
// Pluggy feature. When the trial lapsed on 2026-08-25 the API kept serving
// items, accounts and transactions, but every transaction arrived with
// `merchant: null` — and because the sync re-upserts the full window daily, it
// overwrote the enrichment already stored with nulls. `merchant_key` is derived
// from CNPJ precisely because one merchant bills under several descriptors, so
// losing the CNPJ shattered each subscription's group and detection deleted
// every run (2026-08-31 incident).
//
// This table reproduces, for the merchants this account actually subscribes
// to, exactly what Pluggy's enrichment said while the trial was live. It is
// consulted only when Pluggy sends no merchant, so a paid plan would make it
// dead code rather than a conflict. Descriptors match EXACTLY (normalized:
// whitespace-collapsed, uppercased) — never by substring, so `IOF de "Steam
// Purchase"` (a fee) and `Crédito de "WL *STEAM PURCHASE"` (a refund) stay
// untouched. A new descriptor variant is a new line here, plus its test.

export interface MerchantEnrichment {
  name: string
  cnpj: string
}

// Valve bills under (at least) three descriptors, all of which carried this
// CNPJ during the trial — the same value still stored in
// subscription.merchant_key.
const VALVE: MerchantEnrichment = {
  name: 'TRUELINE VALVE CORPORATION',
  cnpj: '08057063000196',
}

const BY_DESCRIPTOR = new Map<string, MerchantEnrichment>([
  ['STEAM PURCHASE', VALVE],
  ['WL *STEAM PURCHASE', VALVE],
  ['STEAMGAMES.COM', VALVE],
])

export function localEnrichmentFor(
  normalizedDescriptor: string,
): MerchantEnrichment | null {
  return BY_DESCRIPTOR.get(normalizedDescriptor) ?? null
}
