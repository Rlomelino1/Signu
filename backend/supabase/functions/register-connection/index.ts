
import { json, resolveCaller, serviceClient } from '../_shared/auth.ts'
import { accountKey, accountLabel, pluggyAccountKey } from '../_shared/accounts.ts'
import { pluggy, pluggyApiKey, PluggyError, type PluggyItem } from '../_shared/pluggy.ts'

async function findClashingAccount(
  db: ReturnType<typeof serviceClient>,
  userId: string,
  itemId: string,
): Promise<{ label: string; institution: string } | null> {
  let incoming: { subtype?: unknown; number?: unknown }[]
  try {
    const apiKey = await pluggyApiKey()
    const payload = await pluggy<{ results?: { subtype?: unknown; number?: unknown }[] }>(
      `/accounts?itemId=${encodeURIComponent(itemId)}`,
      apiKey,
    )
    incoming = payload?.results ?? []
  } catch {
    return null
  }

  const incomingKeys = new Set(
    incoming.map(pluggyAccountKey).filter((key): key is string => key !== null),
  )
  if (incomingKeys.size === 0) return null

  const { data: existing, error } = await db
    .from('bank_account')
    .select('type, last4, official_name, connection!inner(user_id, institution_name)')
    .eq('connection.user_id', userId)
  if (error || !existing) return null

  for (const row of existing) {
    const key = accountKey(row.type as string | null, row.last4 as string | null)
    if (!key || !incomingKeys.has(key)) continue
    const connection = row.connection as unknown as { institution_name?: string } | null
    return {
      label: accountLabel(row.official_name as string | null, row.last4 as string | null),
      institution: connection?.institution_name ?? 'another connection',
    }
  }
  return null
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json({ error: 'POST only' }, 405)

  const who = await resolveCaller(req)
  if (!who.ok) return json({ error: who.error }, who.status)

  let itemId: string | null = null
  try {
    const body = await req.json()
    itemId = typeof body?.itemId === 'string' ? body.itemId : null
  } catch {
    return json({ error: 'body must be JSON' }, 400)
  }
  if (!itemId) return json({ error: 'itemId is required' }, 400)

  let item: PluggyItem
  try {
    const apiKey = await pluggyApiKey()
    item = await pluggy<PluggyItem>(`/items/${itemId}`, apiKey)
  } catch (e) {
    const status = e instanceof PluggyError ? e.status : 500
    return json({ error: e instanceof Error ? e.message : String(e) }, status)
  }

  if (item.clientUserId !== who.caller.id) {
    return json({ error: 'not found' }, 404)
  }

  const db = serviceClient()

  const { data: already } = await db
    .from('connection')
    .select('id')
    .eq('user_id', who.caller.id)
    .eq('provider_connection_id', itemId)
    .maybeSingle()

  if (!already) {
    const clash = await findClashingAccount(db, who.caller.id, itemId)
    if (clash) {
      try {
        const apiKey = await pluggyApiKey()
        await pluggy(`/items/${itemId}`, apiKey, { method: 'DELETE' })
      } catch (error) {
        console.log(
          `orphan cleanup failed for item ${itemId}: ${
            error instanceof Error ? error.message : String(error)
          }`,
        )
      }

      return json({
        error: `${clash.label} is already connected through ${clash.institution}. `
          + `Remove that bank first if you meant to reconnect it.`,
        code: 'duplicate_accounts',
      }, 409)
    }
  }

  const { data, error } = await db
    .from('connection')
    .upsert(
      {
        user_id: who.caller.id,
        provider_connection_id: itemId,
        institution_id: String(item.connector?.id ?? ''),
        institution_name: item.connector?.name ?? 'Bank',
        status: 'needs_action',
      },
      { onConflict: 'user_id,provider_connection_id' },
    )
    .select('id, institution_name')
    .single()
  if (error) return json({ error: `upsert connection: ${error.message}` }, 500)

  const secret = Deno.env.get('SYNC_SECRET')
  let sync: unknown = 'started'
  if (secret) {
    const running = fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/pluggy-sync`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-sync-secret': secret },
      body: JSON.stringify({ connectionId: data.id }),
    }).catch(() => {
    })
    const runtime = (globalThis as { EdgeRuntime?: { waitUntil?: (p: Promise<unknown>) => void } }).EdgeRuntime
    if (typeof runtime?.waitUntil === 'function') runtime.waitUntil(running)
    else await running
  } else {
    sync = 'SYNC_SECRET not configured — connection saved, nothing synced'
  }

  return json({
    ok: true,
    connectionId: data.id,
    institutionName: data.institution_name,
    itemStatus: `${item.status}/${item.executionStatus}`,
    sync,
  })
})
