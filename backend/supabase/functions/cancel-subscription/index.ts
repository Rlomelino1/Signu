
import { cancellation, type CancelRun } from '../_shared/actions.ts'
import { json, ownedSubscription, resolveCaller, serviceClient, todayInSaoPaulo } from '../_shared/auth.ts'

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json({ error: 'POST only' }, 405)

  const who = await resolveCaller(req)
  if (!who.ok) return json({ error: who.error }, who.status)

  let subscriptionId: string | null = null
  let today = todayInSaoPaulo()
  try {
    const body = await req.json()
    subscriptionId = typeof body?.subscriptionId === 'string' ? body.subscriptionId : null
    if (typeof body?.today === 'string') today = body.today
  } catch {
    return json({ error: 'body must be JSON' }, 400)
  }
  if (!subscriptionId) return json({ error: 'subscriptionId is required' }, 400)

  const db = serviceClient()

  const owned = await ownedSubscription<{ id: string }>(db, who.caller, subscriptionId, 'id')
  if (!owned.ok) return json({ error: owned.error }, owned.status)

  const { data: runs, error: rErr } = await db
    .from('subscription_run')
    .select('id, status, billing_interval, start_date')
    .eq('subscription_id', subscriptionId)
    .order('start_date', { ascending: false })
    .order('id', { ascending: false })
    .limit(1)
  if (rErr) return json({ error: `select subscription_run: ${rErr.message}` }, 500)
  const run = (runs ?? [])[0] as CancelRun | undefined
  if (!run) return json({ error: 'subscription has no runs' }, 409)

  // Paid-through is measured from the last charge that actually landed, so the
  // date the app renders comes from evidence rather than from when the user got
  // round to telling us.
  const { data: charges, error: cErr } = await db
    .from('charge')
    .select('date')
    .eq('run_id', run.id)
    .order('date', { ascending: false })
    .order('id', { ascending: false })
    .limit(1)
  if (cErr) return json({ error: `select charge: ${cErr.message}` }, 500)
  const latestChargeDate = (charges ?? [])[0]?.date ?? null

  const decision = cancellation(run, latestChargeDate, today)
  if (decision.kind === 'refuse') return json({ error: decision.reason }, decision.status)
  if (decision.kind === 'noop') {
    return json({ ok: true, runId: run.id, noop: true, reason: decision.reason })
  }

  const w = decision.write
  const { error: uErr } = await db.from('subscription_run').update(w.run).eq('id', w.runId)
  if (uErr) return json({ error: `update subscription_run: ${uErr.message}` }, 500)

  return json({
    ok: true,
    subscriptionId,
    runId: w.runId,
    status: w.run.status,
    cancelledDate: w.run.cancelled_date,
    // The date the detail screen renders as "paid through". Returned because it
    // is derived here and the client would otherwise have to re-derive it or
    // wait for a refetch to find out what it just agreed to.
    endDate: w.run.end_date,
  })
})
