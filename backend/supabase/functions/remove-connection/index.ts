
import {
  type AttrCharge,
  attributedSubscriptionIds,
  type AttrRun,
  latestChargePerRun,
  latestRunPerSubscription,
} from '../_shared/actions.ts'
import { json, ownedConnection, resolveCaller, serviceClient } from '../_shared/auth.ts'

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json({ error: 'POST only' }, 405)

  const who = await resolveCaller(req)
  if (!who.ok) return json({ error: who.error }, who.status)

  let connectionId: string | null = null
  let deleteHistory: boolean | null = null
  try {
    const body = await req.json()
    connectionId = typeof body?.connectionId === 'string' ? body.connectionId : null
    deleteHistory = typeof body?.deleteHistory === 'boolean' ? body.deleteHistory : null
  } catch {
    return json({ error: 'body must be JSON' }, 400)
  }
  if (!connectionId) return json({ error: 'connectionId is required' }, 400)
  if (deleteHistory === null) return json({ error: 'deleteHistory must be stated, true or false' }, 400)

  const db = serviceClient()

  const owned = await ownedConnection<{ id: string }>(db, who.caller, connectionId, 'id')
  if (!owned.ok) return json({ error: owned.error }, owned.status)


  const { data: accounts, error: aErr } = await db
    .from('bank_account')
    .select('id')
    .eq('connection_id', connectionId)
  if (aErr) return json({ error: `select bank_account: ${aErr.message}` }, 500)
  const accountIds = (accounts ?? []).map((a: { id: string }) => a.id)

  const { data: subs, error: sErr } = await db
    .from('subscription')
    .select('id')
    .eq('user_id', who.caller.id)
  if (sErr) return json({ error: `select subscription: ${sErr.message}` }, 500)
  const subscriptionIds = (subs ?? []).map((s: { id: string }) => s.id)

  let attributed: string[] = []
  if (subscriptionIds.length && accountIds.length) {
    const { data: runRows, error: rErr } = await db
      .from('subscription_run')
      .select('id, subscription_id, start_date')
      .in('subscription_id', subscriptionIds)
    if (rErr) return json({ error: `select subscription_run: ${rErr.message}` }, 500)
    const runs = (runRows ?? []) as AttrRun[]

    const latestRunIds = [...latestRunPerSubscription(runs).values()].map((r) => r.id)
    let charges: AttrCharge[] = []
    if (latestRunIds.length) {
      const { data: chargeRows, error: cErr } = await db
        .from('charge')
        .select('id, run_id, date, transaction_id')
        .in('run_id', latestRunIds)
      if (cErr) return json({ error: `select charge: ${cErr.message}` }, 500)
      charges = (chargeRows ?? []) as AttrCharge[]
    }

    // Only the transactions a latest charge actually points at — at most one per
    // subscription, rather than every transaction the bank ever produced.
    const txIds = [...latestChargePerRun(charges).values()]
      .map((c) => c.transaction_id)
      .filter((id): id is string => id !== null)

    const transactionAccount: Record<string, string> = {}
    if (txIds.length) {
      const { data: txRows, error: tErr } = await db
        .from('transaction')
        .select('id, account_id')
        .in('id', txIds)
      if (tErr) return json({ error: `select transaction: ${tErr.message}` }, 500)
      for (const t of (txRows ?? []) as Array<{ id: string; account_id: string }>) {
        transactionAccount[t.id] = t.account_id
      }
    }

    attributed = attributedSubscriptionIds({
      subscriptionIds,
      runs,
      charges,
      transactionAccount,
      connectionAccountIds: accountIds,
    })
  }

  // ---- the deletes, in the one order that works ----

  let deletedSubscriptions = 0
  if (deleteHistory && attributed.length) {
    // Cascades to subscription_run and to charge. The `user_id` predicate is
    // redundant with where these ids came from and is here anyway: it is the
    // last line before a DELETE that RLS is not standing behind.
    const { error: dErr } = await db
      .from('subscription')
      .delete()
      .in('id', attributed)
      .eq('user_id', who.caller.id)
    if (dErr) return json({ error: `delete subscription: ${dErr.message}` }, 500)
    deletedSubscriptions = attributed.length
  }

  // Cascades to bank_account and transaction; surviving charges keep their date,
  // amount, currency and card_label with `transaction_id` set to NULL.
  const { error: cErr } = await db
    .from('connection')
    .delete()
    .eq('id', connectionId)
    .eq('user_id', who.caller.id)
  if (cErr) return json({ error: `delete connection: ${cErr.message}` }, 500)

  return json({
    ok: true,
    connectionId,
    deleteHistory,
    // The number the sheet promised. Reported back so a mismatch with what the
    // user was shown is visible in a response rather than inferred later from a
    // list that got shorter than expected.
    attributed: attributed.length,
    deletedSubscriptions,
    keptSubscriptions: deleteHistory ? 0 : attributed.length,
  })
})
