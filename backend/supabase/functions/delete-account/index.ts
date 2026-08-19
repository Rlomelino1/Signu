
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
