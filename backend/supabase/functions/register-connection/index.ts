// register-connection — the other half of the connect flow, and the thing that
// replaces `seed/seed-connection.sql`.
//
// That script said of itself: "DELIBERATE STOPGAP… When the in-app connect flow
// lands, this file is deleted, not adapted." This is that flow, so it is deleted.
//
// The widget hands the app an `itemId`; this turns it into a `connection` row and
// then runs the sync, so one tap produces bank, cards, transactions and detected
// subscriptions rather than an empty row that waits for tomorrow's cron.
//
// OWNERSHIP IS THE WHOLE SECURITY QUESTION HERE
//
// An item id is just a UUID travelling through a client. Trusting it would mean
// any signed-in user could register any item they learned the id of and read a
// stranger's transactions. So the item is fetched from Pluggy and its
// `clientUserId` — set by `connect-token` to the caller's user id, and settable
// nowhere else in this codebase — must match the caller. `UNIQUE (user_id,
// provider_connection_id)` then makes a double tap idempotent rather than a
// duplicate.

import { json, resolveCaller, serviceClient } from '../_shared/auth.ts'
import { pluggy, pluggyApiKey, PluggyError, type PluggyItem } from '../_shared/pluggy.ts'

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

  // The check this function exists for. Reported as 404 rather than 403 for the
  // same reason the ownership helpers are: an endpoint that distinguishes "not
  // yours" from "does not exist" is an endpoint that confirms ids.
  if (item.clientUserId !== who.caller.id) {
    return json({ error: 'not found' }, 404)
  }

  const db = serviceClient()

  const { data, error } = await db
    .from('connection')
    .upsert(
      {
        user_id: who.caller.id,
        provider_connection_id: itemId,
        institution_id: String(item.connector?.id ?? ''),
        institution_name: item.connector?.name ?? 'Bank',
        // 'active' would be a claim, and nothing has been fetched yet. The sync
        // below overwrites this from the live item within the same request —
        // the same honesty the seed script observed for the same reason.
        status: 'needs_action',
      },
      { onConflict: 'user_id,provider_connection_id' },
    )
    .select('id, institution_name')
    .single()
  if (error) return json({ error: `upsert connection: ${error.message}` }, 500)

  // Chained, not scheduled. A row that appears with nothing behind it until the
  // next cron reads as a broken connect flow, and the sync is the thing that
  // turns the item into the screens the user just agreed to see. It chains into
  // detection itself, so subscriptions land in the same pass.
  //
  // A sync failure does NOT fail the registration: the link is real either way,
  // it is recorded on the row as `last_sync_error`, and the daily job retries.
  let sync: unknown = 'not attempted'
  const secret = Deno.env.get('SYNC_SECRET')
  if (secret) {
    try {
      const res = await fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/pluggy-sync`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-sync-secret': secret },
        body: JSON.stringify({ connectionId: data.id }),
      })
      sync = { status: res.status }
    } catch (e) {
      sync = { error: e instanceof Error ? e.message : String(e) }
    }
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
