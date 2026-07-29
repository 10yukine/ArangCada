#!/usr/bin/env bash
#
# Rebuild a throwaway test database from scratch and run the pgTAP suite.
#
# Runs against a local PostgreSQL 16 + PostGIS + pgTAP install (WSL Ubuntu).
# No Docker and no Supabase CLI required.
#
# To run without a sudo password prompt, give your OS user a Postgres role
# once:
#
#   sudo -u postgres psql -c "create role $(whoami) superuser login;"
#
# Superuser is needed because the script creates databases and installs the
# postgis and pgtap extensions. This is a throwaway local test database; do
# not grant a role like this on a shared or hosted instance.
#
#   Usage:  bash scripts/run_db_tests.sh [dbname]
#
# The database is dropped and recreated on every run, so the result is a clean
# reflection of supabase/migrations/ + supabase/seed.sql and nothing else.

set -euo pipefail

DB="${1:-arangcada_test}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Connect directly when the invoking user has a Postgres role with the rights
# this script needs; that path involves no sudo and so no password prompt. Fall
# back to sudo -u postgres where that role does not exist, so the script keeps
# working on a fresh machine.
#
# -w on the probe matters: without it psql prompts for a password and the script
# hangs instead of falling through to the sudo path.
if psql -w -d postgres -tAc 'select 1' >/dev/null 2>&1; then
  PSQL=(psql -v ON_ERROR_STOP=1 -q)
  PG_PROVE=(pg_prove)
  echo "==> Connecting as $(whoami)"
else
  PSQL=(sudo -u postgres psql -v ON_ERROR_STOP=1 -q)
  PG_PROVE=(sudo -u postgres pg_prove)
  echo "==> Connecting as postgres via sudo"
fi

echo "==> Rebuilding database: $DB"
"${PSQL[@]}" -d postgres -c "drop database if exists $DB;"
"${PSQL[@]}" -d postgres -c "create database $DB;"
"${PSQL[@]}" -d "$DB" -c "create extension if not exists postgis; create extension if not exists pgtap;"

echo "==> Applying local auth shim"
"${PSQL[@]}" -d "$DB" -f "$ROOT/supabase/tests/00_bootstrap_local.sql"

echo "==> Applying migrations"
for migration in "$ROOT"/supabase/migrations/*.sql; do
  echo "    - $(basename "$migration")"
  "${PSQL[@]}" -d "$DB" -f "$migration"
done

echo "==> Applying seed"
"${PSQL[@]}" -d "$DB" -f "$ROOT/supabase/seed.sql"

echo "==> Running pgTAP suite"
shopt -s nullglob
tests=("$ROOT"/supabase/tests/*_test.sql)
if [ ${#tests[@]} -eq 0 ]; then
  echo "    (no *_test.sql files found)"
  exit 0
fi
"${PG_PROVE[@]}" --failures -d "$DB" "${tests[@]}"
