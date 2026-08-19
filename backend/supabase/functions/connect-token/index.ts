
import { json, ownedConnection, resolveCaller, serviceClient } from '../_shared/auth.ts'
import { pluggy, pluggyApiKey, PluggyError } from '../_shared/pluggy.ts'

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json({ error: 'POST only' }, 405)

  const who = await resolveCaller(req)
  if (!who.ok) return json({ error: who.error }, who.status)

  let connectionId: string | null = null
  try {
    const body = await req.text()
    if (body.trim()) {
      const parsed = JSON.parse(body)
      connectionId = typeof parsed?.connectionId === 'string' ? parsed.connectionId : null
    }
  } catch {
    return json({ error: 'body must be JSON' }, 400)
  }

  let itemId: string | null = null
  if (connectionId) {
    const db = serviceClient()
    const owned = await ownedConnection<{ provider_connection_id: string }>(
      db,
      who.caller,
      connectionId,
      'provider_connection_id',
    )
    if (!owned.ok) return json({ error: owned.error }, owned.status)
    itemId = owned.row.provider_connection_id
  }

  try {
    const apiKey = await pluggyApiKey()
    const token = await pluggy<{ accessToken?: string }>('/connect_token', apiKey, {
      method: 'POST',
      body: JSON.stringify({
        ...(itemId ? { itemId } : {}),
        options: {
          clientUserId: who.caller.id,
        },
      }),
    })
    if (!token?.accessToken) return json({ error: 'Pluggy returned no accessToken' }, 502)

    return json({
      ok: true,
      accessToken: token.accessToken,
      mode: itemId ? 'update' : 'create',
      itemId,
    })
  } catch (e) {
    const status = e instanceof PluggyError ? e.status : 500
    return json({ error: e instanceof Error ? e.message : String(e) }, status)
  }
})
