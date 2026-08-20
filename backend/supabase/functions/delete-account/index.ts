
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
  if (error) {
    console.log(`delete-account deleteUser failed: ${error.message}`)
    return json({ error: 'could not delete the account' }, 500)
  }

  return json({ ok: true, userId: who.caller.id, deleted: true })
})
