#!/usr/bin/env bash
set -euo pipefail

# 03_init_r_project.sh
# Initializes renv (R's per-project dependency lock, the equivalent of
# a Python venv + requirements.txt) and installs the core packages
# needed for this phase's verification step and for Phase 2.
#
# A CRAN mirror is set explicitly in every call below (in addition to
# the project's .Rprofile) because the Homebrew-cask R build does not
# preset one, and install.packages() has nowhere to download from
# otherwise.

cd "$(dirname "$0")/../.."

CRAN_OPT='options(repos = c(CRAN = "https://cloud.r-project.org"))'

echo "==> Ensuring renv is installed"
Rscript -e "$CRAN_OPT; if (!requireNamespace('renv', quietly = TRUE)) install.packages('renv')"

echo "==> Initializing renv for this project (bare = no auto-detected deps yet)"
Rscript -e "$CRAN_OPT; renv::init(bare = TRUE)"

echo "==> Installing core packages"
Rscript -e "$CRAN_OPT; renv::install(c(
  'DBI',
  'RPostgres',
  'dbplyr',
  'dplyr',
  'here',
  'dotenv',
  'targets',
  'testthat',
  'httpgd',
  'languageserver'
))"

echo "==> Locking dependency versions to renv.lock"
Rscript -e "$CRAN_OPT; renv::snapshot(prompt = FALSE)"

echo ""
echo "==> renv.lock written — this file gets committed to git."
echo "==> Proceed to 04_verify_setup.sh"
