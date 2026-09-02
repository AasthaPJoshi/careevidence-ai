#!/usr/bin/env bash
set -euo pipefail

# 04_verify_setup.sh
# Confirms R, renv, and PostgreSQL connectivity all work together
# before Phase 2 (data layer) starts.

cd "$(dirname "$0")/../.."

if [ ! -f .env ]; then
  echo "✘ .env not found. Copy .env.example to .env and fill in passwords first."
  exit 1
fi

set -a
source .env
set +a

Rscript -e '
  cat("R version:      ", R.version.string, "\n")
  cat("renv active:    ", !is.null(renv::project()), "\n")

  library(DBI)
  con <- dbConnect(
    RPostgres::Postgres(),
    host     = Sys.getenv("PGHOST"),
    port     = as.integer(Sys.getenv("PGPORT")),
    dbname   = Sys.getenv("PGDATABASE"),
    user     = "careevidence_etl",
    password = Sys.getenv("CAREEVIDENCE_ETL_PASSWORD")
  )
  cat("Postgres:       ", dbGetQuery(con, "SELECT version();")[[1]], "\n")
  dbDisconnect(con)

  cat("\n✔ Environment verified — ready for Phase 2 (data layer).\n")
'
