#!/usr/bin/env python3
"""
Cross-implementation parity gate for the detection rules.

WHY THIS EXISTS

There are two implementations of the same rules: the TypeScript engine that
actually writes the database, and pluggy-detection-dryrun.py, the harness the
doctrine was developed against. Thirty-two passing unit tests on fixtures is not
the same evidence as two independent implementations agreeing -- the float-epsilon
bug (v23) passed every test it had and was only caught when the harness and a SQL
re-implementation disagreed on a count they should have shared.

So this script makes that comparison explicit and repeatable instead of a thing
someone remembers to do.

WHAT IT COMPARES, AND WHY IT IS STRONGER THAN THE OBVIOUS VERSION

The naive comparison -- run the harness on pluggy-probe-raw.json, run the engine
on the database, compare -- proves less than it appears to, because the two are
reading DIFFERENT INPUTS. Sync converts Pluggy's UTC timestamps to Sao Paulo
dates (v22), which moves 37 of 258 rows by a day, so a divergence could be date
handling rather than a rule disagreement and a match could be luck.

This script feeds BOTH implementations the same rows: it reads the database, emits
them in the Pluggy-shaped JSON the harness expects, and runs the harness over
that. Any divergence is then a rule divergence.

It found one on its first run: the harness lagged the engine by one version and
had no currency guard (v25), so the two encoded different rules and agreed only
because no cross-currency amounts collide in this data.

Not in CI. It needs a running local stack with real synced data, and the raw dump
is gitignored, so this is a local gate -- the same status as the dry run itself.

Usage (from backend/, with the stack up, data synced and functions served):
    python3 detection-parity.py

Exit code 0 on parity, 1 on divergence.
"""

import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

DB_CONTAINER = os.environ.get("SIGNU_DB_CONTAINER", "supabase_db_backend")
FUNCTIONS_URL = os.environ.get("SIGNU_FUNCTIONS_URL", "http://127.0.0.1:54321/functions/v1")
TODAY = os.environ.get("SIGNU_TODAY", "2026-08-10")

COMPARED = [
    "candidates",
    "excluded_credit",
    "excluded_fee",
    "excluded_installment",
    "excluded_internal_transfer",
    "r1_runs",
    "r3_runs",
]


def die(msg):
    print(f"\n  ERROR  {msg}\n", file=sys.stderr)
    sys.exit(1)


def psql_json(sql):
    out = subprocess.run(
        ["docker", "exec", "-i", DB_CONTAINER, "psql", "-U", "postgres", "-d", "postgres",
         "-tA", "-c", sql],
        capture_output=True, text=True,
    )
    if out.returncode != 0:
        die(f"psql failed (is the stack up?):\n{out.stderr.strip()[:400]}")
    body = out.stdout.strip()
    return json.loads(body) if body else []


def read_rows_from_db():
    """The rows the TypeScript engine will see, in the shape the harness expects.

    Withdrawn rows are dropped here rather than passed through: the harness
    predates withdrawn_at and has no filter for it, so including them would be a
    known shape mismatch rather than a rule comparison. The engine's withdrawn
    filter is covered by unit tests instead. Reported below so the omission is
    never silent.
    """
    return psql_json("""
      select coalesce(json_agg(row_to_json(x)), '[]'::json) from (
        select t.id, t.account_id, t.provider_tx_id, t.status, t.type,
               t.date::text as date, t.amount, t.currency,
               t.raw_description, t.installment_number, t.total_installments,
               t.fee_type_additional_info, t.provider_merchant_name,
               t.provider_merchant_cnpj, t.withdrawn_at
        from public.transaction t
      ) x;
    """)


def to_pluggy_shape(rows):
    """Database rows -> the JSON layout pluggy-probe-raw.json has.

    Only the fields the harness reads are populated. `date` keeps the stored Sao
    Paulo date rather than being converted back to UTC, which is the whole point:
    both implementations must see the same calendar day.
    """
    by_account = {}
    for r in rows:
        by_account.setdefault(r["account_id"], []).append({
            "id": r["id"],
            "provider_tx_id": r["provider_tx_id"],
            "description": r["raw_description"],
            "descriptionRaw": r["raw_description"],
            "date": f'{r["date"]}T12:00:00.000Z',
            "amount": float(r["amount"]),
            "currencyCode": r["currency"],
            "type": r["type"],
            "status": "POSTED" if r["status"] == "posted" else "PENDING",
            "creditCardMetadata": {
                "installmentNumber": r["installment_number"],
                "totalInstallments": r["total_installments"],
                "feeTypeAdditionalInfo": r["fee_type_additional_info"],
            },
            "merchant": (
                {"businessName": r["provider_merchant_name"], "cnpj": r["provider_merchant_cnpj"]}
                if r["provider_merchant_name"] or r["provider_merchant_cnpj"] else None
            ),
        })
    return {
        "item": {},
        "accounts": [{"id": a, "subtype": "UNKNOWN"} for a in by_account],
        "transactions": by_account,
    }


def run_harness(payload):
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as fh:
        json.dump(payload, fh)
        path = fh.name
    try:
        out = subprocess.run(
            [sys.executable, "pluggy-detection-dryrun.py", path],
            capture_output=True, text=True,
        )
        if out.returncode != 0:
            die(f"harness failed:\n{out.stdout[-800:]}\n{out.stderr[-800:]}")
        return parse_harness(out.stdout)
    finally:
        os.unlink(path)


def parse_harness(text):
    def one(pattern, label):
        m = re.search(pattern, text)
        if not m:
            die(f"could not read '{label}' out of the harness output")
        return int(m.group(1))

    return {
        "candidates": one(r"candidates:\s+(\d+)", "candidates"),
        "excluded_credit": one(r"excluded by 1 type=CREDIT\s+(\d+)", "excluded_credit"),
        "excluded_fee": one(r"excluded by 2 fee\s+(\d+)", "excluded_fee"),
        "excluded_installment": one(r"excluded by 3 installment\s+(\d+)", "excluded_installment"),
        "excluded_internal_transfer": one(
            r"excluded by 4 internal transfer\s+(\d+)", "excluded_internal_transfer"),
        "r1_runs": one(r"R1 anchors:\s+(\d+)", "r1_runs"),
        "r3_runs": one(r"R3 suggestions:\s+(\d+)", "r3_runs"),
    }


def run_engine():
    secret = os.environ.get("SYNC_SECRET")
    if not secret:
        env_path = os.path.join("supabase", "functions", ".env")
        if os.path.exists(env_path):
            for line in open(env_path):
                line = line.strip()
                if line.startswith("SYNC_SECRET="):
                    secret = line.partition("=")[2].strip().strip("'\"")
    if not secret:
        die("no SYNC_SECRET (set it, or provide supabase/functions/.env)")

    req = urllib.request.Request(
        f"{FUNCTIONS_URL}/run-detection",
        data=json.dumps({"today": TODAY}).encode(),
        headers={"Content-Type": "application/json", "x-sync-secret": secret},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            body = json.loads(resp.read())
    except urllib.error.HTTPError as e:
        die(f"run-detection returned {e.code}: {e.read().decode(errors='replace')[:400]}")
    except urllib.error.URLError as e:
        die(f"run-detection unreachable ({e.reason}). Is `supabase functions serve` running?")

    if not body.get("results"):
        die(f"run-detection returned no results: {json.dumps(body)[:400]}")
    return body["results"][0]["diagnostics"]


def main():
    rows = read_rows_from_db()
    if not rows:
        die("no transactions in the database — sync first")
    withdrawn = [r for r in rows if r["withdrawn_at"] is not None]
    live = [r for r in rows if r["withdrawn_at"] is None]

    print(f"  rows in database      {len(rows)}")
    print(f"  withdrawn (excluded)  {len(withdrawn)}   <- harness has no withdrawn filter")
    print(f"  compared              {len(live)}")
    print(f"  today                 {TODAY}\n")

    harness = run_harness(to_pluggy_shape(live))
    engine = run_engine()

    print(f"  {'metric':<30}{'harness':>10}{'engine':>10}   verdict")
    print("  " + "-" * 62)
    diverged = []
    for k in COMPARED:
        h, e = harness.get(k), engine.get(k)
        ok = h == e
        if not ok:
            diverged.append((k, h, e))
        print(f"  {k:<30}{h:>10}{e:>10}   {'ok' if ok else '*** DIVERGES ***'}")

    print()
    if diverged:
        print("  PARITY FAILED. Two implementations of one rule set disagree, so at")
        print("  least one is wrong. Do not ship until this is resolved.")
        for k, h, e in diverged:
            print(f"    {k}: harness={h} engine={e}")
        return 1

    print("  PARITY OK — both implementations agree on every compared count.")
    print("  Note this is agreement on counts over one ledger, not a proof. It is")
    print("  the check that caught the epsilon bug, not a substitute for the tests.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
