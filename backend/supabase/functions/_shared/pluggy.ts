// pluggy.ts — the Pluggy API surface the connect flow needs.
//
// `pluggy-sync` carries its own copy of these two helpers and keeps it: it is the
// live daily job, and the same tolerated duplication already exists for
// `secretsMatch` across the three machine-invoked functions. What is shared here
// is shared because the CONNECT flow has two halves — mint a token, register the
// item it produced — and they must agree about credentials and error shape.
//
// Everything here is verified against the live API rather than the published
// reference, per the reality-contract habit this project acquired the hard way
// (v20): `/auth` answers `{ apiKey }`, `/connect_token` answers `{ accessToken }`
// and takes `itemId` at the TOP level (not inside `options`) for update mode.

const PLUGGY = 'https://api.pluggy.ai'

export class PluggyError extends Error {
  readonly status: number
  constructor(message: string, status: number) {
    super(message)
    this.status = status
  }
}

/** One call per invocation. The key is short-lived and there is nowhere durable
 *  to cache it that would be worth the staleness risk. */
export async function pluggyApiKey(): Promise<string> {
  const clientId = Deno.env.get('PLUGGY_CLIENT_ID')
  const clientSecret = Deno.env.get('PLUGGY_CLIENT_SECRET')
  if (!clientId || !clientSecret) {
    throw new PluggyError('PLUGGY_CLIENT_ID / PLUGGY_CLIENT_SECRET not configured', 500)
  }
  const auth = await pluggy<{ apiKey?: string }>('/auth', null, {
    method: 'POST',
    body: JSON.stringify({ clientId, clientSecret }),
  })
  if (!auth?.apiKey) throw new PluggyError('Pluggy /auth returned no apiKey', 502)
  return auth.apiKey
}

export async function pluggy<T>(
  path: string,
  apiKey: string | null,
  init?: RequestInit,
): Promise<T> {
  const res = await fetch(`${PLUGGY}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...(apiKey ? { 'X-API-KEY': apiKey } : {}),
      ...(init?.headers ?? {}),
    },
  })
  if (!res.ok) {
    const body = await res.text()
    // Truncated, not summarised: Pluggy's errors name the actual problem
    // ("itemId not found", a connector outage) and paraphrasing hides the fix.
    throw new PluggyError(
      `Pluggy ${init?.method ?? 'GET'} ${path} -> ${res.status}: ${body.slice(0, 400)}`,
      502,
    )
  }
  return (await res.json()) as T
}

/** Only the fields the connect flow reads. `clientUserId` is the load-bearing
 *  one — see register-connection, where it is the ownership proof. */
export interface PluggyItem {
  id: string
  clientUserId?: string | null
  status?: string
  executionStatus?: string
  consentExpiresAt?: string | null
  connector?: { id?: number | string | null; name?: string | null } | null
}
