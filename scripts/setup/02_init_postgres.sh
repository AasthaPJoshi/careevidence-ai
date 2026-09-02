#!/usr/bin/env bash
set -euo pipefail

# 02_init_postgres.sh
# Creates the careevidence database and the role matrix from
# docs/architecture.md section 12.2. Idempotent — safe to re-run.
#
# Same database and same roles are used for local dev and for the
# production-style deployment later; only host/credentials change.

cd "$(dirname "$0")/../.."

if [ ! -f .env ]; then
  echo "✘ .env not found. Copy .env.example to .env and fill in passwords first."
  exit 1
fi

set -a
source .env
set +a

echo "==> Waiting for PostgreSQL to accept connections"
until pg_isready -q; do
  sleep 1
done

echo "==> Creating database (if not present)"
psql postgres -v ON_ERROR_STOP=1 <<SQL
SELECT 'CREATE DATABASE careevidence'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'careevidence')\gexec
SQL

echo "==> Creating roles (if not present)"
psql postgres -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'careevidence_etl') THEN
    CREATE ROLE careevidence_etl LOGIN PASSWORD '${CAREEVIDENCE_ETL_PASSWORD}';
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'careevidence_analyst') THEN
    CREATE ROLE careevidence_analyst LOGIN PASSWORD '${CAREEVIDENCE_ANALYST_PASSWORD}';
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'careevidence_app') THEN
    CREATE ROLE careevidence_app LOGIN PASSWORD '${CAREEVIDENCE_APP_PASSWORD}';
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'careevidence_api') THEN
    CREATE ROLE careevidence_api LOGIN PASSWORD '${CAREEVIDENCE_API_PASSWORD}';
  END IF;
END
\$\$;

GRANT CONNECT ON DATABASE careevidence TO
  careevidence_etl, careevidence_analyst, careevidence_app, careevidence_api;
SQL

echo "==> Done. Schema-level grants (per table/schema) are created by the"
echo "    migration scripts in Phase 2 (data layer), not here — this script"
echo "    only establishes the logins."
echo ""
echo "==> Proceed to 03_init_r_project.sh"
