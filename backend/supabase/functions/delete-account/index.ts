// delete-account — 14a, deletion tier (a).
//
// One call. `auth.admin.deleteUser()` removes the row in `auth.users`, and the
// cascade does the rest: profiles → connection → bank_account → transaction, and
// profiles → subscription → subscription_run → charge. Nothing is soft-deleted,
// which is what makes the sheet's copy honest — "This is permanent. There's no
// grace period and no undo."
//
// THE CALLER IS THE SUBJECT, ALWAYS
//
// There is no user id in the body and there will never be one. The account
// deleted is the account that owns the JWT; an id parameter on this endpoint
// would be a request to delete anyone, gated by nothing but a valid session.
//
// WHY IT ASKS TWICE
//
// 14a's type-to-confirm is friction in the UI, and the UI is not the only thing
// that can reach this. `{"confirm": "DELETE"}` puts the same intent at the API
// boundary, so a stray POST, a retried request replayed from a log, or a token
// pasted into a shell does nothing on its own. It is not security — the JWT is
// the security — it is the difference between an action and an accident.

import { json, resolveCaller, serviceClient } from '../_shared/auth.ts'

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json({ error: 'POST only' }, 405)

  const who = await resolveCaller(req)
  if (!who.ok) return json({ error: who.error }, who.status)

  let confirm = ''
  try {
    const body = await req.json()
    confirm = typeof body?.confirm === 'string' ? body.confirm : ''
  } catch {
    return json({ error: 'body must be JSON' }, 400)
  }
  // Case-insensitive, matching the sheet's field, which renders uppercase
  // regardless of what is typed.
  if (confirm.trim().toUpperCase() !== 'DELETE') {
    return json({ error: 'confirm must be "DELETE"' }, 400)
  }

  const db = serviceClient()

  const { error } = await db.auth.admin.deleteUser(who.caller.id)
  if (error) return json({ error: `delete user: ${error.message}` }, 500)

  // The client still has to end its session. The access token stays
  // cryptographically valid until it expires — nothing revokes a signed JWT —
  // but every request it makes now resolves to a user that no longer exists, so
  // reads return nothing and these four functions return 401. Signing out is
  // what makes the app agree with the database rather than what enforces it.
  return json({ ok: true, userId: who.caller.id, deleted: true })
})
