#!/usr/bin/env bash
# Starts PostgREST (in Docker) in front of a fresh database with the migrations applied, like
# a Supabase project minus Auth, and prints the LAXPOCKET_E2E_* variables the Swift sync
# test needs. Used by CI; also handy locally:
#
#   eval "$(supabase/tests/start-postgrest.sh)"
#   (cd Core && swift test --filter CloudSyncIntegrationTests)
#
# Needs a local Postgres you can create databases and roles on (libpq env vars), Docker and python3.
set -euo pipefail
cd "$(dirname "$0")/../.."

db="${LAXPOCKET_E2E_DB:-laxpocket_e2e}"
port="${LAXPOCKET_E2E_PORT:-3000}"
image="${POSTGREST_IMAGE:-postgrest/postgrest:v12.2.3}"
secret="laxpocket-e2e-secret-at-least-32-characters-long"
password="laxpocket-e2e"

# An earlier PostgREST would hold connections to the database we're about to recreate.
docker rm -f laxpocket-postgrest >/dev/null 2>&1 || true
dropdb --if-exists "$db" >&2
createdb "$db" >&2
run() { psql -X -q -v ON_ERROR_STOP=1 -d "$db" "$@" >&2; }
run -f supabase/tests/local_supabase_stub.sql
for migration in supabase/migrations/*.sql; do run -f "$migration"; done
run <<SQL
do \$\$
begin
  if not exists (select 1 from pg_roles where rolname = 'authenticator') then
    create role authenticator login noinherit;
  end if;
end
\$\$;
alter role authenticator password '$password';
grant anon, authenticated to authenticator;
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000000e1', 'e2e-a@example.com'),
  ('00000000-0000-4000-8000-0000000000e2', 'e2e-b@example.com');
SQL

docker run -d --name laxpocket-postgrest --network host \
  -e PGRST_DB_URI="postgres://authenticator:$password@${PGHOST:-127.0.0.1}:${PGPORT:-5432}/$db" \
  -e PGRST_DB_SCHEMAS=public \
  -e PGRST_DB_ANON_ROLE=anon \
  -e PGRST_JWT_SECRET="$secret" \
  -e PGRST_SERVER_PORT="$port" \
  -e PGRST_LOG_LEVEL="${PGRST_LOG_LEVEL:-error}" \
  "$image" >&2

for _ in $(seq 1 30); do
  curl -fsS "http://127.0.0.1:$port/" >/dev/null 2>&1 && break
  sleep 1
done
curl -fsS "http://127.0.0.1:$port/" >/dev/null || { docker logs laxpocket-postgrest >&2; exit 1; }

token() {
  python3 - "$secret" "$1" <<'PY'
import base64, hashlib, hmac, json, sys
secret, sub = sys.argv[1], sys.argv[2]
enc = lambda b: base64.urlsafe_b64encode(b).rstrip(b"=").decode()
header = enc(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
payload = enc(json.dumps({"sub": sub, "role": "authenticated", "exp": 4102444800}).encode())
sig = enc(hmac.new(secret.encode(), f"{header}.{payload}".encode(), hashlib.sha256).digest())
print(f"{header}.{payload}.{sig}")
PY
}

echo "export LAXPOCKET_E2E_REST_URL=http://127.0.0.1:$port"
echo "export LAXPOCKET_E2E_TOKEN_A=$(token 00000000-0000-4000-8000-0000000000e1)"
echo "export LAXPOCKET_E2E_TOKEN_B=$(token 00000000-0000-4000-8000-0000000000e2)"
echo "export LAXPOCKET_E2E_EMAIL_B=e2e-b@example.com"
