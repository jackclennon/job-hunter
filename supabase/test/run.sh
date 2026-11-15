#!/usr/bin/env bash
# Applies the migrations to a throwaway local Postgres with a Supabase stub and runs checks.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PGBIN="${PGBIN:-$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -1)}"
DIR="$(mktemp -d)"
PORT="${PGPORT_TEST:-54329}"
RUNAS=()
if [ "$(id -u)" = 0 ]; then chown postgres "$DIR"; RUNAS=(runuser -u postgres --); fi
cleanup() { "${RUNAS[@]}" "$PGBIN/pg_ctl" -D "$DIR/data" stop -m immediate >/dev/null 2>&1 || true; rm -rf "$DIR"; }
trap cleanup EXIT
"${RUNAS[@]}" "$PGBIN/initdb" -D "$DIR/data" -A trust -U postgres >/dev/null
"${RUNAS[@]}" "$PGBIN/pg_ctl" -D "$DIR/data" -o "-p $PORT -k $DIR -c listen_addresses=''" -l "$DIR/log" start -w >/dev/null
PSQL=(psql -h "$DIR" -p "$PORT" -U postgres -d postgres -v ON_ERROR_STOP=1 -q -X)
"${PSQL[@]}" -f "$HERE/stub_supabase.sql"
for f in "$HERE"/../migrations/*.sql; do "${PSQL[@]}" -f "$f"; done
OUT="$("${PSQL[@]}" -A -t -F ' | ' -f "$HERE/checks.sql")"
echo "$OUT"
if grep -q '| f$' <<<"$OUT"; then echo "FAIL"; exit 1; fi
echo "All database checks passed."
