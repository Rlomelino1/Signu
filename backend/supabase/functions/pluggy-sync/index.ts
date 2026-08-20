
import {
  createClient,
  type SupabaseClient,
} from 'https://esm.sh/@supabase/supabase-js@2.45.4'
import { accountType, lastFour } from '../_shared/accounts.ts'
import { withdrawalDecision } from '../_shared/sync.ts'
import { writeApiKey } from '../_shared/auth.ts'

const PLUGGY = 'https://api.pluggy.ai'

const WINDOW_DAYS = 365

const MAX_PAGES = 40


interface PluggyCreditCardMetadata {
  installmentNumber?: number | null
  totalInstallments?: number | null
  purchaseDate?: string | null
  feeTypeAdditionalInfo?: string | null
}

interface PluggyMerchant {
  businessName?: string | null
  cnpj?: string | null
}

interface PluggyTransaction {
  id: string
  status?: string
  type?: string
  date: string
  amount: number
  amountInAccountCurrency?: number | null
  currencyCode?: string
  description?: string
  category?: string | null
  creditCardMetadata?: PluggyCreditCardMetadata | null
  merchant?: PluggyMerchant | null
}

interface PluggyAccount {
  id: string
  type?: string
  subtype?: string
  currencyCode?: string | null
  name?: string | null
  marketingName?: string | null
  number?: string | null
  creditData?: { brand?: string | null } | null
}

interface PluggyItem {
  status?: string
  executionStatus?: string
  consentExpiresAt?: string | null
  lastUpdatedAt?: string | null
  nextAutoSyncAt?: string | null
  autoSyncDisabledAt?: string | null
  connector?: { name?: string | null } | null
}

interface ConnectionRow {
  id: string
  provider_connection_id: string
  institution_name: string
  status: string
}

interface TransactionRow {
  account_id: string
  provider_tx_id: string
  status: string
  type: string
  date: string
  amount: number
  currency: string
  amount_in_account_currency: number | null
  raw_description: string
  normalized_merchant: string
  provider_category: string | null
  withdrawn_at: string | null
  installment_number: number | null
  total_installments: number | null
  purchase_date: string | null
  fee_type_additional_info: string | null
  provider_merchant_name: string | null
  provider_merchant_cnpj: string | null
}

interface AccountResult {
  providerAccountId: string
  type: string
  fetched: number
  pages: number
  truncated: boolean
  withdrawn: number
}

const SP_PARTS = new Intl.DateTimeFormat('en-US', {
  timeZone: 'America/Sao_Paulo',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
})

function toSaoPauloDate(iso: string | null | undefined): string | null {
  if (!iso) return null
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return null
  const p: Record<string, string> = {}
  for (const { type, value } of SP_PARTS.formatToParts(d)) p[type] = value
  return `${p.year}-${p.month}-${p.day}`
}


function normalizeMerchant(raw: string): string {
  return raw.replace(/\s+/g, ' ').trim().toUpperCase()
}

function blankToNull(v: unknown): string | null {
  return typeof v === 'string' && v.trim() !== '' ? v : null
}

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

class SyncError extends Error {}

async function pluggy<T>(
  path: string,
  apiKey: string | null,
  init?: RequestInit,
): Promise<T> {
  const res = await fetch(`${PLUGGY}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...(apiKey ? { 'X-API-KEY': apiKey } : {}),
      ...(init?.headers ?? {}),
    },
  })
  if (!res.ok) {
    const body = await res.text()
    throw new SyncError(
      `Pluggy ${init?.method ?? 'GET'} ${path} -> ${res.status}: ${body.slice(0, 400)}`,
    )
  }
  return (await res.json()) as T
}


function mapTxStatus(s: unknown): string {
  const v = String(s ?? '').toUpperCase()
  if (v === 'POSTED') return 'posted'
  if (v === 'PENDING') return 'pending'
  throw new SyncError(`unmapped Pluggy transaction status: ${JSON.stringify(s)}`)
}

function mapTxType(t: unknown): string {
  const v = String(t ?? '').toUpperCase()
  if (v === 'DEBIT' || v === 'CREDIT') return v
  throw new SyncError(`unmapped Pluggy transaction type: ${JSON.stringify(t)}`)
}


function mapConnectionStatus(item: PluggyItem): string {
  const s = String(item?.status ?? '').toUpperCase()
  const consent = item?.consentExpiresAt ? new Date(item.consentExpiresAt) : null
  if (consent && consent.getTime() < Date.now()) return 'expired'
  switch (s) {
    case 'UPDATED':
    case 'UPDATING':
      return 'active'
    case 'WAITING_USER_INPUT':
    case 'WAITING_USER_ACTION':
    case 'LOGIN_ERROR':
      return 'needs_action'
    case 'OUTDATED':
      return String(item?.executionStatus ?? '').toUpperCase() === 'SUCCESS'
        ? 'active'
        : 'needs_action'
    default:
      return 'needs_action'
  }
}


async function fetchTransactions(
  accountId: string,
  apiKey: string,
  dateFrom: string,
): Promise<{ rows: PluggyTransaction[]; pages: number; truncated: boolean }> {
  const rows: PluggyTransaction[] = []
  let cursor: string | null = null
  let pages = 0

  for (;;) {
    const qs = new URLSearchParams({ accountId, dateFrom })
    if (cursor) qs.set('after', cursor)
    const page = await pluggy<{ results?: PluggyTransaction[]; next?: string | null }>(
      `/v2/transactions?${qs}`,
      apiKey,
    )
    rows.push(...(page.results ?? []))
    pages++

    const next = page.next
    if (!next) break

    const q = String(next).includes('?') ? String(next).split('?')[1] : String(next)
    cursor = new URLSearchParams(q).get('after')
    if (!cursor) break
    if (pages >= MAX_PAGES) return { rows, pages, truncated: true }
  }
  return { rows, pages, truncated: false }
}

function toTransactionRow(accountRowId: string, t: PluggyTransaction): TransactionRow {
  const date = toSaoPauloDate(t.date)
  if (!date) throw new SyncError(`transaction ${t.id} has unparseable date ${t.date}`)
  const ccm = t.creditCardMetadata ?? {}
  const merchant = t.merchant ?? {}
  const raw = String(t.description ?? '')

  return {
    account_id: accountRowId,
    provider_tx_id: String(t.id),
    status: mapTxStatus(t.status),
    type: mapTxType(t.type),
    date,
    amount: t.amount,
    currency: String(t.currencyCode ?? '').toUpperCase(),
    amount_in_account_currency: t.amountInAccountCurrency ?? null,
    raw_description: raw,
    normalized_merchant: normalizeMerchant(raw),
    provider_category: t.category ?? null,

    withdrawn_at: null,
    installment_number: ccm.installmentNumber ?? null,
    total_installments: ccm.totalInstallments ?? null,
    purchase_date: toSaoPauloDate(ccm.purchaseDate),
    fee_type_additional_info: ccm.feeTypeAdditionalInfo ?? null,
    provider_merchant_name: blankToNull(merchant.businessName),
    provider_merchant_cnpj: blankToNull(merchant.cnpj),
  }
}


async function syncAccount(
  db: SupabaseClient,
  accountRowId: string,
  providerAccountId: string,
  apiKey: string,
  windowStart: string,
) {
  const { rows, pages, truncated } = await fetchTransactions(
    providerAccountId,
    apiKey,
    windowStart,
  )

  const mapped = rows.map((t) => toTransactionRow(accountRowId, t))

  for (let i = 0; i < mapped.length; i += 500) {
    const { error } = await db
      .from('transaction')
      .upsert(mapped.slice(i, i + 500), { onConflict: 'account_id,provider_tx_id' })
    if (error) throw new SyncError(`upsert transaction: ${error.message}`)
  }

  let withdrawn = 0
  const { data: held, error: hErr } = await db
    .from('transaction')
    .select('id, provider_tx_id')
    .eq('account_id', accountRowId)
    .gte('date', windowStart)
    .is('withdrawn_at', null)
  if (hErr) throw new SyncError(`select held transactions: ${hErr.message}`)

  const verdict = withdrawalDecision(
    mapped.map((m) => m.provider_tx_id),
    held ?? [],
    truncated,
  )
  if (verdict.kind === 'refuse') {
    throw new SyncError(verdict.reason)
  }
  if (verdict.kind === 'withdraw') {
    const { error: wErr } = await db
      .from('transaction')
      .update({ withdrawn_at: new Date().toISOString() })
      .in('id', verdict.ids)
    if (wErr) throw new SyncError(`mark withdrawn: ${wErr.message}`)
    withdrawn = verdict.ids.length
  }

  return { fetched: mapped.length, pages, truncated, withdrawn }
}


async function syncConnection(db: SupabaseClient, conn: ConnectionRow, apiKey: string) {
  const windowStart = new Date(Date.now() - WINDOW_DAYS * 86_400_000)
    .toISOString()
    .slice(0, 10)

  const item = await pluggy<PluggyItem>(`/items/${conn.provider_connection_id}`, apiKey)

  const accounts = await pluggy<{ results?: PluggyAccount[] }>(
    `/accounts?${new URLSearchParams({ itemId: conn.provider_connection_id })}`,
    apiKey,
  )

  const perAccount: AccountResult[] = []
  const skipped: { providerAccountId: string; subtype?: string }[] = []

  for (const acct of accounts.results ?? []) {
    const type = accountType(acct.subtype)
    if (!type) {
      skipped.push({ providerAccountId: acct.id, subtype: acct.subtype })
      continue
    }

    const { data: accountRow, error } = await db
      .from('bank_account')
      .upsert(
        {
          connection_id: conn.id,
          provider_account_id: String(acct.id),
          type,
          brand: acct.creditData?.brand ?? null,
          last4: lastFour(acct.number),
          currency: acct.currencyCode ? String(acct.currencyCode).toUpperCase() : null,
          official_name: acct.marketingName ?? acct.name ?? null,
          status: 'active',
        },
        { onConflict: 'connection_id,provider_account_id' },
      )
      .select('id')
      .single()
    if (error) throw new SyncError(`upsert bank_account: ${error.message}`)

    const result = await syncAccount(
      db,
      accountRow.id,
      String(acct.id),
      apiKey,
      windowStart,
    )
    perAccount.push({ providerAccountId: acct.id, type, ...result })
  }

  const { error: cErr } = await db
    .from('connection')
    .update({
      status: mapConnectionStatus(item),
      consent_expires_at: item.consentExpiresAt
        ? String(item.consentExpiresAt).slice(0, 10)
        : null,
      last_synced_at: new Date().toISOString(),
      provider_updated_at: item.lastUpdatedAt ?? null,
      last_sync_error: null,
      institution_name: item.connector?.name ?? conn.institution_name,
    })
    .eq('id', conn.id)
  if (cErr) throw new SyncError(`update connection: ${cErr.message}`)

  return {
    connectionId: conn.id,
    itemStatus: `${item.status}/${item.executionStatus}`,
    nextAutoSyncAt: item.nextAutoSyncAt ?? null,
    autoSyncDisabledAt: item.autoSyncDisabledAt ?? null,
    accounts: perAccount,
    skippedAccounts: skipped,
  }
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

  const clientId = Deno.env.get('PLUGGY_CLIENT_ID')
  const clientSecret = Deno.env.get('PLUGGY_CLIENT_SECRET')
  if (!clientId || !clientSecret) {
    return json({ error: 'PLUGGY_CLIENT_ID / PLUGGY_CLIENT_SECRET not configured' }, 500)
  }

  const db = createClient(
    Deno.env.get('SUPABASE_URL')!,
    writeApiKey(),
    { auth: { persistSession: false } },
  )

  let onlyConnectionId: string | null = null
  try {
    const body = await req.json()
    onlyConnectionId = body?.connectionId ?? null
  } catch {
  }

  let query = db
    .from('connection')
    .select('id, provider_connection_id, institution_name, status')
    .in('status', ['active', 'needs_action'])
  if (onlyConnectionId) query = query.eq('id', onlyConnectionId)

  const { data: connections, error: connErr } = await query
  if (connErr) return json({ error: `select connection: ${connErr.message}` }, 500)
  if (!connections?.length) {
    return json({ ok: true, note: 'no syncable connections', results: [] })
  }

  let apiKey: string | undefined
  try {
    const auth = await pluggy<{ apiKey?: string }>('/auth', null, {
      method: 'POST',
      body: JSON.stringify({ clientId, clientSecret }),
    })
    apiKey = auth?.apiKey
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 502)
  }
  if (!apiKey) return json({ error: 'Pluggy /auth returned no apiKey' }, 502)

  const results: Awaited<ReturnType<typeof syncConnection>>[] = []
  const failures: { connectionId: string; error: string }[] = []

  for (const conn of connections) {
    try {
      results.push(await syncConnection(db, conn, apiKey))
    } catch (e) {
      const message = e instanceof Error ? e.message : String(e)
      failures.push({ connectionId: conn.id, error: message })
      await db
        .from('connection')
        .update({ last_sync_error: message.slice(0, 1000) })
        .eq('id', conn.id)
    }
  }

  let detection: unknown = 'not attempted'
  if (results.length) {
    try {
      const res = await fetch(
        `${Deno.env.get('SUPABASE_URL')}/functions/v1/run-detection`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'x-sync-secret': expected },
          body: JSON.stringify({ reason: 'post-sync' }),
        },
      )
      detection = res.status === 404
        ? 'run-detection not deployed yet — raw chain is synced, nothing interpreted'
        : { status: res.status }
    } catch (e) {
      detection = { error: e instanceof Error ? e.message : String(e) }
    }
  }

  return json(
    { ok: failures.length === 0, results, failures, detection },
    failures.length ? 207 : 200,
  )
})
