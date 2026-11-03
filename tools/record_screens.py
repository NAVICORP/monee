"""Records what the server answers for the demo book (tools/demo.sql), so the
screen pictures (app/test_screens) show real answers from the real database
rules, without a server running during the Flutter tests.

    python3 tools/record_screens.py app/test_screens/fixtures.json

Connects with the usual PG* settings (PGHOST, PGPORT, PGUSER, PGDATABASE).
Needs psycopg: pip install "psycopg[binary]".

The database functions take arguments that change with the screen and the
day, so each one is recorded for the arguments the screens send today, on
the book's own clock: this month, its calendar weeks, this year, the
category, card and entry the pictures open. Each answer is kept under the
function's name and its arguments as canonical JSON (sorted keys, no
spaces), the way app/test_screens/screens_test.dart looks them up, and the
first answer of each function also under its bare name, as a fallback.
Tables are recorded whole, as the demo user sees them.
"""
import calendar
import datetime as dt
import json
import sys

import psycopg

USER = 'dddddddd-0000-0000-0000-000000000001'
EMAIL = 'demo@skifi.co'
BOOK = 'dddddddd-0000-0000-0000-0000000000b1'

# The words typed into Search in the pictures (screens_test.dart reads them from here).
SEARCH = 'Salary'

# Tables the app reads with select(); recorded whole, as the demo user.
TABLES = ('account_groups', 'accounts', 'categories', 'tags', 'currency_rates', 'txns', 'txn_splits', 'txn_tags',
          'txn_photos', 'repeat_rules', 'instalment_plans', 'budgets', 'bookmarks', 'book_members', 'day_memos')

conn = psycopg.connect(autocommit=False)


def run(sql, args=None):
    """One statement as the demo user in the demo book, its first column."""
    with conn.cursor() as cur:
        claims = json.dumps({'sub': USER, 'role': 'authenticated', 'email': EMAIL})
        cur.execute("select set_config('request.jwt.claims', %s, true)", (claims,))
        cur.execute("select set_config('request.headers', %s, true)", (json.dumps({'x-farm-id': BOOK}),))
        cur.execute('set local role authenticated')
        cur.execute(sql, args)
        row = cur.fetchone()
    conn.commit()
    return row[0] if row else None


def canonical(args):
    return json.dumps(args, sort_keys=True, separators=(',', ':'), ensure_ascii=False)


# Each function's argument types by name, to call it by name as the API does.
with conn.cursor() as cur:
    cur.execute("""
      select p.proname, p.proargnames, array(select format_type(t, null) from unnest(p.proargtypes) t)
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public'""")
    SIGNATURES = {name: dict(zip(names or [], types)) for name, names, types in cur.fetchall()}
conn.commit()

out = {'book_id': BOOK, 'user_id': USER, 'email': EMAIL, 'search': SEARCH, 'picks': {}, 'rpc': {}, 'tables': {}}
missing = []


def rpc(fn, args=None):
    """Calls a function as the app does and keeps the answer for those arguments."""
    args = args or {}
    types = SIGNATURES[fn]
    parts, values = [], []
    for k, v in args.items():
        parts.append(f'"{k}" => %s::{types[k]}')
        values.append(json.dumps(v) if isinstance(v, (dict, list)) else v)
    value = run(f'select to_jsonb(public.{fn}({", ".join(parts)}))', values)
    key = f'{fn} {canonical(args)}'
    out['rpc'][key] = value
    out['rpc'].setdefault(fn, value)
    if value is None:
        missing.append(key)
    return value


def iso(d):
    return d.isoformat()


def day(s):
    return dt.date.fromisoformat(str(s)[:10])


# The book loads as the app loads it: catch_up first, so every answer after
# it is what a person opening the app today sees.
rpc('catch_up')
who = rpc('whoami')
book = next(b for b in who['books'] if b['book_id'] == BOOK)
today = day(book['today'])
out['today'] = iso(today)

# The book's periods, the same rules as Book in app/lib/core/book.dart.
MSD = int(book.get('month_start_day') or 1)
WS = int(book.get('week_start') or 0)
FYS = int(book.get('fy_start_month') or 1)


def month_day(y, m, d):
    y, m = y + (m - 1) // 12, (m - 1) % 12 + 1
    return dt.date(y, m, min(d, calendar.monthrange(y, m)[1]))


def month(y, m):
    first = month_day(y, m, MSD)
    nxt = month_day(y + 1, 1, MSD) if m == 12 else month_day(y, m + 1, MSD)
    return first, nxt - dt.timedelta(days=1)


def month_of(d):
    y, m = d.year, d.month
    if d < month_day(y, m, MSD):
        m -= 1
        if m < 1:
            y, m = y - 1, 12
    return y, m


def dow(d):
    """0 Sunday .. 6 Saturday, as Dart's weekday % 7."""
    return (d.weekday() + 1) % 7


def later(a, b):
    return a if a > b else b


def plus(d, n):
    return d + dt.timedelta(days=n)


m0, m1 = month(*month_of(today))
mon = {'date_from': iso(m0), 'date_to': iso(m1)}
fy_y, fy_m = month_of(today)
fy = fy_y if fy_m >= FYS else fy_y - 1
y0 = month(fy, FYS)[0]
y1 = plus(month(fy + 1, FYS)[0], -1)
year = {'date_from': iso(y0), 'date_to': iso(y1)}
g0 = plus(m0, -((dow(m0) - WS + 7) % 7))
g1 = plus(m1, 6 - (dow(m1) - WS + 7) % 7)
tomorrow = plus(today, 1)


def upcoming(a, b):
    """upcoming() as the lists ask for it: from tomorrow at the earliest."""
    start = later(a, tomorrow)
    return rpc('upcoming', {'date_from': iso(start), 'date_to': iso(b)}) if start <= b else None


# The Trans tab: the strip, Daily, Calendar, Monthly, Total and Note.
rpc('period_totals', {**mon, 'f': {}})
daily = rpc('txn_list', {**mon, 'f': {}, 'max_rows': 3000})
daily_up = upcoming(m0, m1) or []
rpc('day_totals', {'date_from': iso(g0), 'date_to': iso(g1), 'f': {}})
upcoming(g0, g1)
rpc('period_totals', {**year, 'f': {}})
months = rpc('span_totals', {**year, 'unit': 'month', 'f': {}}) or []
upcoming(y0, y1)
for s in months:
    if day(s['from']) <= today <= day(s['to']):
        rpc('span_totals', {'date_from': str(s['from'])[:10], 'date_to': str(s['to'])[:10], 'unit': 'week', 'f': {}})
rpc('budget_status', {**mon, 'period': 'month'})
rpc('period_accounts', dict(mon))
for kind in ('expense', 'income'):
    rpc('note_totals', {**mon, 'kind': kind, 'f': {}})
# The Home tab: six months of cash flow ending this month, and the latest entries.
hy, hm = month_of(today)
hm -= 5
while hm < 1:
    hm += 12
    hy -= 1
rpc('span_totals', {'date_from': iso(month(hy, hm)[0]), 'date_to': iso(m1), 'unit': 'month', 'f': {}})
rpc('txn_list', {**mon, 'f': {}, 'max_rows': 5})
rpc('category_totals', {**mon, 'kind': 'expense', 'f': {}})
# The filter page (this month, no filter) and a search.
rpc('txn_list', {**mon, 'f': {}, 'max_rows': 10000})
rpc('txn_list', {'date_from': iso(plus(today, -3650)), 'date_to': iso(plus(today, 400)), 'f': {'q': SEARCH}, 'max_rows': 500})

# The entry the pictures edit: the newest expense with a note in Daily, whose
# note no repeat still to come shares (those rows cannot be opened).
planned = {(u.get('note') or '').strip() for u in daily_up}
for t in daily:
    note = (t.get('note') or '').strip()
    if t.get('kind') == 'expense' and note and note not in planned:
        out['picks']['expense'] = {'id': t['id'], 'note': note}
        break

# The Stats tab: income and expense by category, and the top expense
# category's own page.
rpc('category_totals', {**mon, 'kind': 'income', 'f': {}})
spent = rpc('category_totals', {**mon, 'kind': 'expense', 'f': {}}) or {}
for r in spent.get('rows') or []:
    if r.get('category_id') and float(r.get('amount') or 0) > 0:
        emoji = (r.get('emoji') or '').strip()
        name = r.get('name') or ''
        out['picks']['category'] = {'id': r['category_id'], 'label': f'{emoji} {name}' if emoji else name}
        c = r['category_id']
        rpc('category_totals', {**mon, 'kind': 'expense', 'parent': c, 'f': {}})
        rpc('category_trend', {'kind': 'expense', 'category': c, 'months': 12, 'until': iso(m1), 'f': {}})
        rpc('txn_list', {**mon, 'f': {'categories': [c]}})
        break

# The Accounts tab, the first credit card it shows (hidden ones are left
# out there), that card's page, and the asset trend.
overview = rpc('accounts_overview', {'include_deleted': False}) or {}
cards = [a for g in overview.get('groups') or [] if g.get('kind') == 'card' and not g.get('hidden')
         for a in g.get('accounts') or [] if not a.get('hidden')]
for a in cards[:1]:
    out['picks']['card'] = {'id': a['id'], 'name': a['name']}
    rpc('balance_at', {'account': a['id'], 'until': iso(today)})
    rpc('account_trend', {'account': a['id'], 'months': 12})
    rpc('txn_list', {**mon, 'f': {'accounts': [a['id']]}})
    rpc('card_status', {'card': a['id']})
rpc('asset_trend', {'months': 12})

# More > Repeats: what comes next for each.
rpc('upcoming', {'date_from': iso(today), 'date_to': iso(plus(today, 400))})

# The tables, whole, as the demo user may read them (row security applies).
with conn.cursor() as cur:
    cur.execute("select table_name from information_schema.columns where table_schema = 'public' and column_name = 'book_id'")
    with_book = {r[0] for r in cur.fetchall()}
conn.commit()
for name in TABLES:
    where = ' where book_id = %s' if name in with_book else ''
    sql = f"select coalesce(json_agg(t), '[]'::json) from (select * from public.{name}{where}) t"
    out['tables'][name] = run(sql, (BOOK,) if where else None) or []

if missing:
    sys.exit('No answer for: ' + ', '.join(missing))
# Without one of these, only the picture that opens it fails.
for want in ('expense', 'category', 'card'):
    if want not in out['picks']:
        print(f'No {want} for the pictures to open today.', file=sys.stderr)
with open(sys.argv[1] if len(sys.argv) > 1 else 'app/test_screens/fixtures.json', 'w') as f:
    json.dump(out, f, indent=1, sort_keys=True)
p = out['picks']
opens = [p['category']['label'] if 'category' in p else None, p['card']['name'] if 'card' in p else None,
         f"the entry \"{p['expense']['note']}\"" if 'expense' in p else None]
print(f"Recorded the demo book for {today}: {len(out['rpc'])} answers, {len(out['tables']['txns'])} entries, "
      f"{len(daily)} this month. The pictures open {', '.join(x for x in opens if x)}.")
