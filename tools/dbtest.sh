#!/usr/bin/env bash
# Runs the database tests on a scratch Postgres: platform pieces, every
# migration, the tests, and the demo book. Uses PG* from the environment.
set -euo pipefail
cd "$(dirname "$0")/.."
db=${PGDATABASE:-monee}
dropdb --if-exists "$db" >/dev/null 2>&1 || true
createdb "$db"
psql -d "$db" -v ON_ERROR_STOP=1 -q -f supabase/tests/platform.sql
for f in supabase/migrations/*.sql; do psql -d "$db" -v ON_ERROR_STOP=1 -q -1 -f "$f"; done
for t in supabase/tests/*_test.sql; do
  echo "== $t"
  psql -d "$db" -v ON_ERROR_STOP=1 -q -f "$t" 2>&1 | grep -E "NOTICE|ERROR|CONTEXT" | sed 's/^psql:[^:]*:[0-9]*: //'
done
if [ -f tools/demo.sql ]; then
  psql -d "$db" -v ON_ERROR_STOP=1 -q -f tools/demo.sql > /dev/null && echo "demo book loads"
fi
