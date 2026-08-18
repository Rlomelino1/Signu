// pluggy-sync — raw-chain sync. Implements the v20 Pluggy reality contract.
//
// Poll-only by design: there is no webhook endpoint, because Pluggy has no
// `updatedAtFrom` parameter, so a full re-scan is the ONLY mechanism that
// observes updates (a PENDING->POSTED transition, a billId arriving). See the
// v20 changelog. That makes the daily re-scan the baseline rather than a
// fallback, which is why missing a webhook costs nothing.
//
// This function owns the RAW chain only: connection, bank_account, transaction.
// It never writes subscription / subscription_run / charge. Detection is a
// separate function on the replayability doctrine — a detection bug must not be
// able to fail a sync, and detection must be re-runnable over stored history
// without touching Pluggy (which is the recovery path for withdrawn rows).
//
// Invocation is guarded by a shared secret, not a JWT: this URL is publicly
// addressable once deployed and there is no user session behind a cron call.

import {
  createClient,
  type SupabaseClient,
} from 'https://esm.sh/@supabase/supabase-js@2.45.4'
import { accountType, lastFour } from '../_shared/accounts.ts'

const PLUGGY = 'https://api.pluggy.ai'

// Item history is 365 days (docs/item.md: "up to the last 365 days"). Re-scan
// the whole window every run; ~6 requests per account against a 360 req/min
// limit, so the cost is trivial and the completeness is total.
const WINDOW_DAYS = 365

// Pagination guard. /v2/transactions is fixed at 500 rows per page, so this is
// 20k rows per account. Exceeding it is reported, never silent — a quiet stop
// reads as "that is all of them".
const MAX_PAGES = 40

// ------------------------------------------------------------------- API shapes
//
// Only the fields this function reads, typed so a misspelling is a check-time
// error rather than a silent null in the database. Every one was confirmed
// present on a live payload — `marketingName`, `creditData.brand` and
// `autoSyncDisabledAt` are not all in the published reference.

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
  /** Present only when the transaction currency differs from the account's.
   *  Not derivable from `amount`: the implied FX rate moves per transaction. */
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
  /** When PLUGGY last refreshed this item from the institution. Not our clock, and
   *  the honest half of a freshness claim (v65). */
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

// ---------------------------------------------------------------- date handling
//
// transaction.date is a `date` column but Pluggy sends ISO timestamps in UTC,
// and its own docs say you must convert to GMT-3 to read them as Brazilian
// time. 37 of 258 rows in the v20 probe carried a UTC time of 00:00-02:59,
// every one of which lands on the PREVIOUS day once converted — so naive
// truncation puts ~14% of the ledger on the wrong date, perturbing exactly the
// gap arithmetic R1/R3 depend on (28-33d bands, +/-3d windows).
//
// Named IANA zone, not a fixed -3: Brazil abolished DST in 2019, but history
// before that was GMT-2 in summer and the zone handles it.
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

// --------------------------------------------------------------------- helpers

/** Case + whitespace only. v21 forbids stripping trailing digits: a
 *  digit-stripping pass merged two unrelated `LS...` transactions and merged
 *  nothing else. Fragmentation is by descriptor VARIANT, which string surgery
 *  cannot fix and merchant_key (CNPJ-first) solves at detection time. */
function normalizeMerchant(raw: string): string {
  return raw.replace(/\s+/g, ' ').trim().toUpperCase()
}

/** businessName arrives as '' on 4 of 66 card rows carrying a merchant object.
 *  Coerced so `is not null` means what it says (v21). */
function blankToNull(v: unknown): string | null {
  return typeof v === 'string' && v.trim() !== '' ? v : null
}

/** Compares SHA-256 digests rather than the raw strings, so neither the content
 *  nor the LENGTH of the expected secret leaks through timing. Fixed-width
 *  inputs are what make the constant-time loop actually constant-time. */
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

// ------------------------------------------------------------------- mappings
//
// Two traps here, both easy to get backwards, because the CHECK constraints are
// inconsistent with each other:
//   transaction.status  CHECK ('pending','posted')   -- lowercase
//   transaction.type    CHECK ('DEBIT','CREDIT')     -- uppercase
// Pluggy sends BOTH uppercase, so status is lowercased and type passes through.

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

/** Both mappings now live in `_shared/accounts.ts` (v53), against this file's own
 *  precedent of keeping private copies. The reason is specific: the duplicate check
 *  in `register-connection` compares the accounts of a new item against the rows
 *  THIS function wrote, so the two must agree about `type` and `last4`. A drifting
 *  copy there fails open and silently — the check would simply stop matching. */

/** Pluggy item status -> connection.status
 *  CHECK ('active','needs_action','expired','disconnected').
 *  Conservative: anything needing the user becomes needs_action rather than
 *  being optimistically called active. */
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
      // Auto-sync retries OUTDATED up to 5 times before dropping the item;
      // it is a transient execution failure, not a user-actionable state.
      return String(item?.executionStatus ?? '').toUpperCase() === 'SUCCESS'
        ? 'active'
        : 'needs_action'
    default:
      return 'needs_action'
  }
}

// ----------------------------------------------------------------- transactions

/** Page /v2/transactions to exhaustion for one account. */
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

    // `next` is documented as a bare query string ("?accountId=...&after=<c>")
    // but has also been seen as a full URL. URL-parse handles both; passing the
    // whole string through as `after` yields 400 Invalid cursor.
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
    // Stored exactly as Pluggy sends it, sign included. Card dialect is
    // positive = new charge; bank dialect is negative = outflow. Detection
    // keys direction off `type`, never off sign, and compares magnitudes.
    amount: t.amount,
    currency: String(t.currencyCode ?? '').toUpperCase(),
    // Stored exactly as sent: null when the transaction is already in the
    // account's currency, where `amount` IS the account-currency figure. Both
    // are kept because neither reconstructs the other -- the implied FX rate
    // moves per transaction -- and because R1 needs the stable transaction
    // amount while totals need this one (v26).
    amount_in_account_currency: t.amountInAccountCurrency ?? null,
    raw_description: raw,
    normalized_merchant: normalizeMerchant(raw),
    provider_category: t.category ?? null,

    // ---- v20 additive columns ----
    // A row present in the feed is by definition not withdrawn. Stated
    // explicitly rather than left alone, so a row that reappears under the same
    // provider_tx_id is un-withdrawn by the next re-scan.
    withdrawn_at: null,
    installment_number: ccm.installmentNumber ?? null,
    total_installments: ccm.totalInstallments ?? null,
    purchase_date: toSaoPauloDate(ccm.purchaseDate),
    // Stored RAW, including the 'NA' sentinel. Interpretation is a denylist
    // living in detection, because this field is populated on 164/165 card rows
    // and only its VALUE discriminates — never its presence (v21).
    fee_type_additional_info: ccm.feeTypeAdditionalInfo ?? null,
    // From businessName, NOT `name`: `name` is present on 5 of 258 rows (v21).
    provider_merchant_name: blankToNull(merchant.businessName),
    provider_merchant_cnpj: blankToNull(merchant.cnpj),
  }
}

// ------------------------------------------------------------------ per-account

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

  // Upsert in chunks. UNIQUE (account_id, provider_tx_id) makes this idempotent,
  // which is what lets the whole window be re-scanned every run.
  for (let i = 0; i < mapped.length; i += 500) {
    const { error } = await db
      .from('transaction')
      .upsert(mapped.slice(i, i + 500), { onConflict: 'account_id,provider_tx_id' })
    if (error) throw new SyncError(`upsert transaction: ${error.message}`)
  }

  // ---- withdrawn detection ----
  // Pluggy's id is a content hash, not a surrogate key: a hash-breaking content
  // change OR a 1-3 day bank drop deletes the row and creates a new one under a
  // NEW id. We never hard-delete — the row is evidence for a replayable
  // interpreted chain, and detection filters `withdrawn_at is null`.
  //
  // Scoped to `date >= windowStart` on purpose. Comparing against every stored
  // row would withdraw the entire pre-window history on every run, since it is
  // absent from a 365-day response by construction.
  let withdrawn = 0
  if (!truncated) {
    const seen = new Set(mapped.map((m) => m.provider_tx_id))
    const { data: held, error } = await db
      .from('transaction')
      .select('id, provider_tx_id')
      .eq('account_id', accountRowId)
      .gte('date', windowStart)
      .is('withdrawn_at', null)
    if (error) throw new SyncError(`select held transactions: ${error.message}`)

    const gone = (held ?? []).filter((h) => !seen.has(h.provider_tx_id))
    if (gone.length) {
      const { error: wErr } = await db
        .from('transaction')
        .update({ withdrawn_at: new Date().toISOString() })
        .in('id', gone.map((g) => g.id))
      if (wErr) throw new SyncError(`mark withdrawn: ${wErr.message}`)
      withdrawn = gone.length
    }
  }

  return { fetched: mapped.length, pages, truncated, withdrawn }
}

// --------------------------------------------------------------- per-connection

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
      // Not modelled by bank_account's CHECK. Reported, never invented.
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
          // brand is documented "card network; null for non-cards" — it lives
          // under creditData, which is absent entirely on checking accounts.
          brand: acct.creditData?.brand ?? null,
          last4: lastFour(acct.number),
          // The unit for transaction.amount_in_account_currency. Without it
          // "account currency" would be an assumption rather than a fact (v26).
          currency: acct.currencyCode ? String(acct.currencyCode).toUpperCase() : null,
          // marketingName is the fuller label where present ('… (Conta
          // Pré-paga)'); `name` alone is 'platinum' on the card, which reads as
          // a tier rather than an account. Column is sync-owned and overwritable.
          official_name: acct.marketingName ?? acct.name ?? null,
          // nickname is user-owned and deliberately absent from this payload:
          // naming it here at all would risk a future upsert clobbering it.
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
      // OUR clock: when this read finished. Kept as-is -- it is the honest answer
      // to "when did Signu last look", which is a different question from "how old
      // is the data" and is what a stalled cron shows up in.
      last_synced_at: new Date().toISOString(),
      // PLUGGY's clock: when the provider last refreshed the item from the
      // institution. Copied through, never computed, and null rather than
      // substituted when the response omits it (v65).
      provider_updated_at: item.lastUpdatedAt ?? null,
      last_sync_error: null,
      institution_name: item.connector?.name ?? conn.institution_name,
    })
    .eq('id', conn.id)
  if (cErr) throw new SyncError(`update connection: ${cErr.message}`)

  return {
    connectionId: conn.id,
    itemStatus: `${item.status}/${item.executionStatus}`,
    // Both surfaced because a silent drop from auto-sync is a real failure mode:
    // five consecutive failures and Pluggy stops updating the item with no
    // further event. nextAutoSyncAt going null, or autoSyncDisabledAt becoming
    // non-null, is the only warning. autoSyncDisabledAt is undocumented — it
    // does not appear in the API reference and was found on a live payload.
    nextAutoSyncAt: item.nextAutoSyncAt ?? null,
    autoSyncDisabledAt: item.autoSyncDisabledAt ?? null,
    accounts: perAccount,
    skippedAccounts: skipped,
  }
}

// --------------------------------------------------------------------- handler

Deno.serve(async (req: Request) => {
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body, null, 2), {
      status,
      headers: { 'Content-Type': 'application/json' },
    })

  if (req.method !== 'POST') return json({ error: 'POST only' }, 405)

  // Shared-secret gate. This URL is publicly addressable and a cron caller has
  // no user session, so there is no JWT to verify (verify_jwt = false in
  // config.toml). Constant-time compare.
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
    // Service role: all writes go through Edge Functions and bypass RLS, so
    // sync never pays the RLS join cost (Migration #1 posture).
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  )

  // Optional narrowing, for replaying one connection without touching others.
  let onlyConnectionId: string | null = null
  try {
    const body = await req.json()
    onlyConnectionId = body?.connectionId ?? null
  } catch {
    // no body is the normal cron case
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
    // Credentials wrong or Pluggy down: fail the whole run cleanly rather than
    // letting the throw escape as an opaque 500 with no body.
    return json({ error: e instanceof Error ? e.message : String(e) }, 502)
  }
  if (!apiKey) return json({ error: 'Pluggy /auth returned no apiKey' }, 502)

  const results: Awaited<ReturnType<typeof syncConnection>>[] = []
  const failures: { connectionId: string; error: string }[] = []

  for (const conn of connections) {
    try {
      results.push(await syncConnection(db, conn, apiKey))
    } catch (e) {
      // One bad connection must not abort the others, and the reason has to
      // land somewhere durable rather than only in the response.
      const message = e instanceof Error ? e.message : String(e)
      failures.push({ connectionId: conn.id, error: message })
      await db
        .from('connection')
        .update({ last_sync_error: message.slice(0, 1000) })
        .eq('id', conn.id)
    }
  }

  // Chain into detection rather than scheduling it separately: an independently
  // scheduled detection run can wake mid-sync and interpret a half-written raw
  // chain. It would self-heal on the next run ("re-runs repair"), but producing
  // knowingly-wrong state in the meantime is avoidable. Both functions stay
  // independently invokable, which is what replay needs.
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
