# Signu

A subscription tracker for Brazilian bank and card data. Charges are read from
Pluggy, interpreted by a pure detection engine, and rendered by a SwiftUI iOS app.

**The architecture in one sentence:** a **raw chain** that only ever mirrors the
provider (connection → bank_account → transaction) and an **interpreted chain** that
only ever holds our conclusions (subscription → subscription_run → charge) meet at
exactly one nullable foreign key, which is what makes detection fully replayable and
what lets a bank link be deleted without losing history.

This README is the only prose document besides the specification, and it carries the
invariants and "why not the obvious thing" reasoning that used to live in code comments.

---

## 1. What Signu is

The app answers one question — *what am I paying for every month, and when does the
next charge land?* — from bank and card transaction data rather than from receipts or
manual entry. Nothing is entered by hand: a charge arrives in the raw chain, the engine
decides whether a series of charges is a subscription, and the user confirms or dismisses
only the ones the engine is not sure about. The name is from *assinatura* — subscriptions
are things you signed.

Two properties shape every design decision in the repo:

- **The engine is pure and replayable.** Rules are functions over rows; `today` is a
  parameter, never a clock read. Given the same raw data, the same user assertions and
  the same date, a full replay and an incremental sync must converge on identical
  state.
- **The app never says more than the data supports.** A failed read is never rendered
  as an empty account, a predicted amount is always marked as predicted, and a number
  is never cropped.

---

## 2. Repo layout

```
backend/supabase/
  migrations/        19 versioned SQL files, forward-only, applied by `db push`
  functions/         nine Edge Functions plus _shared/
    _shared/         the pure, tested core — the ONLY code CI runs tests for
  templates/         the two auth emails (HTML, no comments — see §12)
  tests/             pgTAP suites
  config.toml        local CLI config; NOT pushed to production (see §13)
frontend/
  Signu/             the iOS app (SwiftUI, Swift 6 language mode):
                     Data/ (providers, row decoding, session, BankLabel),
                     DesignSystem/, Features/ (one directory per screen area)
  SignuTests/        unit tests (Swift Testing) · SignuUITests/ UI tests (XCTest)
docs/
  subscription-tracker-data-model.md   the specification — source of truth
  Screen-mockups/                      design references for the screen contracts
.github/workflows/ci.yml               three required checks + deploy-on-green
```

**`_shared/` is load-bearing, not organisational.** CI runs
`deno test backend/supabase/functions/_shared/` and nothing else, so a rule written inside
a function's `index.ts` cannot be gated by any check. Every decision that matters —
detection, reminder selection, the four user-asserted writes, withdrawal — lives in
`_shared/` as a pure function for that reason, and the Edge Functions above them are
load-decide-write shells.

The modules: `detection.ts` (the engine), `actions.ts` (the four writes the client is not
granted), `sync.ts` (the withdrawal decision), `reminders.ts`, `accounts.ts`, `money.ts`,
`dates.ts`, `auth.ts`, `pluggy.ts`. Note that **`deno check` names files individually in
CI while `deno test` is directory-scoped** — a new module is type-checked only once added
to that list, but picked up as a test suite for free.

---

## 3. The two chains, and the one place they meet

```
RAW CHAIN  (mirrors the provider; we never invent a row)
  connection ──< bank_account ──< transaction
                                      │
                          transaction_id (nullable, ON DELETE SET NULL)
                                      │
INTERPRETED CHAIN  (our conclusions; recomputed freely)
  subscription ──< subscription_run ──< charge
```

`charge.transaction_id` is **the bridge — the only place the two chains meet**, and it
is nullable on purpose. `ON DELETE SET NULL` is what makes *delete the bank link,
preserve the history* work: the charge survives the transaction's deletion,
self-described by columns duplicated onto it (date, amount, currency,
`amount_in_account_currency`, `card_label`).

**The frozen region.** A charge whose `transaction_id` is NULL has no raw backing, so it
is evidence rather than a derivation: never recomputed, never deleted, never re-parented.
Run identity is resolved by overlap on *live* transaction ids, excluding frozen charges
because they cannot be identity evidence. A run holding frozen charges is never deleted
even when nothing derives it any more — its basis is those charges.

**Why this makes replay safe.** The engine reads user assertions and never writes them;
it recomputes everything else. Recompute is therefore *reconcile*, not *rebuild*:

| Value | Status |
|---|---|
| run status where `detected_by = 'R1'` | derived — recomputed freely |
| run status where `detected_by IN ('R3','R4')` and stored status ≠ `possible` | asserted — the user confirmed a suggestion |
| `run.billing_interval` for a confirmed R4 | asserted — the confirm flow's authoritative write |
| `cancelled_date`, and `status = cancelled` | asserted |
| everything else | derived |

`transaction.withdrawn_at` is a soft delete: a row Pluggy stops returning is marked,
never removed, because raw rows are the evidence the interpreted chain rests on. A row
that reappears under the same `provider_tx_id` is un-withdrawn by the next scan.
Detection reads only `withdrawn_at is null`.

**Money** is compared exactly and always with its currency — never with a float epsilon.
`abs(6.46 - 6.45)` is `0.009999999999999787`, so an epsilon test makes amounts a cent
apart compare equal, which produced a false anchor on real data. Equality means currency
*and* cents, because one real merchant bills in two currencies. Comparison is centralised
in `money.ts`. A foreign charge carries both `amount` and `amount_in_account_currency`, so
`coalesce(second, first)` is always in the account's currency — that is what makes a total
a plain sum.

---

## 4. Detection rules R1–R5

**Doctrine: strict to create, generous to extend, re-runs repair.** Date granularity only;
all five rules are live.

| Rule | Mode | What it does |
|---|---|---|
| **R1 — anchor** | auto | Two charges, same merchant and the **same money**, one cadence apart (monthly = 28–33 days, ±3 day window). Continuation is amount-flexible, so a price rise never splits a run. |
| **R2 — backfill** | auto | On a confirmed run, claim an unclaimed same-merchant charge about one interval before the start, any amount, and correct `start_date`. |
| **R3 — cadence beats amount** | suggest-only | 3+ date-aligned charges with varying amounts. The user confirms or dismisses. |
| **R4 — catalog fast path** | suggest-only | One charge from a known subscription-only merchant ⇒ a `possible` run immediately. |
| **R5 — trailing charge on cancelled runs** | auto | A cancelled run may claim **at most one** charge dated after its `cancelled_date`. |

**R2 is not an event.** Doctrine says it fires "on confirmation", but under recompute
the confirmation state is preserved, so the precondition still holds, so the backfill
re-applies and reproduces the same `start_date`. Nothing needs to remember that R2 ran.

**R4 cannot state an interval honestly** — it creates a run from a single charge, so
cadence cannot be measured. The engine writes a provisional `monthly` (keeping the
column non-null and the prediction renderable) and the confirm flow asks the user
monthly-or-annual, which is the authoritative write. **R3 confirmations never ask:**
3+ aligned charges already *measure* the cadence, and asking would be the system
pretending not to know something it proved.

**R5, in full.** Claiming the trailing charge recomputes `end_date` (paid-through
extends one interval) and the timeline renders it as *"Charged · after cancellation"*.
If a **second** matching charge lands one cadence later, the trailing charge is
**un-claimed** — removed from the cancelled run, the original `end_date` restored — and
both charges anchor a **new** run through standard R1: a resubscription, not a
resurrection. Three decisions inside it are load-bearing:

- **The cap is measured from `cancelled_date`, never from the run's last claimed
  charge.** `cancelled_date` is an assertion; the last claimed charge is derived and
  moves the instant a trailing charge is claimed, so a cap anchored on it ratchets
  forward one charge per sync — the unlimited-swallowing bug wearing a limit.
- **Paid-through is derived every pass, never frozen.** It is `last claimed charge +
  one interval`, the same expression the cancel action writes, which is what lets the
  un-claim restore the original date without storing it. Freezing the stored value made
  paid-through a function of sync history rather than of the data.
- **The un-claim requires a real anchor.** "Both charges anchor a new run via standard
  R1" is a precondition: R1 needs the *same* money, so two post-cancellation charges at
  different amounts anchor nothing. Then the cap decides instead and the run keeps its
  one trailing charge, rather than un-claiming into charges that belong to no run.

R5 is **the only place a charge ever moves between runs**, which is why run identity is
matched by descending overlap: the cancelled run overlaps itself on many charges while
the new run overlaps it on one, so the cancelled run keeps its id.

### The candidate filter, and why each exclusion exists

Each came from a dry run against real data, and each is a false positive R1 or R3 would
otherwise have produced:

1. **Card-bill payments, card side** — a `CREDIT` on the card account.
2. **Fees** — excluded by the *value* of `fee_type_additional_info`, never its presence.
   The field is populated on nearly every card row with `'NA'` meaning "no fee"; testing
   `IS NOT NULL` excluded 146 of 258 rows and detected nothing.
3. **Instalments** — `installment_number` or `total_installments` disqualifies a row from
   anchoring *and* from continuing a run. A 12× purchase is identical in amount and one
   month apart: R1's exact trigger.
4. **Internal transfers** — paying the card bill from a connected checking account puts a
   `DEBIT` there matching a `CREDIT` on the card. The strongest false positive in real
   data: twelve consecutive months, same day, gaps 28–33, amounts spanning two orders of
   magnitude — R3's trigger executed perfectly, and confirming it would have tracked the
   user's entire card spend as one subscription. It needs *both* accounts connected.

**`merchant_key` is derived from CNPJ, not the descriptor.** One real merchant bills
under three different descriptors carrying the same CNPJ, so descriptor-keyed R1 saw no
pair and detected nothing. Across one card, 15 descriptors collapse to 5 CNPJs and no
descriptor ever maps to more than one CNPJ. Aggregator CNPJs (payment processors) are
the exception and must not unify unrelated merchants, or two unrelated purchases anchor
a phantom run.

**`dedupe_key` ordinals are assigned by ascending first-charge date**, never by
discovery order. Discovery-order numbering would let a recompute renumber runs and
silently re-attach a user's nickname, category and reminders to the wrong subscription.

**Predictions are marked.** `detected_by` powers expected-exact (R1) versus
expected-approximate (R3/R4); the UI renders approximate amounts with a tilde. One marker,
one meaning, and markers never stack.

---

## 5. The write boundary

The client may write **eight columns across three tables** and nothing else. This is a
Postgres permission boundary, not a convention — the app cannot violate it no matter
what the Swift code asks for.

```
revoke insert, update, delete  from anon, authenticated  -- on all seven tables
grant  select                  to authenticated          -- on all seven tables

grant update (display_name, reminder_channels) on profiles     to authenticated
grant update (avatar_path)                     on profiles     to authenticated
grant update (nickname)                        on bank_account to authenticated
grant update (nickname, category, ignored, remind_before_days)
                                               on subscription to authenticated
```

Everything else — every raw-chain row, every run, every charge — is written only by the
engine through `service_role`. **`subscription_run` has no client UPDATE grant at
all**, which is why confirming a suggestion and marking a run cancelled must be Edge
Functions rather than client writes, and why the four server-side writes exist:
confirm-suggestion, cancel-subscription, remove-connection, delete-account.

The rule behind the grant list: **sync-owned and user-owned columns never overlap.**
`institution_name` is sync-owned and never overwritten by the client; `nickname` is
user-owned and never touched by sync.

**A decision is a value, not a write.** Each of those four operations is a pure
function in `_shared/actions.ts` returning `write` / `noop` / `refuse`, so the
interesting cases can be tested as data rather than as mocked round trips. `noop` is
deliberately distinct from `refuse`: a second *Track it* tap after a dropped response is
a success from where the user sits, and answering 409 would make a retry look like a
failure.

`identification` (`auto` / `user_confirmed` / `user_renamed`) marks how a subscription got
its name; `user_renamed` freezes `service_name` against the engine's re-derivation.

---

## 6. Sync contract, freshness, and the shared secret

**Schedule.** `pluggy-sync` runs daily at **15:30 UTC** from `pg_cron`, re-scans 365 days
per account, and **chains directly into `run-detection`** on success — deliberately, since
an independently scheduled detection run can wake mid-sync and interpret a half-written
raw chain. Both stay independently invokable, which is what replay needs.
`send-reminders` runs at **16:30 UTC**.

**Every call to Pluggy's data endpoints is a GET** — `/items/{id}`, `/accounts`,
`/v2/transactions` — and the sync never issues `PATCH /items/{id}`. So it reads
whatever Pluggy already holds and cannot make Pluggy look again. The transactions
request sends `dateFrom` with no upper bound, so "today" is never excluded by the query.

**Three schedules are stacked and only the last is ours:** bank → aggregator (not
observable to us), aggregator → provider item (~24h, plan-level), provider → Signu
(daily, ours). So "the charge is on my card, why isn't it in the app?" is almost never
layer 3. Measured end-to-end latency from charge date to the row existing locally:
**median +1 day, max +8**. A charge taking more than four days to surface shows the
subscription as overdue while the money has already left the card — upstream latency made
visible, not a defect, and it self-heals next pass.

**Webhooks are deliberately not built.** They fire when *Pluggy* updates an item, and an
item can update with nothing new — so a webhook would deliver an empty event on time.
There is also no webhook signature, so authenticating a public endpoint would rest on a
bearer header that does not bind to the payload plus a hard-coded IP.

### What "Updated 3h ago" actually measures

`connection.last_synced_at` is **our** clock: `new Date()` when a sync finishes.
Rendering it as "Updated 3h ago" reads as a claim about the *data* while being a claim
about our *polling*, and the two diverge exactly when it matters — on a day the
provider's own sync fails, that label keeps saying "Updated 5m ago" about data frozen a
day earlier. A freshness label that cannot express staleness argues against the user's
own suspicion that something is behind.

So the sync also stores the provider's `lastUpdatedAt` as
`connection.provider_updated_at`, and the app reports the **older of the two**:

```
dataFreshAsOf = min(provider_updated_at, last_synced_at)
```

Both halves are load-bearing: the provider's stamp bounds freshness because our copy
shows its state as of our read, and ours bounds it because a stalled cron means we do not
*have* the provider's newer state. A null `provider_updated_at` falls back to
`last_synced_at` rather than inventing a freshness.

Across several banks the label reports the **oldest** connection — `max()` would let a
freshly added second bank paper over a first one that stopped updating days ago. A
connection that has never synced contributes nothing, and "Setting up" covers it.
Settings deliberately still says "Synced …" from `last_synced_at`, because there the
question really is *when did Signu last look* — what you want when diagnosing a stalled
cron rather than stale data.

### An empty provider response is refused, not obeyed

A revoked Open Finance consent returns **empty data, not an error**: HTTP 200, a
well-formed body, zero transactions — indistinguishable in shape from an account with
no activity. Read literally, every in-window row becomes "gone", so every one is marked
withdrawn; detection then finds no candidates and `delete_run_ids` removes every
non-frozen run, taking **run-level assertions** with it (confirmed suggestions,
cancellations) while subscription-level ones survive. Re-running does not repair that:
*re-runs repair* is a promise about derived state, and an assertion is not derived.

`withdrawalDecision` in `_shared/sync.ts` answers `withdraw` / `noop` / `refuse`:

- **Truncation is checked first** — a truncated feed can arrive empty too, and then
  incompleteness is the honest explanation rather than a revocation.
- **Empty feed + held rows in the window ⇒ refused.** Nothing is withdrawn, the
  connection fails with the held-row count in `last_sync_error`, and `last_synced_at`
  does not advance, so the freshness label cannot claim a read we rejected. Other
  connections still sync — one bad item must not abort the others.
- **Empty feed + nothing held ⇒ ordinary no-op** (a new account, a quiet window), or
  first sync on a fresh connection would report a failure.
- **Only a *fully* empty feed is refused.** One row where two hundred were held is
  trusted: no threshold separates a partial revocation from a quiet month without
  inventing a number.

### The shared secret must be rotated atomically

`pluggy-sync`, `run-detection` and `send-reminders` are called by machines, not users,
so they gate on a shared secret in the `x-sync-secret` header. That secret exists in
**two places that must change together**:

| Copy | Where | Read by |
|---|---|---|
| Edge Function secret | `SYNC_SECRET` in the functions' environment | the functions, to compare |
| Vault secret | `signu_sync_secret` in `vault.secrets` | the `pg_cron` trigger functions, to set the header |

**A mismatch fails silently and there is no error signal anywhere.** This is not
hypothetical: the Vault copy once held a four-character paste artefact, so every
scheduled POST was rejected at the gate with HTTP 403 for three days while cron
reported *"succeeded"* — because `net.http_post` returns the moment the request is
*queued*, so `cron.job_run_details` describes the queueing and reads identically for a
200, a 403 or a DNS failure. The HTTP status lands in `net._http_response` and nowhere
else, and pg_net prunes that within about a day. The app's own "Updated 2d ago" label
was the only thing that ever said otherwise.

Two guards came out of it, and neither closes the whole hole:

- The trigger functions **refuse to fire below a 32-character floor** — a floor, not a
  format assertion, chosen low enough that a future rotation to a shorter secret is not
  broken by it. It makes a *mangled paste* fail as a FAILED cron run on the first
  firing. It cannot catch a wrong-but-plausible value.
- `supabase secrets list` prints a **sha256 digest** of each deployed secret, so a
  local value can be confirmed against production by hashing it, never by printing it.
  That read-back is what covers the wrong-but-plausible case.

The cron HTTP timeout is **150 s**, matched to the platform's ceiling rather than to a
measurement: an Edge Function request is cut off around 150 s, so a POST outstanding then
means the function is gone and "timeout" is honest. The default 5 s was shorter than the
work — a sync chains detection and takes ~7 s — so it overwrote every real status with a
timeout. Both schedules use the same value: one rule, not two.

---

## 7. The nine Edge Functions

`verify_jwt = true` means the caller must present a signed-in user's JWT; `false` means
the caller is a machine and the function gates on `x-sync-secret` itself.

| Function | JWT | Who calls it, and what it does |
|---|---|---|
| `pluggy-sync` | **false** | `pg_cron`, 15:30 UTC. Mirrors accounts and transactions into the raw chain, decides withdrawal, then chains into `run-detection`. |
| `run-detection` | **false** | `pluggy-sync` (or a manual invoke). Loads the graph, runs the pure engine, applies the desired state in one atomic call. |
| `send-reminders` | **false** | `pg_cron`, 16:30 UTC. Selects due runs and sends through the mail provider. |
| `connect-token` | true | The app, to mint a Pluggy connect token for the widget. |
| `register-connection` | true | The app, after the widget succeeds: creates the `connection` row and refuses duplicates. |
| `confirm-suggestion` | true | The app — *Track it* on an R3/R4 suggestion. |
| `cancel-subscription` | true | The app — *Mark cancelled*. |
| `remove-connection` | true | The app — delete a bank link, preserving history via the frozen region. |
| `delete-account` | true | The app — delete the account and all its data. |

**`verify_jwt` must be declared for every machine-called function.** It is a
per-function deploy property read from `config.toml`, and the CLI's default is `true`. An
undeclared cron-called function is therefore one scoped `functions deploy <slug>` away
from silently 401ing every firing — while `pg_cron` still reports success, because it
reports the queueing of the request and not its status. All three of the `false` ones are
now declared; `send-reminders` was undeclared until v75 and had been running on a value
production happened to hold rather than one the repo stated. A blanket
`supabase functions deploy` reads each declared value, which is why it could never flip
them by accident — the exposure was the scoped path.

**How the six verify their caller, and why it survives a key migration.** `resolveCaller`
builds a client from an API key and calls `getUser()` with the caller's token, so a caller
holding only the project's public API key resolves to no user and gets 401 — that second
gate, not `verify_jwt`, is what makes the public key useless against these six. It prefers
an injected **publishable** key (`sb_publishable_…`, found by scanning
`SUPABASE_PUBLISHABLE_KEYS`, whose container shape is undocumented) and falls back to
`SUPABASE_ANON_KEY`, so disabling the legacy key cannot break authentication. It logs which
source it used, once per instance, so that can be confirmed from the function logs before
the legacy key is switched off. A secret key can never be selected: the scan matches only
the publishable prefix.

**Key selection prefers an explicitly set secret.** `SIGNU_PUBLISHABLE_KEY` and
`SIGNU_SECRET_KEY` are checked before the platform-injected `SUPABASE_PUBLISHABLE_KEYS` /
`SUPABASE_SECRET_KEYS`, which are checked before the legacy keys. The explicit pair exists
because the injected plurals are undocumented: their digests did not change across two
deploys spanning a key creation, so whether they carry usable client credentials at all is
unproven, and a migration cannot rest on an inference. Set them with
`supabase secrets set SIGNU_PUBLISHABLE_KEY=… SIGNU_SECRET_KEY=…` — the `SIGNU_` prefix is
required because Supabase reserves `SUPABASE_*` for its own injection. A user-set secret
also changes its digest in `supabase secrets list`, which makes arrival **verifiable**
rather than assumed. An explicit key of the wrong type is ignored, not used.

**The write path is key-independent too.** `serviceClient()` and the three cron functions
run on `writeApiKey()`, which prefers an injected **secret** key (`sb_secret_…` from
`SUPABASE_SECRET_KEYS`) and falls back to `SUPABASE_SERVICE_ROLE_KEY`. Both selections are
prefix scans, so a publishable key can never be used to write and a secret key can never
be used to verify a caller — each is pinned by a test. This matters because the dashboard
retires the legacy keys **together**: one *"Disable JWT-based API keys"* button kills `anon`
and `service_role` at once, and `service_role` is what every write in the system runs on,
including the daily sync, detection and reminders. Retiring the legacy pair needs both
halves migrated, not just the caller-verification one.

**`register-connection`'s duplicate check** deserves its own note. It compares the
**accounts** an incoming item exposes, keyed `type:last4` — not the provider's account
id (per-item, so it would match nothing) and not the display name (which the provider
rewords). It **fails open**: a loud false positive beats a silent double-count. The
check lives here rather than in `connect-token` because the token is minted *before* the
user picks a bank in the widget, so it cannot be scoped by connector.

---

## 8. Migration discipline

- **Versioned files, forward-only.** `backend/supabase/migrations/` holds 19 timestamped
  SQL files. `supabase db push` applies what is pending, and the deploy job runs it
  unconditionally on every merge, so a migration that misses one deploy self-heals on
  the next.
- **Never edit an applied migration.** `db push` records and compares a **version**, not
  the file's contents, so a file edited after it was applied silently never reaches
  production and no check can see the drift. Write a new migration instead.
- **Trust the ledger less than the database.** The deploy job ends with
  `migration list --linked` and fails if any local version has no remote counterpart. A
  green deploy that applied nothing is a failure already paid for once.
- **`Schema applies` in CI proves migrations apply to an *empty* database** — nothing
  more. A migration that locks a populated table, or violates a constraint only real rows
  can violate, passes that gate. The deploy prints `db push --dry-run` first, so a
  post-mortem starts with what ran.
- **Migrations run before functions**, and the job fails fast between them: a writer must
  never ship ahead of the column or data it depends on.
- **Some steps are deliberately one-off and manual** because they do not belong in a
  migration: creating Vault secrets, and uploading the email mark to the public `brand`
  bucket (a binary in a migration is the wrong shape).

Migration headers used to carry a `Source of truth: <spec> (vNN, date)` line naming the
spec version each was written against; those were comments, so that provenance now lives
in git history and the spec's changelog.

---

## 9. Logo sourcing

Three tiers, in order:

1. **Runtime fetch by domain** from logo.dev, cached to disk for 30 days.
2. **Bundled assets — deliberately unpopulated.** Insurance against an outage or an
   uncovered domain, to be added only if tier 1 fails in practice.
3. **The monogram tile**, which needs no data at all and is what the avatar already
   draws.

**Why it fetches logos the user has no subscription to.** Fetching only the domains a
user is subscribed to would tell logo.dev the user's subscription list, one request at a
time — a financial-behaviour fingerprint tied to an IP. So the prefetch walks the
**whole catalog**: the request set is identical for every install and independent of
anyone's data. The cost is roughly two megabytes once per TTL, and the property is
structural rather than a promise.

**That property depends on the catalog being independent of the user.** A catalog seeded
from the user's own merchants would make "fetch everything" leak anyway — which is why
`brand_catalog` is shared reference data carrying no `user_id`, identical for every
account.

**`kind` scoping is load-bearing.** `brand_catalog` holds both services and financial
institutions, and a bank's name also appears on statements as the *acquirer* — so an
unscoped lookup gives a bank-acquired subscription the bank's logo. The lookup takes
`kind` as a required argument for that reason. Every institution domain was verified to
resolve at logo.dev before being written, because a row whose logo does not resolve is a
row that does nothing.

Logos **fill** the avatar tile — logo.dev images carry their own padding, so an extra
inset double-pads them — and renaming a subscription costs it its logo, because
resolution runs off the merchant identity rather than the display name.

---

## 10. The auth gate

Four states, and `RootView` switches on exactly one value:

```
.restoring        cold launch, session restore in flight — renders the splash
.unauthenticated  the welcome flow
.recovering       a password-reset deep link is in charge
.authenticated    the app shell
```

**Every transition is a function of (current state, event), never of the event alone.**
Blind assignment was the same defect twice — a late restore overwriting a link's
decision, and an expired link ejecting a signed-in user — so all transitions are
funnelled through one place rather than patched per site.

Each event enumerates **all four states with no `default`**, so the compiler forces a
decision per cell and a `break` reads as a decision rather than as an omission.

The race that motivated it: a deep link can land while restore is still in flight — a
cold launch from an email link is exactly that. **The link already decided, and it
wins**; a late restore overwriting `.recovering` with `.authenticated` drops the user on
Home with their password unchanged.

**There is no "signed in but unverified" branch, by construction.** Email confirmation
is on and non-negotiable, so a session existing *implies* a verified address. That is
why the signup → confirm-notice step is navigation inside the welcome flow rather than a
gate transition.

---

## 11. Failure honesty

**A failed read must never look like no data.** Every read used to be `try?`, and a screen
rendered the same empty view for "still loading" and "the read threw" — so a signed-in
user whose data would not load got a blank page with a tab bar and nothing naming the
problem, on screen or in a log. "Renders nothing" tells the user nothing and tells us
nothing.

The rule both list screens now follow:

| On screen | A failed read does |
|---|---|
| nothing | the failure view, with a retry — the error **is** the screen |
| a payload | keep it, and report the failure through the shell alert |

The second row is the one worth stating: a failure view there would say **less** than
the data already displayed supports.

**Messages are the underlying error's own words**, not a paraphrase. The reader of this
deployment is also its developer, and "Something went wrong" deletes the only useful
part. The connect flow and the four server-side writes take the same posture, surfacing
the server's message verbatim.

**Failures with nowhere to be noticed get an alert.** The four Edge Function writes change
state no screen is showing, and a failed pull-to-refresh leaves the last good data on
screen — correct, and indistinguishable from a refresh that worked. One channel, one
meaning: *the thing you asked for did not happen.*

**The six client-owned column writes use that same channel.** Setting a nickname, a
category, `ignored`, or a reminder is a direct column-scoped `UPDATE`, and each used to be
`try? await`, so a rejected write left the old value rendering with nothing said. Worse for
diagnosis than a visible error: the provider only invalidates its cache **on success**, so
a failed write leaves the stale value in place and the screen looks like it obeyed. They now
route through the same alert, and the two that are already async only bump `dataVersion`
once the write has actually landed.

**Pull-to-refresh ignores the refresh verdict but never the error.** The verdict (did
anything change?) is ignored because the user asked, so the payload is re-read either way
and the gesture never appears to do nothing. Swallowing the *error* produced a gesture
that appeared to have worked, which is worse. A **foreground** refresh does use the
verdict: discarding someone's scroll position to show them what they were already looking
at is worse than not refreshing.

**A number is never cropped.** `minimumScaleFactor` alone was not enough — at the largest
accessibility sizes the date slot grows and the amount truncated anyway — so layouts
reflow. And a layout claim is worth what the screenshot says: two changes that read as
correct in code were wrong on screen.

---

## 12. Auth email templates

The two emails Signu sends live in `backend/supabase/templates/`, registered in
`config.toml` under `[auth.email.template.recovery]` and `.confirmation`. Paths there are
relative to the directory holding `supabase/`, hence the `./supabase/` prefix — the CLI's
own examples show it both ways and only that form resolves.

**The HTML files carry no comments, deliberately.** Comments in an email template are
*delivered* — they sit in the source the recipient can open with "show original" — and
worse, a `{{ .Email }}` mentioned in prose is substituted like any other, putting the
address in the source an extra time.

| Template | Sent when | Included |
|---|---|---|
| `confirmation` | signup, because confirmation is on | yes |
| `recovery` | the password reset, and the Settings row that reuses it | yes |
| `email_change` | changing an address | no — the app has no change-email UI |
| `invite`, `magic_link`, `reauthentication` | — | no — never sent |

The confirmation template is included because confirmation being on makes it the
**first** email any account receives: fixing only the reset would fix the second
impression and not the first.

**Construction rules, none of them preferences:**

- **Table layout, inline styles.** Outlook renders no flexbox and strips `<style>`
  blocks, so a stylesheet degrades to unstyled text in the client most likely to open
  it. Every colour is stated on the element that uses it.
- **One image, with a fallback that still reads as the brand.** The mark is two
  counter-rotated arcs, not a letter, so no font substitutes for it. SVG is out (Gmail
  drops it) and so is a `data:` URI (Gmail strips those), so it must be hosted — from the
  **public** `brand` bucket, because a mail client holds no session and an email outlives
  any signed URL. The opposite requirement to the private avatars bucket. Rendered 40×40
  from an 80×80 source; placing the asset is a one-off step per environment.
- **The link appears twice**, as a button and as selectable text, because a client that
  strips anchor styling still leaves something the reader can copy.
- **Palette copied from the app's `Theme.swift`** — paper, surface, ink, on-ink, text,
  secondary, hairline — so the mail matches the app without importing anything.
- **Pure ASCII**, with entities for em dashes. GoTrue does declare `charset=UTF-8` so raw
  UTF-8 would almost certainly survive, but "almost certainly" is doing work in the one
  email a locked-out user needs to read, and an entity depends on no charset negotiation
  at all. Verified by counting: zero bytes above 0x7F in either file.

**Copy that had to be checked rather than written:** "within the hour" is
`otp_expiry = 3600`, not an assumption. An earlier draft said the bank connection "is
read-only" and that Signu "cannot" move money — **cut**, because the Pluggy connector
payload advertises `supportsPaymentInitiation`, so that claim needs the consent scope
verified before it goes in writing to a user. It now says Signu only ever reads, which
is defensible from what the app does.

**Deploying them is a dashboard operation**, on evidence rather than caution — see §13.

---

## 13. Local dev, test, deploy

### Run

```sh
xcodebuild build -project frontend/Signu.xcodeproj -scheme Signu \
  -configuration Debug -destination 'generic/platform=iOS'
xcodebuild test  -project frontend/Signu.xcodeproj -scheme Signu \
  -configuration Debug -destination "id=$SIMULATOR_UDID"

deno test  backend/supabase/functions/_shared/
deno lint  backend/supabase/functions
deno check backend/supabase/functions/_shared/detection.ts
```

**Never hand over a `CODE_SIGNING_ALLOWED=NO` build.** CI passes that flag because it
only needs to compile, but the resulting app has **no entitlements**, so the Keychain
refuses every write — and the auth client stores its session there and nowhere else.
Sign-in succeeds, nothing persists, the session reads back nil, and every request falls
back to the anonymous key. That looked exactly like a production permissions outage once.
Use Xcode's default simulator signing for anything a human will touch.

**A DEBUG build runs against mock data by default**, and live is opt-in:
`simctl launch <udid> <bundle-id> --live-auth --live-data`. Both flags exist so the
session provider and the data provider can never disagree about which world a build is
in. With the mock provider `refresh()` never throws, so failure paths are unreachable —
a live build is the only way to exercise them.

**Editor setup.** `.vscode/` enables the Deno language server for
`./backend/supabase/functions` only, via `deno.enablePaths` rather than `deno.enable`.
Without it the built-in TypeScript server checks those files against Node/browser globals
and reports *"Cannot find name 'Deno'"* on every `Deno.env` call plus an unresolvable
`https://` import — errors that are not real, since `deno check` and `deno lint` both pass.
Enabling it repo-wide would point the wrong analyser at everything outside that directory,
which is most of the repo. The `denoland.vscode-deno` recommendation exists because
`enablePaths` needs a language server to point at.

**What is ignored, and why the pattern rather than a list.** `.gitignore` covers `.env`
and `.env.*` as a **class**. An earlier enumeration (`.env`, `.env.local`, `.env.*.local`)
did not cover `.env.production`, which already existed on disk holding a live Pluggy client
secret and the sync secret — one `git add -A` away from a public repo. Naming files leaves
the same hole open for the next variant, so the rule is the class, with `!.env.example` as
the single committed template. Also ignored for the same reason: `pluggy-probe-raw.json`,
which is real transaction history, and `frontend/Signu/Config.plist` below.

**Local configuration.** The project URL, the anon key and the logo.dev publishable key
are read at launch from a `Config.plist` that is **not committed** — copy the template:

```sh
cp frontend/Signu/Config.example.plist frontend/Signu/Config.plist
```

### CI

Three required checks, plus a deploy that runs on `main` only and is gated on all three:
**`iOS build`** (the app compiles and the whole Swift suite passes on a simulator),
**`Detection tests`** (`deno check` per named file, `deno lint`, every `_shared/` suite),
and **`Schema applies`** (all migrations apply to an empty database).

**Third-party actions are pinned to commit SHAs, not tags.** `@v4` is a tag the owner
can move and `@v1` is a *branch*, so both can gain new code without this file changing —
and the deploy job runs them with a Supabase access token in its environment, which
carries the same privileges as the account. The pins, and the versions they resolved to:

| Action | Commit | Was |
|---|---|---|
| `actions/checkout` | `11d5960a326750d5838078e36cf38b85af677262` | v4.4.0 |
| `supabase/setup-cli` | `ab058987d8d6c725971f6cf9d0b5c98467e30bd1` | v1.7.1 |
| `denoland/setup-deno` | `22d081ff2d3a40755e97629de92e3bcbfa7cf2ed` | v2.0.5 |

The Supabase CLI itself is pinned to `2.109.1` in the job. To upgrade any of these,
resolve the new tag to a commit and change both the SHA and the table row together:
`gh api repos/<owner>/<repo>/git/ref/tags/<version> --jq .object.sha`. Never "fix" a pin
by reverting to a tag; that silently restores the mutability.

**Deploy on green.** A merge to `main` runs `db push`, then deploys functions scoped to
what changed. A `_shared/` change deploys **every** function, because they all bundle it —
narrow scoping there would silently leave old copies running in production.

**Superseded PR runs are cancelled; runs on `main` are not.** Cancelling on every ref
cost a production deploy once, silently: a newer merge cancelled the previous merge's run
mid-build, its deploy died with it, and the next run's scoped diff legitimately found no
function changed — so a merged guard sat undeployed behind three green checkmarks.
Deploys still serialise through their own concurrency group, which GitHub does not
document as FIFO, so two queued together could land out of order; the next merge
redeploys, so that window closes on its own.

**Recovering a skipped deploy:** re-run the cancelled run rather than deploying by hand.
Its event payload still carries the right base commit, so scoping deploys correctly, and
a laptop deploy bypasses the green gate the pipeline exists to be. Verify from the log
that it printed `Deployed Functions on project …`.

**Functions are verified after deploying, the way migrations are.** `Verify functions
shipped` reads `supabase functions list` and fails the deploy when a function directory in
the repo has no deployed counterpart, when a deployed function is not `ACTIVE`, when its
remote `verify_jwt` disagrees with what `config.toml` declares, or when a function whose
own sources changed in this push carries a bundle older than the deploy that just ran. It
prints every slug's version, `verify_jwt` and `updated_at` either way, so a post-mortem
starts from what is actually deployed rather than from what the log claims. A function
deployed but absent from the repo is reported as a note, not a failure.

**What it deliberately cannot catch:** staleness after an *unchanged* bundle. The CLI skips
uploading when content has not changed, so `updated_at` legitimately stays old, and the
check only asserts freshness for slugs whose sources changed in the same push. The
stranded-deploy case — a run cancelled before its deploy ever started — is closed by the
concurrency rule above, not by this step.

### `supabase config push` is forbidden

Not caution — evidence:

- **It has never been run against this project**, so `config.toml` has never been
  reconciled wholesale with production. Exactly one setting was ever checked by hand.
- The file holds **74 auth settings** and a first push applies all of them at once.
  Several are the CLI's *local-dev* defaults and wrong for production: the reset-email
  minimum interval is `1s` against production's `60s` (pushing it removes the
  server-side limit the app's countdown exists to make visible), `site_url` points at
  localhost, and email confirmation sat at the CLI default of *off* — pushing that would
  have silently disabled confirmation, so signup would return live sessions for
  unverified addresses with no error anywhere, and the auth gate rests on it being on.
- **There is no way to check the rest.** `supabase config pull` does not exist, so
  nothing can diff production's auth config first — and `config push` has no dry-run and
  aborts midway on the first rejected setting, after auth has already been written.

**Four other `config.toml` values are load-bearing and easy to "tidy" wrongly.**
`site_url` *and* `additional_redirect_urls` must both name the app's deep link, because
Supabase refuses any redirect not **exactly** on that list — naming it once is not enough.
The Google provider is a **web** client, not an iOS one, since the code exchange happens
on Supabase's server. The `[db.seed]` block stays present with seeding off: removing it
makes the CLI fall back to a default path and warn on every `db reset`, and a warning
that always fires trains you to ignore warnings. And vector buckets stay `false` because
on a free project the API rejects `true` with a 402 that aborts a push midway — after
auth has already been written.

So auth config changes, including the email templates, go through the dashboard until
all 74 settings have been reconciled as its own task. The drift this creates is real and
accepted: the templates and their registration stay committed so the repo remains the
source of truth, and the dashboard is only today's delivery mechanism.

---

## 14. The specification

**`docs/subscription-tracker-data-model.md` is the source of truth.** A living document
with a changelog, carrying the full schema, the detection doctrine, every screen contract,
and the reasoning behind decisions this README only summarises — including the ones that
were rejected and why. `docs/Screen-mockups/` holds the design references those screen
contracts were locked against. Where this README and the spec disagree, the spec wins.
