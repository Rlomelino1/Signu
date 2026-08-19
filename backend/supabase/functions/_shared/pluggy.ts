
const PLUGGY = 'https://api.pluggy.ai'

export class PluggyError extends Error {
  readonly status: number
  constructor(message: string, status: number) {
    super(message)
    this.status = status
  }
}

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
