#!/usr/bin/env bash
#
# Rebuild a throwaway test database from scratch and run the pgTAP suite.
#
# Runs against a local PostgreSQL 16 + PostGIS + pgTAP install (WSL Ubuntu).
# No Docker and no Supabase CLI required.
#
#   Usage:  bash scripts/run_db_tests.sh [dbname]
#
# The database is dropped and recreated on every run, so the result is a clean
# reflection of supabase/migrations/ + supabase/seed.sql and nothing else.

set -euo pipefail

DB="${1:-arangcada_test}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PSQL=(sudo -u postgres psql -v ON_ERROR_STOP=1 -q)

echo "==> Rebuilding database: $DB"
"${PSQL[@]}" -c "drop database if exists $DB;"
"${PSQL[@]}" -c "create database $DB;"
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
sudo -u postgres pg_prove --failures -d "$DB" "${tests[@]}"
