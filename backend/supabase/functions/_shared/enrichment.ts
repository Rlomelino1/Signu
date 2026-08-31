
export interface MerchantEnrichment {
  name: string
  cnpj: string
}

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
