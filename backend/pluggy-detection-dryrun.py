#!/usr/bin/env python3
"""
Detection dry run — the harness behind v21 of subscription-tracker-data-model.md.

Applies the v21 detection doctrine to the transactions pluggy-probe.py captured,
before any engine exists, and reports what each rule would do:

  1. the v21 candidate filter (CREDIT / fee / installment / internal transfer)
  2. whether the three known false-positive sources survive it
  3. R1 anchors under v21 merchant_key derivation (CNPJ where present)
  4. R3 suggestions under the v21 date-alignment definition
  5. the collapse effect of merchant_key vs raw descriptors

Every number v21 asserts comes from here, so the claims stay reproducible rather
than remembered. It is also what caught the bug v21 documents: reading the fee
filter as a presence test excludes 146 of 258 rows and detects nothing, because
fee_type_additional_info is populated on 164/165 card rows ('NA' on 104).

Usage:
    python3 pluggy-detection-dryrun.py [pluggy-probe-raw.json]

WARNING — unlike pluggy-probe.py, this script's stdout is NOT paste-safe.
It prints merchant business names and amounts, because naming the pair that
anchors R1 is the whole point. pluggy-probe.py deliberately splits paste-safe
counts from a gitignored raw dump; this one cannot, so treat its output the way
you treat pluggy-probe-raw.json.

No dependencies beyond the Python 3 standard library.
"""

import sys
import json, re, statistics
from datetime import date
from collections import defaultdict, Counter

SRC = sys.argv[1] if len(sys.argv) > 1 else 'pluggy-probe-raw.json'
d=json.load(open(SRC))
ACCTS=list(d['transactions'])
def cents(x) -> int:
    """Money as integer cents. Never compare amounts with a float epsilon.

    abs(6.46 - 6.45) is 0.009999999999999787 in IEEE float, which slips under a
    `< 0.01` threshold and makes two amounts a cent apart compare EQUAL. That
    inflated this script's R1 anchor count from 1 to 2 on real data: the Valve
    charges of 6.46 and 6.45 are not the same amount, and R1 requires the same
    amount. Postgres `numeric`, which the engine will actually use, reports
    6.46 <> 6.45 correctly -- the discrepancy between this script and a SQL
    implementation of the same rule is what exposed it.
    """
    return int(round(abs(float(x)) * 100))


def money(r):
    """(currency, cents) -- the v25 comparison unit.

    Must stay identical to _shared/money.ts's sameMoney/moneyKey. Comparing cents
    alone is unsound once one merchant bills in two currencies, which is already
    true here: Valve charges under a single CNPJ in both BRL and USD. This harness
    lagged the TypeScript engine by one version and the two agreed only because no
    cross-currency amounts happen to collide in this data -- accidental parity,
    which is precisely what detection-parity.py now guards against.

    Reads either key so the same function serves Pluggy-shaped JSON
    (`currencyCode`) and database-shaped rows (`currency`).
    """
    cur = (r.get('currencyCode') or r.get('currency') or '').strip().upper()
    return (cur, cents(r['amount']))


def dt(r): return date.fromisoformat(str(r['date'])[:10])
def desc(r): return (r.get('description') or '').upper().strip()
def meta(r): return r.get('creditCardMetadata') or {}
def bn(r):
    m=r.get('merchant') or {}
    v=m.get('businessName')
    return v if v else None
def cnpj(r):
    m=r.get('merchant') or {}
    return m.get('cnpj') or None

AGGREGATORS={'PAYPAL'}
def is_aggregator(r):
    b=(bn(r) or '').upper()
    return any(a in b for a in AGGREGATORS)

def merchant_key(r):
    c=cnpj(r)
    if c:
        if is_aggregator(r):
            return f"{c}:{re.sub(r'[^A-Z0-9 ]',' ',desc(r)).strip()}"
        return c
    return re.sub(r'\s+',' ',desc(r)).strip()

rows=[(a,r) for a in ACCTS for r in d['transactions'][a]]

NOT_A_FEE={None,'','NA','N/A'}
def is_fee(r):
    v=meta(r).get('feeTypeAdditionalInfo')
    return v not in NOT_A_FEE
def is_inst(r):
    return (meta(r).get('installmentNumber') is not None
            or meta(r).get('totalInstallments') is not None
            or bool(re.search(r'\b\d{1,2}/\d{1,2}\b', desc(r))))
credits=[(a,r) for a,r in rows if r['type']=='CREDIT']
def is_internal(a,r):
    if r['type']!='DEBIT': return False
    for a2,c in credits:
        if a2!=a and money(c)==money(r) and abs((dt(c)-dt(r)).days)<=3:
            return True
    return False

excl=Counter(); cand=[]
for a,r in rows:
    if r['type']=='CREDIT': excl['1 type=CREDIT']+=1; continue
    if is_fee(r):           excl['2 fee']+=1; continue
    if is_inst(r):          excl['3 installment']+=1; continue
    if is_internal(a,r):    excl['4 internal transfer']+=1; continue
    cand.append((a,r))

print("="*70); print("  v21 CANDIDATE FILTER"); print("="*70)
print(f"  input rows: {len(rows)}")
for k in sorted(excl): print(f"    excluded by {k:<24} {excl[k]:>4}")
print(f"  candidates: {len(cand)}")

print("\n  targeted checks:")
for label, test in [("PAGAMENTO RECEBIDO  (card, CREDIT)", lambda r:'PAGAMENTO RECEBIDO' in desc(r)),
                    ("PAGAMENTO DE FATURA (checking, DEBIT)", lambda r:'PAGAMENTO DE FATURA' in desc(r)),
                    ("IOF lines", lambda r:'IOF' in desc(r))]:
    tot=sum(1 for a,r in rows if test(r)); left=sum(1 for a,r in cand if test(r))
    print(f"    {label:<40} {tot:>3} in data -> {left} surviving  {'OK' if left==0 else '*** LEAK ***'}")

print("\n"+"="*70); print("  R1 UNDER v21 merchant_key (CNPJ where present)"); print("="*70)
g=defaultdict(list)
for a,r in cand: g[merchant_key(r)].append(r)
fires=0
for k,v in sorted(g.items(), key=lambda x:-len(x[1])):
    v=sorted(v,key=dt)
    for i in range(len(v)):
        for j in range(i+1,len(v)):
            gap=(dt(v[j])-dt(v[i])).days
            if 25<=gap<=36 and money(v[i])==money(v[j]):
                nm=bn(v[i]) or k
                print(f"  R1 ANCHOR  {nm[:34]:<34} R${abs(v[i]['amount']):.2f}  "
                      f"{dt(v[i])} -> {dt(v[j])}  gap={gap}d")
                print(f"             descriptors: {desc(v[i])[:26]!r} / {desc(v[j])[:26]!r}")
                fires+=1
print(f"\n  R1 anchors: {fires}   (was 0 under descriptor keying)")

def circ_aligned(v):
    doms=[dt(x).day for x in v]
    med=statistics.median(doms)
    ok=sum(1 for x in doms if min(abs(x-med), 31-abs(x-med))<=3)
    return ok/len(doms)
print("\n"+"="*70); print("  R3 UNDER v21 DEFINITION (>=80% within +/-3d of circular median DOM)"); print("="*70)
r3=0
for k,v in sorted(((k,v) for k,v in g.items() if len(v)>=3), key=lambda x:-len(x[1])):
    v=sorted(v,key=dt)
    amts={money(x) for x in v}
    frac=circ_aligned(v)
    nm=bn(v[0]) or k
    if frac>=0.8 and len(amts)>1:
        r3+=1
        print(f"  R3 SUGGEST {nm[:32]:<32} n={len(v)} aligned={frac:.0%} DOMs={sorted({dt(x).day for x in v})}")
    else:
        print(f"  rejected   {nm[:32]:<32} n={len(v)} aligned={frac:.0%}")
print(f"\n  R3 suggestions: {r3}   (was 1 false positive under the loose reading)")

print("\n"+"="*70); print("  merchant_key EFFECT"); print("="*70)
dk=len({re.sub(r'\s+',' ',desc(r)).strip() for a,r in cand})
print(f"  distinct descriptors among candidates : {dk}")
print(f"  distinct v21 merchant_key            : {len(g)}")
agg=[k for k in g if ':' in k and k.split(':')[0].isdigit()]
print(f"  aggregator-split keys (PayPal etc.)  : {len(agg)}")
