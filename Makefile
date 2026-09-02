.PHONY: setup check-prereqs install-deps init-db init-r verify

## Run the full Phase 1 environment setup, in order
setup: check-prereqs install-deps init-db init-r verify

check-prereqs:
	bash scripts/setup/00_check_prerequisites.sh

install-deps:
	bash scripts/setup/01_install_system_deps.sh

init-db:
	bash scripts/setup/02_init_postgres.sh

init-r:
	bash scripts/setup/03_init_r_project.sh

verify:
	bash scripts/setup/04_verify_setup.sh

# Phase 2+ targets (data layer, cohort, RWE, ML, product, ops) get added
# here as each phase's scripts/<phase>/ folder is built.
