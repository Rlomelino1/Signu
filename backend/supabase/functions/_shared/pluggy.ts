
const PLUGGY = 'https://api.pluggy.ai'

export class PluggyError extends Error {
  readonly status: number
  readonly upstreamStatus?: number
  constructor(message: string, status: number, upstreamStatus?: number) {
    super(message)
    this.status = status
    this.upstreamStatus = upstreamStatus
  }
}

export interface PluggyCredentials {
  clientId?: string
  clientSecret?: string
}

export function pluggyEnvCredentials(): PluggyCredentials {
  return {
    clientId: Deno.env.get('PLUGGY_CLIENT_ID'),
    clientSecret: Deno.env.get('PLUGGY_CLIENT_SECRET'),
  }
}

export async function pluggyApiKey(
  creds: PluggyCredentials = pluggyEnvCredentials(),
): Promise<string> {
  const { clientId, clientSecret } = creds
  if (!clientId || !clientSecret) {
    throw new PluggyError('PLUGGY_CLIENT_ID / PLUGGY_CLIENT_SECRET not configured', 500)
  }
  let auth: { apiKey?: string }
  try {
    auth = await pluggy<{ apiKey?: string }>('/auth', null, {
      method: 'POST',
      body: JSON.stringify({ clientId, clientSecret }),
    })
  } catch (error) {
    const upstream = error instanceof PluggyError ? error.upstreamStatus : undefined
    throw new PluggyError(
      `Pluggy POST /auth -> ${upstream ?? 'no response'}: response body withheld, ` +
        'because this request carried the client secret and a gateway may echo it back',
      502,
      upstream,
    )
  }
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
    throw new PluggyError(
      `Pluggy ${init?.method ?? 'GET'} ${path} -> ${res.status}: ${body.slice(0, 400)}`,
      502,
      res.status,
    )
  }
  return (await res.json()) as T
}

export interface PluggyItem {
  id: string
  clientUserId?: string | null
  status?: string
  executionStatus?: string
  consentExpiresAt?: string | null
  connector?: { id?: number | string | null; name?: string | null } | null
}
