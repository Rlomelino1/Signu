# Signu

A subscription tracker for Brazilian bank and card data. Charges are read from
Pluggy, interpreted by a pure detection engine, and rendered by a SwiftUI app.

- **The specification is `docs/subscription-tracker-data-model.md`** — a living
  document with a changelog. It is the source of truth for schema, detection
  doctrine, screen contracts and every decision's reasoning. This README is
  deliberately thin by comparison.
- `frontend/` — the iOS app (SwiftUI, Swift 6 language mode).
- `backend/supabase/` — migrations, pgTAP tests, and ten Edge Functions.
- `.github/workflows/ci.yml` — three required checks: `iOS build`,
  `Detection tests`, `Schema applies`.

---

# How fresh the data is, and why a charge can be missing

**The short version: a charge on your card today is normally visible in Signu
tomorrow, and the delay is almost never Signu's.** Three schedules are stacked,
only one of which this project controls.

This section exists because the question "the charge is on my card, why isn't it
in the app?" has a long answer, and every attempt to shorten it produces a wrong
diagnosis. Statements below are marked **[observed]** (measured against live
production data), **[documented]** (quoted from Pluggy's docs, linked at the
bottom), or **[speculative]** (reasoning we could not verify — flagged rather
than smoothed over).

## The three layers

| # | Hop | Cadence | Who controls it |
|---|-----|---------|-----------------|
| 1 | bank → aggregator | unobservable to us | the bank / the aggregator |
| 2 | aggregator → Pluggy item | ~24h per item | Pluggy (plan-level) |
| 3 | Pluggy → Signu | daily, 15:30 UTC | us |

**Layer 3 is ours and is the least interesting.** `pluggy-sync` runs at 15:30 UTC
from `pg_cron`, re-scans 365 days per account, and chains directly into
`run-detection`. Every call it makes **to Pluggy's data endpoints is a GET** —
`/items/{id}`, `/accounts`, `/v2/transactions` — and it never issues
`PATCH /items/{id}`. (It does POST twice: `/auth` to mint an API key, and its own
`run-detection` hand-off.) So it reads whatever Pluggy already holds and cannot
make Pluggy look again. The transactions request sends
`dateFrom` with **no upper bound**, so "today" is never excluded by the query
itself. **[observed]**

**Layer 2 is Pluggy's auto-sync.** Each item carries `lastUpdatedAt` and
`nextAutoSyncAt`, and the gap between them has been exactly **24 hours**, anchored
to the previous update rather than to a fixed wall-clock slot — so the anchor
drifts each time an item updates. Two items on the same account sit on unrelated
clocks (15:01 UTC and 22:54 UTC in one recorded case). **[observed]**
Pluggy documents this as *"We provide automatic Item updates, for Production
applications, every 24/12/8 hours, based on your plan."* — the 24h we observe is
consistent with the slowest tier; which tier this project is on is not visible
through the API. **[documented]**
Our 15:30 UTC cron is deliberately scheduled **after** the observed 15:01 UTC
auto-sync, so a normal day needs no coordination.

**Layer 1 is the bank, and it is where the time actually goes.** Nothing in the
API exposes it, and it cannot be bypassed from here.

## The worked example that motivated this section

2026-08-18. A subscription renewal (R$ 35,51) hit the card at **07:41 local
(10:41 UTC)**. Signu did not show it. The chain, measured: **[observed]**

| step | evidence | verdict |
|------|----------|---------|
| Pluggy auto-synced *after* the charge | `lastUpdatedAt 15:01:23Z`, `executionStatus SUCCESS` | ran, and succeeded |
| Pluggy held it? | **0 transactions** dated ≥ 2026-08-17 across all four accounts | **no** |
| Signu missed rows Pluggy had? | 4 of 4 rows since Aug 13 present locally | **no** |
| detection ignored it? | nothing to ignore — the row did not exist | **no** |

So Pluggy looked **4h20m after the charge landed**, succeeded, and still had
nothing. The charge had not reached Pluggy from upstream. **[observed]**
Why not is not observable through the API — the bank may not publish a card
authorisation immediately, or the aggregator in front of it may not have
refreshed. **[speculative]**

**Measured end-to-end latency** (charge date → the row first existing locally,
production, charges since 2026-08-01, n=9): **median +1 day**, min +0, max +8.
The closest comparison to the case above — same merchant, same card — took
**+2 days**. **[observed]**

**Side effect worth knowing.** A run goes `overdue` at its expected date + 3 days
and `ended` 10 days after that. So if a renewal takes more than four days to
surface, the app shows the subscription as overdue while the money has already
left the card. It self-heals on the next pass. That is upstream latency made
visible, not a defect to chase.

## This behaviour is specific to a MeuPluggy connection

The connection in use is **connector 200, "MeuPluggy"**, and its metadata says
plainly what it is: **[observed]**

```
id=200  MeuPluggy  type=PERSONAL_BANK  country=BR  isOpenFinance=false  oauth=true  hasMFA=false
```

`isOpenFinance: false` is the important field. MeuPluggy is Pluggy's own
consumer aggregation product: the user logs into `meu.pluggy.ai`, connects banks
*there*, and Signu's item then mirrors **that account** rather than any single
bank. Connector 200 therefore names no bank at all, which is why `BankLabel`
derives the institution from the account's own name (v43).

**Consequence:** layer 1 is itself two hops — bank → `meu.pluggy.ai` → Pluggy
item — and the middle hop has its own refresh cadence that the Pluggy API does
not expose. **[speculative]** (The architecture is documented; the internal
cadence is inferred, and it is the most likely explanation for a successful
Pluggy sync returning nothing 4h20m after a charge.)

**The one lever this gives the user:** refreshing the bank connection *inside the
`meu.pluggy.ai` dashboard* acts on the layer that is otherwise unreachable. No
API call from this project can substitute for it. **[speculative]** — consistent
with the architecture, never tested here.

## What a direct bank connection would look like

Pluggy also offers regulated connectors for the same institutions: **[observed]**

```
id=612  Nubank   type=PERSONAL_BANK  isOpenFinance=true  oauth=true  hasMFA=false
id=626  C6 Bank  type=PERSONAL_BANK  isOpenFinance=true  oauth=true  hasMFA=false
```

Switching would remove the aggregator hop. It would **not** obviously make the
app fresher, and might make card data worse:

- **Bank-side latency remains.** *"New transactions in Open Finance (regulated)
  connectors can take up to 24 hours to be available for consultation."*
  **[documented]** — surfaced via Pluggy's docs search; we could not reproduce the
  sentence on the page we fetched, so treat the exact figure as unconfirmed while
  the direction (bank-side delay exists regardless) is well supported.
- **Open credit-card bills may be worse.** Pluggy's FAQ states institutions
  *"provide new purchases on a daily"* basis but that open bills are
  *"unavailable until bills are closed or overdue"*. **[documented]** If that
  applies to the accounts here, current-cycle purchases could become **less**
  visible than today — the MeuPluggy path currently delivers `PENDING`
  open-cycle rows, which is exactly what a subscription tracker needs.
  **[speculative]** — we have not tested a regulated connector on this data.
- **Per-sync lookback differs.** *"Open Finance (regulated) connectors: 7
  calendar days including today"* versus *"Direct connectors: 4 to 5 calendar
  days from the last sync."* **[documented]** Signu re-scans 365 days every run,
  so this changes nothing for us — noted because it would matter to an
  incremental design.
- **Consent replaces credentials.** Open Finance consents *"have no expiration"*
  by default but are revocable from the bank's app, and once revoked *"all its
  data endpoints (accounts, transactions, etc) will return empty data"* —
  empty, not an error. **[documented]** The schema already has
  `connection.consent_expires_at` for this.
- **Regulated rate limits appear.** Normal usage (one CPF per institution, one
  item) is documented as safe *"even if you had automatic updates enabled on all
  your items updating up to 4 times per day"*, but duplicate items burn the
  quota: after **240** requests new transactions stop appearing until the next
  month, and after **420** the balance stops updating. **[documented]** This
  interacts directly with `register-connection`'s duplicate check (v53).

**Net:** a direct connector is a plausible improvement to *attribution* (a real
bank name, no aggregator hop) and an unproven one to *freshness*. It should be
tested on a throwaway item before anything is migrated. **[speculative]**

## Forcing an update, and what each bypass buys

| layer | mechanism | what it actually buys |
|-------|-----------|----------------------|
| 3 (ours) | invoke `pluggy-sync` with `x-sync-secret` | nothing if Pluggy has no new data |
| 2 (Pluggy) | `PATCH /items/{id}` | a fresh pull **from the aggregator**, once the aggregator has the data |
| 1 (bank) | refresh inside `meu.pluggy.ai` | the only lever on the layer that usually blocks |

Constraints on the layer-2 bypass, before reaching for it: **[documented]**

- Rate limited — *"The updates could not be performed more than once per hour"*
  for API-triggered updates on newer client ids.
- Pluggy steers integrators to the **widget** instead (a connect token carrying
  `itemId` plus `updateItem`), and says *"In most cases, you can simply start the
  Item Update process without any problem or further input from the user"* —
  with `INVALID_CREDENTIALS` items and MFA prompts as the exceptions that do need
  the user. An API `PATCH` on an item that then wants input can leave it in a
  state the app renders as "Reconnect". **[speculative]** — the exact resulting
  status was not tested here.

**Webhooks are not the fix, and are deliberately not built.** They fire when
*Pluggy* updates an item — and in the case above Pluggy did update, with nothing
new, so a webhook would have delivered an empty event on time. The spec's other
reason still stands: Pluggy offers no webhook signature, so authenticating a
public endpoint would rest on a bearer header that does not bind to the payload
plus a hard-coded IP. See "Sync shape: poll-only, no webhook endpoint" in the
spec.

## Known gaps in how freshness is *reported*

Both are real and both are unfixed:

- **`connection.last_synced_at` is our own clock** (`new Date()` at the end of a
  sync), not Pluggy's `lastUpdatedAt`. So "Updated 3h ago" means *we read Pluggy
  3h ago*, not *the data is 3h old* — and the two diverge exactly when the data
  is stale, which is when the label matters. **[observed]**
- **`item.lastUpdatedAt` is fetched and discarded.** `pluggy-sync` already calls
  `GET /items/{id}`; nothing reads its freshness. The honest label is one
  assignment away. **[observed]**

## Sources

- [Data sync: Update an Item](https://docs.pluggy.ai/docs/data-sync-update-an-item)
- [Updating an Item](https://docs.pluggy.ai/docs/updating-an-item)
- [Consents and expiration](https://docs.pluggy.ai/docs/consents)
- [Considerations & FAQ](https://docs.pluggy.ai/docs/considerations-faq)
- [Operational Rate Limits](https://docs.pluggy.ai/docs/rate-limits-of)
- [Open Finance Connectors](https://docs.pluggy.ai/docs/open-finance-regulated)

Connector and item facts above were read from the live Pluggy API on 2026-08-18;
latency figures from the production database on the same day.
