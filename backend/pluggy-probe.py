#!/usr/bin/env python3
"""
Pluggy probe — answers the four blocking questions from the sync findings report.

  1. Does any credit-card transaction ever reach status POSTED through connector 200?
     (existential: the spec says only posted feeds detection)
  2. Is creditCardMetadata.billId ever populated through connector 200?
  3. Which installment fields do YOUR banks actually populate?
  4. Are merchant / category null on the free path?

No dependencies beyond the Python 3 standard library.

Usage:
    python3 pluggy-probe.py <itemId>
    python3 pluggy-probe.py <itemId> --days 400     # history window, default 400

Credentials are read from ./.env or ../.env (PLUGGY_CLIENT_ID, PLUGGY_CLIENT_SECRET).

TWO OUTPUTS, deliberately separated:
  stdout                 aggregate counts and field-presence flags only. Contains no
                         merchant names and no amounts. Safe to paste into a chat.
  pluggy-probe-raw.json  full API responses, including real transactions. Your eyes
                         only. Make sure it is gitignored before it exists.
"""

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
from datetime import date, timedelta

BASE = "https://api.pluggy.ai"
INSTALLMENT_FIELDS = [
    "installmentNumber",
    "totalInstallments",
    "totalAmount",
    "purchaseDate",
    "billId",
    "billForecastDate",
    "payeeMCC",
    "cardNumber",
]




def load_env():
    for path in (".env", "../.env", "backend/.env"):
        if os.path.exists(path):
            values = {}
            with open(path) as handle:
                for line in handle:
                    line = line.strip()
                    if not line or line.startswith("#") or "=" not in line:
                        continue
                    key, _, value = line.partition("=")
                    values[key.strip()] = value.strip().strip("'\"")
            cid = values.get("PLUGGY_CLIENT_ID")
            secret = values.get("PLUGGY_CLIENT_SECRET")
            if cid and secret:
                return cid, secret, path
    die(
        "No credentials found. Create backend/.env with:\n"
        "  PLUGGY_CLIENT_ID=...\n"
        "  PLUGGY_CLIENT_SECRET=...\n"
        "and confirm `git check-ignore -v backend/.env` prints a rule."
    )


def die(message):
    print(f"\n  ERROR  {message}\n", file=sys.stderr)
    sys.exit(1)


def request(method, url, body=None, api_key=None):
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["X-API-KEY"] = api_key
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=45) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as err:
        detail = err.read().decode(errors="replace")[:600]
        die(f"HTTP {err.code} on {method} {url}\n         {detail}")
    except urllib.error.URLError as err:
        die(f"Network failure on {method} {url}: {err.reason}")


def get(path, api_key, **params):
    clean = {k: v for k, v in params.items() if v is not None}
    url = f"{BASE}{path}"
    if clean:
        url += "?" + urllib.parse.urlencode(clean)
    return request("GET", url, api_key=api_key)




def fetch_all_transactions(account_id, api_key, days):
    """Page /v2/transactions to exhaustion. Returns (rows, page_count, truncated)."""
    date_from = (date.today() - timedelta(days=days)).isoformat()
    rows, cursor, pages, truncated = [], None, 0, False
    max_pages = 40

    while True:
        payload = get(
            "/v2/transactions",
            api_key,
            accountId=account_id,
            dateFrom=date_from,
            after=cursor,
        )
        rows.extend(payload.get("results") or [])
        pages += 1

        nxt = payload.get("next")
        if not nxt:
            break

        cursor = urllib.parse.parse_qs(urllib.parse.urlparse(nxt).query).get(
            "after", [None]
        )[0]
        if not cursor:
            break
        if pages >= max_pages:
            truncated = True
            break

    return rows, pages, truncated




def summarise_account(rows):
    meta_rows = [r for r in rows if isinstance(r.get("creditCardMetadata"), dict)]
    field_hits = Counter()
    for row in meta_rows:
        meta = row["creditCardMetadata"]
        for field in INSTALLMENT_FIELDS:
            if meta.get(field) is not None:
                field_hits[field] += 1

    statuses = Counter((r.get("status") or "NULL") for r in rows)
    posted = [r for r in rows if r.get("status") == "POSTED"]
    posted_with_bill = sum(
        1
        for r in posted
        if isinstance(r.get("creditCardMetadata"), dict)
        and r["creditCardMetadata"].get("billId") is not None
    )
    installment_rows = sum(
        1
        for r in meta_rows
        if r["creditCardMetadata"].get("installmentNumber") is not None
        or r["creditCardMetadata"].get("totalInstallments") is not None
    )
    dates = sorted(str(r.get("date"))[:10] for r in rows if r.get("date"))

    return {
        "total": len(rows),
        "statuses": dict(statuses),
        "posted": len(posted),
        "posted_with_billId": posted_with_bill,
        "rows_with_creditCardMetadata": len(meta_rows),
        "installment_field_hits": dict(field_hits),
        "rows_flagged_as_installment": installment_rows,
        "merchant_non_null": sum(1 for r in rows if r.get("merchant") is not None),
        "category_non_null": sum(1 for r in rows if r.get("category") is not None),
        "updatedAt_present": sum(1 for r in rows if r.get("updatedAt") is not None),
        "date_range": (dates[0], dates[-1]) if dates else None,
    }


def report(item, accounts, per_account):
    connector = item.get("connector") or {}
    print("\n" + "=" * 68)
    print("  ITEM")
    print("=" * 68)
    print(f"  connector          {connector.get('id')} · {connector.get('name')}")
    print(f"  isOpenFinance      {connector.get('isOpenFinance')}")
    print(f"  status             {item.get('status')} / {item.get('executionStatus')}")
    print(f"  lastUpdatedAt      {item.get('lastUpdatedAt')}")
    print(f"  nextAutoSyncAt     {item.get('nextAutoSyncAt')}  <- null = no auto-sync")

    credit_ids = set()
    print("\n" + "=" * 68)
    print("  ACCOUNTS")
    print("=" * 68)
    for acc in accounts:
        kind = acc.get("type")
        if kind == "CREDIT":
            credit_ids.add(acc["id"])
        print(f"  {acc.get('id')}  {str(kind):<8} {acc.get('subtype')}")

    for acc in accounts:
        stats = per_account[acc["id"]]
        print("\n" + "-" * 68)
        print(f"  {acc.get('type')} · {acc.get('subtype')}  ({acc['id'][:8]}…)")
        print("-" * 68)
        print(f"  transactions       {stats['total']}")
        print(f"  date range         {stats['date_range']}")
        print(f"  status breakdown   {stats['statuses']}")
        print(f"  POSTED             {stats['posted']}")
        print(f"    ...with billId   {stats['posted_with_billId']}")
        print(f"  creditCardMetadata {stats['rows_with_creditCardMetadata']} rows")
        print(f"  installment rows   {stats['rows_flagged_as_installment']}")
        print(f"  field presence     {stats['installment_field_hits'] or '{} (none)'}")
        print(f"  merchant non-null  {stats['merchant_non_null']}")
        print(f"  category non-null  {stats['category_non_null']}")
        print(f"  updatedAt present  {stats['updatedAt_present']}")

    credit_stats = [per_account[i] for i in credit_ids]
    total_posted_credit = sum(s["posted"] for s in credit_stats)
    total_credit_rows = sum(s["total"] for s in credit_stats)
    any_billid = sum(s["posted_with_billId"] for s in credit_stats) + sum(
        s["installment_field_hits"].get("billId", 0) for s in credit_stats
    )
    installment_fields_seen = Counter()
    for s in credit_stats:
        installment_fields_seen.update(s["installment_field_hits"])
    merchant_seen = sum(s["merchant_non_null"] for s in per_account.values())
    category_seen = sum(s["category_non_null"] for s in per_account.values())

    print("\n" + "=" * 68)
    print("  VERDICTS")
    print("=" * 68)

    if not credit_ids:
        print("  Q1  NO CREDIT ACCOUNT CONNECTED — cannot answer. Connect a card.")
    elif total_credit_rows == 0:
        print("  Q1  Credit account present but ZERO transactions in window.")
    elif total_posted_credit > 0:
        print(f"  Q1  POSTED DOES OCCUR — {total_posted_credit} posted credit rows.")
        print("      Detection has input. Proceed.")
    else:
        print(f"  Q1  *** NO POSTED CREDIT TRANSACTIONS *** ({total_credit_rows} rows,")
        print("      all non-POSTED). 'Only posted feeds detection' needs rethinking")
        print("      BEFORE any sync code is written. Stop and report this.")

    print(
        f"  Q2  billId populated: {'YES' if any_billid else 'NO'}"
        f"  ({any_billid} rows)"
    )

    if installment_fields_seen:
        keys = ", ".join(sorted(installment_fields_seen))
        print(f"  Q3  installment fields present: {keys}")
        core = {"installmentNumber", "totalInstallments"}
        if core & set(installment_fields_seen):
            print("      R1 can use these as a disqualifying signal.")
        else:
            print("      *** Neither installmentNumber nor totalInstallments seen. ***")
            print("      R1 has no defence against Padrao B false positives.")
    else:
        print("  Q3  NO installment metadata at all. Either no installment purchase")
        print("      in the window, or your bank omits the fields. Not conclusive")
        print("      unless you know a past installment purchase is in range.")

    print(
        f"  Q4  merchant non-null: {merchant_seen}   "
        f"category non-null: {category_seen}"
    )
    if merchant_seen == 0:
        print("      merchant is null (Pro-gated) — raw description is your only")
        print("      merchant signal. Confirms the findings report's expectation.")
    print()




def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        die("Usage: python3 pluggy-probe.py <itemId> [--days 400]")
    item_id = args[0]

    days = 400
    if "--days" in sys.argv:
        try:
            days = int(sys.argv[sys.argv.index("--days") + 1])
        except (IndexError, ValueError):
            die("--days needs an integer")

    client_id, client_secret, env_path = load_env()
    print(f"  credentials from {env_path}")

    auth = request(
        "POST", f"{BASE}/auth", {"clientId": client_id, "clientSecret": client_secret}
    )
    api_key = auth.get("apiKey")
    if not api_key:
        die(f"No apiKey in /auth response: {auth}")
    print("  authenticated")

    item = get(f"/items/{item_id}", api_key)
    accounts = (get("/accounts", api_key, itemId=item_id) or {}).get("results") or []
    if not accounts:
        die("No accounts on this item. Has the first sync finished?")

    per_account, raw = {}, {}
    for acc in accounts:
        rows, pages, truncated = fetch_all_transactions(acc["id"], api_key, days)
        per_account[acc["id"]] = summarise_account(rows)
        raw[acc["id"]] = rows
        note = f"  *** TRUNCATED at {pages} pages ***" if truncated else ""
        print(
            f"  fetched {len(rows):>5} rows in {pages} page(s) — "
            f"{acc.get('subtype')}{note}"
        )

    with open("pluggy-probe-raw.json", "w") as handle:
        json.dump({"item": item, "accounts": accounts, "transactions": raw}, handle,
                  indent=2, ensure_ascii=False)

    report(item, accounts, per_account)
    print("  Full responses in pluggy-probe-raw.json — contains real transaction")
    print("  data. Do not commit it, and do not paste it. The summary above is")
    print("  what I need: counts and flags only, no merchants, no amounts.\n")


if __name__ == "__main__":
    main()
