
import { confirmation, type ConfirmRun, type ConfirmSubscription, type Interval } from '../_shared/actions.ts'
import { json, resolveCaller, serviceClient } from '../_shared/auth.ts'

type Row = ConfirmRun & {
  subscription: { id: string; identification: ConfirmSubscription['identification'] }
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json({ error: 'POST only' }, 405)

  const who = await resolveCaller(req)
  if (!who.ok) return json({ error: who.error }, who.status)

  let runId: string | null = null
  let interval: Interval | null = null
  try {
    const body = await req.json()
    runId = typeof body?.runId === 'string' ? body.runId : null
    const raw = body?.billingInterval
    if (raw === 'monthly' || raw === 'annual') interval = raw
    else if (raw !== undefined && raw !== null) {
      return json({ error: `billingInterval must be monthly or annual, got ${JSON.stringify(raw)}` }, 400)
    }
  } catch {
    return json({ error: 'body must be JSON' }, 400)
  }
  if (!runId) return json({ error: 'runId is required' }, 400)

  const db = serviceClient()

  // Ownership rides on the inner join, because a run has no `user_id` of its
  // own: it is the caller's iff its subscription is. Service role bypasses RLS,
  // so this predicate is the whole of the scoping — see _shared/auth.ts.
  const { data, error } = await db
    .from('subscription_run')
    .select(
      'id, subscription_id, status, detected_by, billing_interval, ' +
        'subscription!inner(id, identification, user_id)',
    )
    .eq('id', runId)
    .eq('subscription.user_id', who.caller.id)
    .maybeSingle()
  if (error) return json({ error: `select subscription_run: ${error.message}` }, 500)
  if (!data) return json({ error: 'not found' }, 404)

  const row = data as unknown as Row
  const decision = confirmation(row, row.subscription, interval)

  if (decision.kind === 'refuse') return json({ error: decision.reason }, decision.status)
  if (decision.kind === 'noop') return json({ ok: true, runId, noop: true, reason: decision.reason })

  const w = decision.write

  // The run first, deliberately. There is no transaction across two PostgREST
  // calls, so one of them can land alone — and if it is going to, it should be
  // the one that matters. A confirmed run with `identification` still 'auto'
  // tracks correctly and is repaired by the next tap; the reverse pair would
  // claim the user confirmed something that is still sitting in review.
  const { error: rErr } = await db.from('subscription_run').update(w.run).eq('id', w.runId)
  if (rErr) return json({ error: `update subscription_run: ${rErr.message}` }, 500)

  if (w.subscription) {
    const { error: sErr } = await db
      .from('subscription')
      .update(w.subscription)
      .eq('id', w.subscriptionId)
    if (sErr) return json({ error: `update subscription: ${sErr.message}` }, 500)
  }

  return json({
    ok: true,
    runId: w.runId,
    subscriptionId: w.subscriptionId,
    status: w.run.status,
    billingInterval: w.run.billing_interval ?? row.billing_interval,
    // Null when the subscription was already `user_renamed` — reported rather
    // than hidden, so a caller can see that the stronger assertion stood.
    identification: w.subscription?.identification ?? null,
  })
})
