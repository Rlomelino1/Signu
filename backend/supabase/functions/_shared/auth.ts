
import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4'

export type Caller = { id: string }

export type CallerResult =
  | { ok: true; caller: Caller }
  | { ok: false; status: number; error: string }

export async function resolveCaller(req: Request): Promise<CallerResult> {
  const header = req.headers.get('Authorization') ?? ''
  const token = header.toLowerCase().startsWith('bearer ') ? header.slice(7).trim() : ''
  if (!token) return { ok: false, status: 401, error: 'missing bearer token' }

  const anon = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    {
      auth: { persistSession: false },
      global: { headers: { Authorization: `Bearer ${token}` } },
    },
  )

  const { data, error } = await anon.auth.getUser()
  if (error || !data?.user) {
    // Deliberately not echoing the auth server's message: it distinguishes
    // expired from malformed from unknown, and none of that helps a client that
    // should simply re-authenticate.
    return { ok: false, status: 401, error: 'not authenticated' }
  }
  return { ok: true, caller: { id: data.user.id } }
}

/** The writing client. Bypasses RLS — every caller of this owes the ownership
 *  checks below before it touches a row. */
export function serviceClient(): SupabaseClient {
  return createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  )
}

/**
 * Both answers to "is this row the caller's?" are one shape on purpose: a
 * missing row and someone else's row are reported identically, so these
 * functions cannot be used to learn that an id exists. The app never sees the
 * difference either, because it can only ever name rows it just read.
 */
export type Owned<T> =
  | { ok: true; row: T }
  | { ok: false; status: number; error: string }

const NOT_YOURS = { ok: false, status: 404, error: 'not found' } as const

/** A subscription row, proved to belong to the caller. `columns` names what the
 *  decision needs, so a function cannot quietly read more than it reasons about. */
export async function ownedSubscription<T>(
  db: SupabaseClient,
  caller: Caller,
  subscriptionId: string,
  columns: string,
): Promise<Owned<T>> {
  const { data, error } = await db
    .from('subscription')
    .select(columns)
    .eq('id', subscriptionId)
    .eq('user_id', caller.id)
    .maybeSingle()
  if (error) return { ok: false, status: 500, error: `select subscription: ${error.message}` }
  if (!data) return NOT_YOURS
  return { ok: true, row: data as T }
}

/** A connection row, proved to belong to the caller. */
export async function ownedConnection<T>(
  db: SupabaseClient,
  caller: Caller,
  connectionId: string,
  columns: string,
): Promise<Owned<T>> {
  const { data, error } = await db
    .from('connection')
    .select(columns)
    .eq('id', connectionId)
    .eq('user_id', caller.id)
    .maybeSingle()
  if (error) return { ok: false, status: 500, error: `select connection: ${error.message}` }
  if (!data) return NOT_YOURS
  return { ok: true, row: data as T }
}

/** Response helper, matching the three existing functions' JSON shape. */
export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body, null, 2), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

/** Today in São Paulo, date-granular — the same clock discipline the engine
 *  uses. Overridable by the caller ONLY where a test needs a fixed date; the
 *  override is per-function, never a header, so it cannot arrive by accident. */
export function todayInSaoPaulo(): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Sao_Paulo',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date())
}
