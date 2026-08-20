#!/usr/bin/env python3
"""Fail if a SQL CHECK vocabulary disagrees with its TypeScript union or Swift enum.

The database is the source of truth, and this reads the vocabularies from the
*applied* schema rather than from the migration text: constraints arrive both in
create-table blocks and in later `alter table ... add column ... check`, and
tables get renamed along the way, so parsing the history is a parser that grows
a new blind spot with every migration. pg_get_constraintdef already normalises.

Feed it psql output on stdin:

  select rel.relname, att.attname, pg_get_constraintdef(c.oid) ...  -- see ci.yml

Every value the database permits must be a value the engine and the client can
name, and neither may name a value the database forbids. A vocabulary with no
entry in KNOWN is itself a failure: it means one was added without deciding who
else has to learn it.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# (table, column) -> (TypeScript type or None, Swift enum or None)
KNOWN = {
    ('subscription_run', 'status'): ('RunStatus', 'RunStatus'),
    # R5 is deliberately absent, and its absence is the rule rather than an
    # oversight: R5 claims a trailing charge onto an existing run, and un-claims
    # into a new run that anchors through standard R1. It never creates a run of
    # its own, so it never labels one -- the same reason R2 does not appear here.
    ('subscription_run', 'detected_by'): ('DetectedBy', 'DetectedBy'),
    ('subscription_run', 'billing_interval'): ('Interval', 'BillingInterval'),
    ('subscription', 'identification'): ('Identification', 'Identification'),
    ('connection', 'status'): (None, 'ConnectionStatus'),
    ('bank_account', 'status'): (None, 'AccountStatus'),
    ('bank_account', 'type'): (None, 'AccountType'),
    ('profiles', 'reminder_channels'): (None, 'ReminderChannels'),
    ('brand_catalog', 'kind'): (None, 'BrandKind'),
    # The raw chain is engine-internal: the client never decodes a transaction,
    # and the engine compares these as bare literals rather than a named union.
    ('transaction', 'status'): (None, None),
    ('transaction', 'type'): (None, None),
}


def read_schema(stream):
    """Parse `table<TAB>column<TAB>constraintdef` rows into {(table, col): values}.

    Only `= ANY (ARRAY[...])` constraints are vocabularies; a range or regex
    check quotes literals too and must not be mistaken for one.
    """
    found = {}
    for line in stream:
        parts = line.rstrip('\n').split('\t')
        if len(parts) != 3:
            continue
        table, column, definition = (p.strip() for p in parts)
        if '= ANY (ARRAY[' not in definition.replace('  ', ' '):
            continue
        found[(table, column)] = set(re.findall(r"'((?:[^']|'')*)'", definition))
    return found


def ts_union(name):
    for path in sorted((ROOT / 'backend/supabase/functions/_shared').glob('*.ts')):
        text = path.read_text()
        m = re.search(rf'^export type {name}\s*=\s*([^\n]+(?:\n\s*\|[^\n]+)*)', text, re.M)
        if m:
            return set(re.findall(r"'([^']*)'", m.group(1)))
    return None


def swift_enum(name):
    for path in sorted((ROOT / 'frontend/Signu').rglob('*.swift')):
        text = path.read_text()
        m = re.search(rf'\benum {name}\s*:\s*String[^{{]*\{{', text)
        if not m:
            continue
        depth, i = 0, m.end() - 1
        while i < len(text):
            if text[i] == '{':
                depth += 1
            elif text[i] == '}':
                depth -= 1
                if depth == 0:
                    break
            i += 1
        values = set()
        for case in re.finditer(r'case\s+(\w+)\s*(?:=\s*"([^"]*)")?', text[m.end():i]):
            values.add(case.group(2) or case.group(1))
        return values
    return None


def audit(schema):
    problems = []
    for key in sorted(set(schema) - set(KNOWN)):
        problems.append(
            f'{key[0]}.{key[1]}: new vocabulary {sorted(schema[key])} has no entry in '
            'KNOWN. Add one, naming the TypeScript union and Swift enum that must learn '
            'these values (or None, with a reason, if neither does).'
        )
    for key in sorted(set(KNOWN) - set(schema)):
        problems.append(
            f'{key[0]}.{key[1]}: mapped in KNOWN but the applied schema has no such '
            'vocabulary. It was dropped or renamed; update KNOWN.'
        )

    compared = 0
    for key, names in sorted(KNOWN.items()):
        expected = schema.get(key)
        if expected is None:
            continue
        for lang, name, extract in (
            ('TypeScript', names[0], ts_union),
            ('Swift', names[1], swift_enum),
        ):
            if name is None:
                continue
            actual = extract(name)
            if actual is None:
                problems.append(f'{key[0]}.{key[1]}: {lang} {name} not found.')
                continue
            compared += 1
            if actual != expected:
                detail = []
                if expected - actual:
                    detail.append(f'SQL permits {sorted(expected - actual)}, '
                                  f'{name} cannot name them')
                if actual - expected:
                    detail.append(f'{name} names {sorted(actual - expected)}, '
                                  'SQL forbids them')
                problems.append(f'{key[0]}.{key[1]} vs {lang}: ' + '; '.join(detail))
    return compared, problems


SELFTEST = """\
subscription_run\tstatus\tCHECK ((status = ANY (ARRAY['possible'::text, 'active'::text, \
'overdue'::text, 'ended'::text, 'cancelled'::text])))
subscription_run\tdetected_by\tCHECK ((detected_by = ANY (ARRAY['R1'::text, 'R3'::text, 'R4'::text])))
subscription_run\tbilling_interval\tCHECK ((billing_interval = ANY (ARRAY['monthly'::text, 'annual'::text])))
subscription\tidentification\tCHECK ((identification = ANY (ARRAY['auto'::text, 'user_confirmed'::text, 'user_renamed'::text])))
connection\tstatus\tCHECK ((status = ANY (ARRAY['active'::text, 'needs_action'::text, 'expired'::text, 'disconnected'::text])))
bank_account\tstatus\tCHECK ((status = ANY (ARRAY['active'::text, 'closed'::text])))
bank_account\ttype\tCHECK ((type = ANY (ARRAY['credit_card'::text, 'checking'::text])))
profiles\treminder_channels\tCHECK ((reminder_channels = ANY (ARRAY['push'::text, 'email'::text, 'both'::text])))
brand_catalog\tkind\tCHECK ((kind = ANY (ARRAY['service'::text, 'institution'::text])))
transaction\tstatus\tCHECK ((status = ANY (ARRAY['pending'::text, 'posted'::text])))
transaction\ttype\tCHECK ((type = ANY (ARRAY['DEBIT'::text, 'CREDIT'::text])))
charge\tamount\tCHECK ((amount > (0)::numeric))
"""


def selftest():
    """Prove the guard still fails when it should, without needing a database.

    A guard is only worth its green tick if its red is reachable, so each case
    below is a way the three languages can drift and must be caught.
    """
    import io as _io

    def run(text):
        return audit(read_schema(_io.StringIO(text)))[1]

    cases = [
        ('the checked-in truth agrees',
         SELFTEST, 0),
        ('SQL gains a status the app cannot name',
         SELFTEST.replace("'cancelled'::text]", "'cancelled'::text, 'paused'::text]"), 2),
        ('SQL gains R5',
         SELFTEST.replace("'R4'::text]", "'R4'::text, 'R5'::text]"), 2),
        ('an app names a value SQL forbids',
         SELFTEST.replace("'checking'::text]", "]"), 1),
        ('a brand-new vocabulary is unmapped',
         SELFTEST + "subscription\ttier\tCHECK ((tier = ANY (ARRAY['free'::text])))\n", 1),
        ('a mapped vocabulary disappeared',
         '\n'.join(l for l in SELFTEST.splitlines() if 'brand_catalog' not in l), 1),
    ]
    failures = 0
    for label, text, want in cases:
        got = run(text)
        ok = len(got) == want
        print(f'  {"ok  " if ok else "FAIL"} {label}: {len(got)} problem(s), expected {want}')
        if not ok:
            failures += 1
            for g in got:
                print(f'         {g}')
    if read_schema(_io.StringIO('')):
        print('  FAIL empty input produced vocabularies')
        failures += 1
    else:
        print('  ok   empty input yields nothing, which main() treats as failure')
    print('selftest: ' + ('every drift is caught' if not failures else f'{failures} case(s) wrong'))
    return 1 if failures else 0


def main():
    if '--selftest' in sys.argv:
        return selftest()
    schema = read_schema(sys.stdin)
    if not schema:
        print('no vocabularies on stdin; the query or the database is wrong')
        return 1
    compared, problems = audit(schema)
    print(f'{len(schema)} vocabularies in the applied schema, {compared} counterparts compared')
    if problems:
        print('\nVOCABULARY DRIFT')
        for p in problems:
            print('  ' + p)
        return 1
    print('every vocabulary agrees across SQL, TypeScript and Swift')
    return 0


if __name__ == '__main__':
    sys.exit(main())
