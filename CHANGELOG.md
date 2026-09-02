# Changelog

All notable changes to this project are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/) — `v0.1.0`
marks the first usable MVP (per `docs/architecture.md` §14), `v1.0.0`
marks portfolio-complete. Study documents (`protocol.md`, `sap.md`) are
versioned separately via their own `protocol-vN` / `sap-vN` tags, since
they follow ICH M14 documentation practice, not software semver.

## [Unreleased]

### Added
- Study protocol v1 (`docs/protocol.md`), tagged `protocol-v1` —
  drafted and committed before any Synthea data was generated
- System architecture blueprint (`docs/architecture.md`)
- Local development environment: R, PostgreSQL 16 with a least-privilege
  role matrix, renv-locked dependencies, VS Code configuration
- Synthea generation script, pinned to `v3.2.0` for reproducibility and
  OHDSI/ETL-Synthea compatibility
- Project scaffolding: license, CI shell-lint workflow, issue/PR templates
