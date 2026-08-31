
import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import { localEnrichmentFor } from './enrichment.ts'

Deno.test('each observed Steam descriptor maps to the Valve CNPJ', () => {
  for (const d of ['STEAM PURCHASE', 'WL *STEAM PURCHASE', 'STEAMGAMES.COM']) {
    assertEquals(localEnrichmentFor(d)?.cnpj, '08057063000196', d)
    assertEquals(localEnrichmentFor(d)?.name, 'TRUELINE VALVE CORPORATION', d)
  }
})

Deno.test('matching is exact, not substring: fee and refund descriptors stay bare', () => {
  assertEquals(localEnrichmentFor('IOF DE "STEAM PURCHASE"'), null)
  assertEquals(localEnrichmentFor('IOF DE "STEAMGAMES.COM"'), null)
  assertEquals(localEnrichmentFor('CRÉDITO DE "WL *STEAM PURCHASE"'), null)
})

Deno.test('an unknown merchant gets nothing', () => {
  assertEquals(localEnrichmentFor('CLAUDE.AI SUBSCRIPTION'), null)
  assertEquals(localEnrichmentFor(''), null)
})
