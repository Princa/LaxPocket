#!/usr/bin/env bash
# Applies the migrations to a throwaway database on a local Postgres (15+) and runs the
# row-level security checks. Uses the usual libpq settings (PGHOST, PGUSER, …); the user
# needs to be able to create databases and roles.
#
#   supabase/tests/run-local.sh
set -euo pipefail
cd "$(dirname "$0")/../.."

db="laxpocket_schema_test_$$"
createdb "$db"
trap 'dropdb --if-exists "$db"' EXIT

run() { psql -X -q -v ON_ERROR_STOP=1 -d "$db" "$@"; }

run -f supabase/tests/local_supabase_stub.sql
for migration in supabase/migrations/*.sql; do
  run -f "$migration"
done
run -f supabase/tests/rls_test.sql
