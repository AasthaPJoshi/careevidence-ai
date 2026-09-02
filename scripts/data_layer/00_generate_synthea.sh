#!/usr/bin/env bash
set -euo pipefail

# 00_generate_synthea.sh
# Downloads a PINNED Synthea release and generates a synthetic patient
# population as CSV, with a fixed seed so the same command always
# produces the same patients.
#
# The version is pinned to v3.2.0 (not "master-branch-latest") for two
# reasons:
#   1. OHDSI/ETL-Synthea, used in a later script to map this data into
#      OMOP CDM, only supports specific tagged Synthea versions.
#   2. Reproducibility: "same seed -> same patients, forever" only
#      holds if the generator itself doesn't silently change under us.
#
# Idempotent: re-running with the same SEED/POPULATION reuses the
# already-downloaded jar and produces the same patients again.

cd "$(dirname "$0")/../.."

SYNTHEA_VERSION="v3.2.0"
SYNTHEA_JAR_URL="https://github.com/synthetichealth/synthea/releases/download/${SYNTHEA_VERSION}/synthea-with-dependencies.jar"
SYNTHEA_JAR_PATH="data-raw/synthea-with-dependencies-${SYNTHEA_VERSION}.jar"

# Override with e.g. `SYNTHEA_POPULATION=200 bash scripts/data_layer/00_generate_synthea.sh`
# for a fast first smoke-test run before committing to the full 10,000.
SEED="${SYNTHEA_SEED:-20260901}"
POPULATION="${SYNTHEA_POPULATION:-10000}"
STATE="Massachusetts"
OUTPUT_DIR="data-raw/synthea_output"

# openjdk is keg-only (see scripts/setup/01_install_system_deps.sh);
# fall back to plain `java` if it's already resolvable some other way.
JAVA_BIN="/opt/homebrew/opt/openjdk/bin/java"
if [ ! -x "$JAVA_BIN" ]; then
  JAVA_BIN="java"
fi

if ! command -v "$JAVA_BIN" >/dev/null 2>&1 && [ "$JAVA_BIN" = "java" ]; then
  echo "✘ Java not found. It was installed in Phase 1 but may need a new"
  echo "  terminal session for PATH changes to take effect. Try opening a"
  echo "  new terminal tab and re-running this script."
  exit 1
fi

echo "==> Synthea version: ${SYNTHEA_VERSION} (pinned, not master-branch-latest)"
echo "==> Seed: ${SEED}   Clinician seed: ${SEED}   Population: ${POPULATION}   State: ${STATE}"

if [ ! -f "$SYNTHEA_JAR_PATH" ]; then
  echo "==> Downloading Synthea ${SYNTHEA_VERSION}"
  mkdir -p data-raw
  curl -L -o "$SYNTHEA_JAR_PATH" "$SYNTHEA_JAR_URL"
else
  echo "==> Synthea jar already present at ${SYNTHEA_JAR_PATH}, skipping download"
fi

mkdir -p "$OUTPUT_DIR"

echo "==> Running Synthea — this can take a while for larger populations"
"$JAVA_BIN" -jar "$SYNTHEA_JAR_PATH" \
  -s "$SEED" \
  -cs "$SEED" \
  -p "$POPULATION" \
  -c config/synthea.properties \
  --exporter.baseDirectory="${OUTPUT_DIR}/" \
  "$STATE"

echo "==> Writing generation manifest (this feeds the snapshot_id in the next script)"
cat > "${OUTPUT_DIR}/GENERATION_MANIFEST.txt" <<EOF
synthea_version=${SYNTHEA_VERSION}
synthea_jar_url=${SYNTHEA_JAR_URL}
seed=${SEED}
clinician_seed=${SEED}
population=${POPULATION}
state=${STATE}
generated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

echo ""
echo "==> Done. CSVs are in ${OUTPUT_DIR}/csv/"
echo "==> Before writing any loader code: open a few of those CSVs by hand"
echo "    and confirm they contain what you expect (patients.csv,"
echo "    encounters.csv, conditions.csv, medications.csv, etc.)."
echo "==> Proceed to 01_init_raw_schema.sh"
