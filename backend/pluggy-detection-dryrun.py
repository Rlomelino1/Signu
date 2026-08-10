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
def dt(r): return date.fromisoformat(str(r['date'])[:10])
def desc(r): return (r.get('description') or '').upper().strip()
def meta(r): return r.get('creditCardMetadata') or {}
def bn(r):
    m=r.get('merchant') or {}
    v=m.get('businessName')
    return v if v else None                      # '' -> None  (v21)
def cnpj(r):
    m=r.get('merchant') or {}
    return m.get('cnpj') or None

AGGREGATORS={'PAYPAL'}                            # v21 aggregator list
def is_aggregator(r):
    b=(bn(r) or '').upper()
    return any(a in b for a in AGGREGATORS)

def merchant_key(r):                              # v21 derivation
    c=cnpj(r)
    if c:
        if is_aggregator(r):
            return f"{c}:{re.sub(r'[^A-Z0-9 ]',' ',desc(r)).strip()}"
        return c
    return re.sub(r'\s+',' ',desc(r)).strip()     # case+whitespace only

rows=[(a,r) for a in ACCTS for r in d['transactions'][a]]

# ---- v21 candidate filter ----
NOT_A_FEE={None,'','NA','N/A'}   # v21: 'NA' is the institution's not-applicable sentinel
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
        if a2!=a and abs(abs(c['amount'])-abs(r['amount']))<0.01 and abs((dt(c)-dt(r)).days)<=3:
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

# ---- did the known offenders get removed? ----
print("\n  targeted checks:")
for label, test in [("PAGAMENTO RECEBIDO  (card, CREDIT)", lambda r:'PAGAMENTO RECEBIDO' in desc(r)),
                    ("PAGAMENTO DE FATURA (checking, DEBIT)", lambda r:'PAGAMENTO DE FATURA' in desc(r)),
                    ("IOF lines", lambda r:'IOF' in desc(r))]:
    tot=sum(1 for a,r in rows if test(r)); left=sum(1 for a,r in cand if test(r))
    print(f"    {label:<40} {tot:>3} in data -> {left} surviving  {'OK' if left==0 else '*** LEAK ***'}")

# ---- R1 under v21 keying ----
print("\n"+"="*70); print("  R1 UNDER v21 merchant_key (CNPJ where present)"); print("="*70)
g=defaultdict(list)
for a,r in cand: g[merchant_key(r)].append(r)
fires=0
for k,v in sorted(g.items(), key=lambda x:-len(x[1])):
    v=sorted(v,key=dt)
    for i in range(len(v)):
        for j in range(i+1,len(v)):
            gap=(dt(v[j])-dt(v[i])).days
            if 25<=gap<=36 and abs(abs(v[i]['amount'])-abs(v[j]['amount']))<0.01:
                nm=bn(v[i]) or k
                print(f"  R1 ANCHOR  {nm[:34]:<34} R${abs(v[i]['amount']):.2f}  "
                      f"{dt(v[i])} -> {dt(v[j])}  gap={gap}d")
                print(f"             descriptors: {desc(v[i])[:26]!r} / {desc(v[j])[:26]!r}")
                fires+=1
print(f"\n  R1 anchors: {fires}   (was 0 under descriptor keying)")

# ---- R3 with the v21 alignment definition ----
def circ_aligned(v):
    doms=[dt(x).day for x in v]
    med=statistics.median(doms)
    ok=sum(1 for x in doms if min(abs(x-med), 31-abs(x-med))<=3)
    return ok/len(doms)
print("\n"+"="*70); print("  R3 UNDER v21 DEFINITION (>=80% within +/-3d of circular median DOM)"); print("="*70)
r3=0
for k,v in sorted(((k,v) for k,v in g.items() if len(v)>=3), key=lambda x:-len(x[1])):
    v=sorted(v,key=dt)
    amts={round(abs(x['amount']),2) for x in v}
    frac=circ_aligned(v)
    nm=bn(v[0]) or k
    if frac>=0.8 and len(amts)>1:
        r3+=1
        print(f"  R3 SUGGEST {nm[:32]:<32} n={len(v)} aligned={frac:.0%} DOMs={sorted({dt(x).day for x in v})}")
    else:
        print(f"  rejected   {nm[:32]:<32} n={len(v)} aligned={frac:.0%}")
print(f"\n  R3 suggestions: {r3}   (was 1 false positive under the loose reading)")

# ---- merchant_key collapse effect ----
print("\n"+"="*70); print("  merchant_key EFFECT"); print("="*70)
dk=len({re.sub(r'\s+',' ',desc(r)).strip() for a,r in cand})
print(f"  distinct descriptors among candidates : {dk}")
print(f"  distinct v21 merchant_key            : {len(g)}")
agg=[k for k in g if ':' in k and k.split(':')[0].isdigit()]
print(f"  aggregator-split keys (PayPal etc.)  : {len(agg)}")
