// send-reminders — the renewal reminder job (v28).
//
// Thin shell around a pure core, the same shape as run-detection: load rows,
// call dueReminders(), send, record. Every rule lives in _shared/reminders.ts
// where it is tested without a database (17 tests).
//
// WHY THE ADDRESS IS NOT READ FROM A TABLE
//
// The reminder address is `auth.users.email` and is never stored (v9): whatever
// address the account was created with, Google identity or email+password, with
// account linking resolving both to the same verified address. `profiles` has no
// email column on purpose, so there is nothing here that could drift from the
// address the user actually signs in with. It is read through the admin API,
// which is the only reader of auth.users in this codebase.
//
// WHAT "SENT" MEANS, AND WHY IT IS RECORDED PER DATE
//
// `subscription_run.last_reminded_for_date` holds the `next_expected_date` a
// reminder went out for. Not a boolean (last month's reminder would silence this
// month's) and not a timestamp (a renewal that moves would need extra
// bookkeeping to re-arm). Detection rewrites `next_expected_date` on every pass,
// so a shifted renewal re-arms the reminder by itself.
//
// It is written ONLY after the provider accepts the send. The failure mode that
// matters is a silent non-delivery that still marks itself done, which would
// skip the renewal entirely; a send recorded as unsent at worst repeats.

import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4'
import {
  chargeMoney,
  type ChargeMoneyRow,
  type DueReminder,
  dueReminders,
  moneyText,
  type ReminderRow,
  wantsEmail,
  whenText,
} from '../_shared/reminders.ts'

/** Constant-time compare, so a wrong secret cannot be narrowed by timing.
 *  Same helper as pluggy-sync and run-detection. */
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

const RESEND_ENDPOINT = 'https://api.resend.com/emails'
/** Resend's shared sender, which works with no verified domain. Overridable so
 *  verifying a domain later needs a secret change and no deploy. */
const DEFAULT_FROM = 'Signu <onboarding@resend.dev>'

async function loadCandidates(db: SupabaseClient, userId: string): Promise<ReminderRow[]> {
  // The join carries the user's assertions (nickname, remind_before_days,
  // ignored) because the core needs them to decide, and the inner join is what
  // scopes to this user — the same posture as run-detection's loaders.
  const { data, error } = await db
    .from('subscription_run')
    .select(
      'id, subscription_id, status, next_expected_date, last_reminded_for_date, billing_interval, ' +
        'subscription!inner(service_name, nickname, remind_before_days, ignored, user_id)',
    )
    .eq('subscription.user_id', userId)
  if (error) throw new Error(`select subscription_run: ${error.message}`)

  type Joined = {
    id: string
    subscription_id: string
    status: string
    next_expected_date: string | null
    last_reminded_for_date: string | null
    billing_interval: string
    subscription: {
      service_name: string
      nickname: string | null
      remind_before_days: number | null
      ignored: boolean
    }
  }

  const rows = (data ?? []) as unknown as Joined[]
  if (!rows.length) return []

  // The amount shown is the latest charge of the run, already resolved into the
  // account's currency (v26) — the same figure the app renders, so an email and
  // the screen cannot disagree about a price.
  // The account is reached through the transaction because that is a charge's
  // only route to one, and the embed is deliberately NOT `!inner`: a charge whose
  // raw backing was deleted has `transaction_id` null (v24's frozen region), and
  // an inner join would drop it from the email entirely rather than show it with
  // its stored currency.
  const { data: charges, error: cErr } = await db
    .from('charge')
    .select(
      'run_id, date, amount, currency, amount_in_account_currency, transaction(bank_account(currency))',
    )
    .in('run_id', rows.map((r) => r.id))
    .order('date', { ascending: false })
  if (cErr) throw new Error(`select charge: ${cErr.message}`)

  const latest = new Map<string, { amount: number | string | null; currency: string | null }>()
  for (const c of (charges ?? []) as Array<Record<string, unknown>>) {
    const runId = c.run_id as string
    if (latest.has(runId)) continue // ordered desc, so the first seen is the latest
    // PostgREST nests both to-one embeds as objects, and `transaction` is null for
    // an orphan -- both shapes verified against the live API, not assumed.
    const tx = c.transaction as { bank_account?: { currency?: string | null } | null } | null
    latest.set(runId, chargeMoney(c as unknown as ChargeMoneyRow, tx?.bank_account?.currency ?? null))
  }

  return rows.map((r) => ({
    run_id: r.id,
    subscription_id: r.subscription_id,
    service_name: r.subscription.service_name,
    nickname: r.subscription.nickname,
    remind_before_days: r.subscription.remind_before_days,
    ignored: r.subscription.ignored,
    status: r.status,
    next_expected_date: r.next_expected_date,
    last_reminded_for_date: r.last_reminded_for_date,
    billing_interval: r.billing_interval,
    amount: latest.get(r.id)?.amount ?? null,
    currency: latest.get(r.id)?.currency ?? null,
  }))
}

function subject(due: DueReminder[]): string {
  if (due.length === 1) {
    return `${due[0].displayName} renews ${whenText(due[0].daysUntil)}`
  }
  return `${due.length} subscriptions renewing soon`
}

/** Plain text alongside the HTML. A reminder that only renders in a rich client
 *  is a reminder some clients silently drop. */
function bodyText(due: DueReminder[]): string {
  const lines = due.map((d) => {
    const money = moneyText(d.amount, d.currency)
    const cost = money ? ` — ${money}${d.billingInterval === 'annual' ? '/year' : ''}` : ''
    return `• ${d.displayName} renews ${whenText(d.daysUntil)} (${d.dueDate})${cost}`
  })
  return [
    due.length === 1 ? 'A subscription is renewing:' : 'Subscriptions renewing:',
    '',
    ...lines,
    '',
    'Signu — you can turn a reminder off on the subscription’s detail screen.',
  ].join('\n')
}

function bodyHtml(due: DueReminder[]): string {
  const esc = (s: string) =>
    s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')
  const rows = due.map((d) => {
    const money = moneyText(d.amount, d.currency)
    const cost = money ? `${esc(money)}${d.billingInterval === 'annual' ? '/year' : ''}` : ''
    return `<tr>
      <td style="padding:10px 0;border-bottom:1px solid #e8e4dc">
        <strong>${esc(d.displayName)}</strong><br>
        <span style="color:#6f6a62;font-size:14px">renews ${esc(whenText(d.daysUntil))} · ${esc(d.dueDate)}</span>
      </td>
      <td style="padding:10px 0;border-bottom:1px solid #e8e4dc;text-align:right;white-space:nowrap">${cost}</td>
    </tr>`
  })
  return `<div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#f4f1ea;padding:24px">
  <div style="max-width:520px;margin:0 auto;background:#fbfaf7;border-radius:16px;padding:24px">
    <h1 style="font-size:20px;margin:0 0 16px">${due.length === 1 ? 'A subscription is renewing' : 'Subscriptions renewing'}</h1>
    <table style="width:100%;border-collapse:collapse">${rows.join('')}</table>
    <p style="color:#6f6a62;font-size:13px;margin:20px 0 0">
      You can turn a reminder off on the subscription’s detail screen.
    </p>
  </div>
</div>`
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

  const resendKey = Deno.env.get('RESEND_API_KEY')
  const from = Deno.env.get('REMINDER_FROM') ?? DEFAULT_FROM

  const db = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  )

  // Resolved once and passed in, so a replay against a fixed date is
  // reproducible — the same discipline as run-detection (v24).
  let today = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Sao_Paulo',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date())
  let onlyUserId: string | null = null
  // `dryRun` sends nothing and records nothing, so the selection can be
  // inspected on real data before any mail goes out.
  let dryRun = false
  try {
    const body = await req.json()
    onlyUserId = body?.userId ?? null
    if (typeof body?.today === 'string') today = body.today
    dryRun = body?.dryRun === true
  } catch {
    // no body is the normal cron case
  }

  if (!resendKey && !dryRun) {
    return json({ error: 'RESEND_API_KEY not configured' }, 500)
  }

  const { data: profiles, error: pErr } = onlyUserId
    ? await db.from('profiles').select('id, reminder_channels').eq('id', onlyUserId)
    : await db.from('profiles').select('id, reminder_channels')
  if (pErr) return json({ error: `select profiles: ${pErr.message}` }, 500)
  if (!profiles?.length) return json({ ok: true, note: 'no users', results: [] })

  const results: unknown[] = []
  const failures: unknown[] = []

  for (const p of profiles as Array<{ id: string; reminder_channels: string }>) {
    try {
      if (!wantsEmail(p.reminder_channels)) {
        results.push({ userId: p.id, skipped: `channel=${p.reminder_channels}` })
        continue
      }

      const candidates = await loadCandidates(db, p.id)
      const due = dueReminders(candidates, today)

      // Resolved before the empty check on a dry run, so `dryRun` can answer "who
      // would this reach?" even on a day nothing is due. That is the question the
      // free-tier restriction turns on -- delivery works only while this address is
      // the one that owns the Resend account -- and it should be answerable without
      // waiting for a renewal to come round.
      if (!due.length && !dryRun) {
        results.push({ userId: p.id, due: 0 })
        continue
      }

      const { data: userData, error: uErr } = await db.auth.admin.getUserById(p.id)
      if (uErr) throw new Error(`get user: ${uErr.message}`)
      const to = userData?.user?.email
      if (!to) throw new Error('no email on auth.users for this account')

      if (dryRun) {
        results.push({
          userId: p.id,
          to,
          // How many runs were even looked at, so "due: 0" distinguishes "no
          // subscriptions" from "subscriptions exist and none is due" without
          // needing a second query to find out.
          candidates: candidates.length,
          due: due.length,
          // Only when there is something to title. `subject([])` reads
          // "0 subscriptions renewing soon", which is not wrong so much as absurd.
          subject: due.length ? subject(due) : null,
          reminders: due,
          note: 'dry run — nothing sent, nothing recorded',
        })
        continue
      }

      const res = await fetch(RESEND_ENDPOINT, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${resendKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          from,
          to: [to],
          subject: subject(due),
          text: bodyText(due),
          html: bodyHtml(due),
        }),
      })

      const payload = await res.json().catch(() => ({}))
      if (!res.ok) {
        // Surfaced verbatim rather than summarised: on the free tier the
        // informative failure is "you can only send to your own address until a
        // domain is verified", and paraphrasing it would hide the fix.
        throw new Error(`resend ${res.status}: ${JSON.stringify(payload)}`)
      }

      // Only now. A send recorded before it succeeded would skip the renewal.
      // One statement per run because each carries its own date.
      for (const d of due) {
        const { error: uErr2 } = await db
          .from('subscription_run')
          .update({ last_reminded_for_date: d.dueDate })
          .eq('id', d.runId)
        if (uErr2) throw new Error(`record reminder for run ${d.runId}: ${uErr2.message}`)
      }

      results.push({ userId: p.id, to, due: due.length, providerId: payload?.id ?? null })
    } catch (err) {
      failures.push({ userId: p.id, error: err instanceof Error ? err.message : String(err) })
    }
  }

  // 207 when some users failed: a 200 would let a broken account hide behind a
  // working one, which is the reporting failure the sync contract calls out.
  return json({ ok: failures.length === 0, today, dryRun, results, failures }, failures.length ? 207 : 200)
})
