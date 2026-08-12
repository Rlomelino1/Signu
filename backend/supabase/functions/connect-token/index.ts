// connect-token — mints the short-lived token the Pluggy Connect widget runs on.
//
// The widget is client-side, so it cannot hold `PLUGGY_CLIENT_SECRET`; a connect
// token is the credential designed for that position, scoped to the one item the
// session produces rather than to the whole client app. This function is the only
// place the real secret is ever used for that purpose.
//
// TWO MODES, ONE ENDPOINT
//
//  * create — no body. The widget opens on the connector list, and completing it
//    produces a NEW item, which the app then hands to `register-connection`.
//  * update — `{ connectionId }`. The widget re-opens the EXISTING item for
//    re-authentication, which is what 12b's "Reconnect <bank>" and Home's
//    needs-action banner need. Pluggy requires the `itemId` on the token itself
//    for this; a token minted without one cannot update an item, by design.
//
// The app never sees an item id it did not already have: `connectionId` is a row
// the caller owns, and the item id is read from it here.
//
// `clientUserId` is set to the caller's user id, and that is not telemetry — it
// is what makes `register-connection`'s ownership check possible. Without it, an
// item id is a bearer token: anyone who learns one could claim it.

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
        // Top level, not inside `options` — checked against the live API.
        ...(itemId ? { itemId } : {}),
        options: {
          clientUserId: who.caller.id,
          // Create only. On an update the item already exists and this would be
          // asking Pluggy to avoid duplicating the thing we are re-authenticating.
          ...(itemId ? {} : { avoidDuplicates: true }),
        },
      }),
    })
    if (!token?.accessToken) return json({ error: 'Pluggy returned no accessToken' }, 502)

    return json({
      ok: true,
      accessToken: token.accessToken,
      // Echoed so the client can assert it opened the widget on the item it
      // meant to, rather than inferring the mode from whether it sent a body.
      mode: itemId ? 'update' : 'create',
      itemId,
    })
  } catch (e) {
    const status = e instanceof PluggyError ? e.status : 500
    return json({ error: e instanceof Error ? e.message : String(e) }, status)
  }
})
