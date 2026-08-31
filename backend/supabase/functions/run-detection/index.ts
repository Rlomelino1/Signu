
import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4'
import { detect, type EngineInput, type TxRow } from '../_shared/detection.ts'
import { detectionApplyDecision } from '../_shared/sync.ts'
import { writeApiKey } from '../_shared/auth.ts'

async function secretsMatch(given: string, expected: string): Promise<boolean> {
  const enc = new TextEncoder()
  const [a, b] = await Promise.all([
    crypto.subtle.digest('SHA-256', enc.encode(given)),
    crypto.subtle.digest('SHA-256', enc.encode(expected)),
  ])
  const va = new Uint8Array(a)
  const vb = new Uint8Array(b)
  let diff = 0
  for (let i = 0; i < va.length; i++) diff |= va[i] ^ vb[i]
  return diff === 0
}

async function loadUser(db: SupabaseClient, userId: string): Promise<EngineInput['rows']> {
  const { data, error } = await db
    .from('transaction')
    .select(
      'id, provider_tx_id, account_id, status, type, date, amount, currency, ' +
        'amount_in_account_currency, raw_description, normalized_merchant, withdrawn_at, installment_number, ' +
        'total_installments, fee_type_additional_info, provider_merchant_name, ' +
        'provider_merchant_cnpj, bank_account!inner(connection!inner(user_id))',
    )
    .eq('bank_account.connection.user_id', userId)
  if (error) throw new Error(`load transactions: ${error.message}`)
  return (data ?? []) as unknown as TxRow[]
}

Deno.serve(async (req: Request) => {
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body, null, 2), {
      status,
      headers: { 'Content-Type': 'application/json' },
    })

  if (req.method !== 'POST') return json({ error: 'POST only' }, 405)

  const expected = Deno.env.get('SYNC_SECRET')
  if (!expected) return json({ error: 'SYNC_SECRET not configured' }, 500)
  if (!(await secretsMatch(req.headers.get('x-sync-secret') ?? '', expected))) {
    return json({ error: 'forbidden' }, 403)
  }

  const db = createClient(
    Deno.env.get('SUPABASE_URL')!,
    writeApiKey(),
    { auth: { persistSession: false } },
  )

  let today = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Sao_Paulo',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date())
  const body = await req.json().catch(() => null)
  const onlyUserId: string | null = body?.userId ?? null
  if (typeof body?.today === 'string') today = body.today
  // Operator replay only: skips the total-wipe guard for a deliberate teardown.
  const allowWipe = body?.allowWipe === true

  const { data: profiles, error: pErr } = onlyUserId
    ? await db.from('profiles').select('id').eq('id', onlyUserId)
    : await db.from('profiles').select('id')
  if (pErr) return json({ error: `select profiles: ${pErr.message}` }, 500)
  if (!profiles?.length) return json({ ok: true, note: 'no users', results: [] })

  const { data: catalogRows, error: catErr } = await db
    .from('brand_catalog')
    .select('brand_name, patterns, subscription_only, kind')
  if (catErr) return json({ error: `select brand_catalog: ${catErr.message}` }, 500)
  const catalog = (catalogRows ?? []) as unknown as EngineInput['catalog']

  const results: unknown[] = []
  const failures: unknown[] = []

  for (const p of profiles) {
    try {
      const rows = await loadUser(db, p.id)

      const [
        { data: subs, error: sErr },
        { data: runs, error: rErr },
        { data: accounts, error: aErrAcc },
      ] = await Promise.all([
        db.from('subscription').select('id, dedupe_key, merchant_key, service_name, identification, ignored').eq('user_id', p.id),
        db.from('subscription_run').select('id, subscription_id, start_date, end_date, billing_interval, status, detected_by, cancelled_date, next_expected_date, subscription!inner(user_id)').eq('subscription.user_id', p.id),
        db.from('bank_account').select('id, brand, last4, connection!inner(user_id)').eq('connection.user_id', p.id),
      ])
      if (sErr) throw new Error(`select subscription: ${sErr.message}`)
      if (rErr) throw new Error(`select subscription_run: ${rErr.message}`)
      if (aErrAcc) throw new Error(`select bank_account: ${aErrAcc.message}`)

      const runIds = (runs ?? []).map((r: { id: string }) => r.id)
      let charges: unknown[] = []
      if (runIds.length) {
        const { data: ch, error: cErr } = await db
          .from('charge')
          .select('id, run_id, transaction_id, date, amount, currency, amount_in_account_currency, card_label')
          .in('run_id', runIds)
        if (cErr) throw new Error(`select charge: ${cErr.message}`)
        charges = ch ?? []
      }

      const desired = detect({
        today,
        rows,
        subscriptions: (subs ?? []) as EngineInput['subscriptions'],
        runs: (runs ?? []) as unknown as EngineInput['runs'],
        charges: charges as EngineInput['charges'],
        accounts: (accounts ?? []) as unknown as EngineInput['accounts'],
        catalog,
      })

      if (!allowWipe) {
        const verdict = detectionApplyDecision(desired.subscriptions.length, (runs ?? []).length)
        if (verdict.kind === 'refuse') throw new Error(verdict.reason)
      }

      const { data: applied, error: aErr } = await db.rpc('apply_detection', {
        p_user_id: p.id,
        p_desired: {
          subscriptions: desired.subscriptions,
          delete_run_ids: desired.delete_run_ids,
        },
      })
      if (aErr) throw new Error(`apply_detection: ${aErr.message}`)

      results.push({
        userId: p.id,
        today,
        diagnostics: desired.diagnostics,
        subscriptions: desired.subscriptions.length,
        applied,
      })
    } catch (e) {
      failures.push({ userId: p.id, error: e instanceof Error ? e.message : String(e) })
    }
  }

  return json({ ok: failures.length === 0, results, failures }, failures.length ? 207 : 200)
})
