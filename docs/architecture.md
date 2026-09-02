# CareEvidence AI — System Blueprint v1.0

**Prepared as:** lead architect / senior RWE analyst review of the project spec
**Date:** September 2026
**Status:** design-locked, pre-implementation
**Repo destination:** `docs/architecture.md` + `docs/adr/`

---

## 0. Read this first — five changes I am making to your spec

Your spec is genuinely strong. It already separates estimation from prediction, versions the cohort, and treats leakage as a first-class test. That is more than most portfolio projects and more than some junior analysts in industry. But five things need to change before a line of code is written.

### 0.1 Synthea has no confounding and no treatment effect — this is the critical issue

Synthea generates patients from a rules engine. Exposure is not assigned by confounded clinical judgment, and there is no true causal effect of drug A vs drug B on readmission. If you run a propensity-score-adjusted analysis on raw Synthea and report "adjusted HR 0.87 (0.74–1.02)", any RWE hiring manager who has done this work will know the number is meaningless, and you will not be able to defend it.

**The fix makes the project stronger, not weaker.** Restructure the RWE arm as a *method-validation study with known ground truth*:

1. Build a **data-generating overlay** on top of Synthea: a documented, seeded script that assigns exposure as a function of measured covariates (introducing confounding you control) and generates outcomes under a **known true hazard ratio** — e.g. true HR = 0.75.
2. Show the **crude** estimate is biased (e.g. HR 1.10 because sicker patients got the drug).
3. Show your **adjusted** estimate recovers the truth (e.g. HR 0.76, 95% CI 0.66–0.87).
4. Add **negative control outcomes** — outcomes the exposure cannot plausibly cause, where the true HR is 1.0 — and use `EmpiricalCalibration` to show your p-values and CIs are calibrated.
5. Add **positive controls** at known effect sizes (HR 1.5, 2.0, 4.0) and plot estimated vs true.

This converts "I ran a propensity model" into "I built a study pipeline and demonstrated it recovers known truth, with calibrated uncertainty." That is what OHDSI methods papers do. Almost no portfolio project does it. It is your single biggest differentiator and it costs about four extra days.

The alternative — a second, honest framing you can also state — is: "the RWE arm demonstrates protocol, cohort, balance and estimation *machinery*; effect estimates on synthetic data are not clinically interpretable and are labelled as such throughout." State this in the README regardless. But do the ground-truth version if you have the time.

### 0.2 Standardize to OMOP CDM, not hand-rolled `core_*` tables

Your spec's `core_patient / core_encounter / core_condition` layer is a bespoke schema. Real RWE teams do not build bespoke schemas — they map to **OMOP CDM 5.4** and then run standardized analytics against it. Mapping Synthea → OMOP is a solved, documented ETL, and once you are on OMOP you inherit an entire ecosystem for free: cohort definitions, characterization, incidence/prevalence, drug utilisation, survival, patient-level prediction, and data quality.

This is a **large** employability difference. "Built custom healthcare tables" is a data-engineering claim. "Mapped a source to OMOP CDM 5.4 and executed a standardized RWE study against it" is an RWE claim, and RWE is the job title you want.

Your `raw_*` layer stays. Your `cohort_*`, `analysis_result`, `model_registry`, `pipeline_run`, `audit_event` tables stay — those are your study-results schema and OMOP does not cover them.

### 0.3 Build the study to ICH M14 structure

ICH M14 came into effect 18 March 2026 and is the first internationally harmonized guideline for non-interventional RWD studies. It requires: question first (not dataset first), a documented **fitness-for-use** assessment of the data source, **two-phase feasibility** (preliminary screen, then detailed assessment against a draft protocol), a protocol and SAP written *before* analysis with documented design rationale, and structured reporting.

Your repo should contain `docs/protocol.md` and `docs/sap.md` written and git-tagged **before** the first estimate is produced, and the commit history should prove it. That timestamp is evidence. It is also the single easiest thing to talk about in an interview.

### 0.4 DuckDB for development, PostgreSQL for production

Running CI against a live Postgres is slow and flaky. `CDMConnector` speaks both DuckDB and Postgres against the same CDM reference object. Develop and test against a DuckDB file (fast, zero-infra, commits to CI), deploy against Postgres. Same code path, one env var. This is a real production pattern and it will save you hours of CI pain.

### 0.5 Scope is roughly 5× too large for one project

Your 24-section spec is 400–600 hours as written. Section 14 defines a ruthless MVP. Build the MVP, tag `v0.1`, and only then extend. A finished narrow project beats an abandoned broad one, and an abandoned repo is worse than no repo.

---

## 1. Project Vision

### 1.1 What CareEvidence AI is

CareEvidence AI is a **reproducible real-world evidence and clinical risk platform**. It takes longitudinal patient-level healthcare data (encounters, diagnoses, drugs, procedures, labs, costs), standardizes it to a common data model, and supports two distinct and deliberately separated analytical products:

1. **Population evidence** — "does exposure A vs exposure B change the rate of hospitalization?" — an association/effect question, answered with a versioned protocol, confounding adjustment, survival analysis, negative controls and calibrated uncertainty.
2. **Patient risk prediction** — "which patients discharged today are likely to be readmitted within 30 days?" — a forecasting question, answered with a leakage-safe, calibrated, subgroup-audited, version-pinned model served over an API.

The platform delivers both through governed artifacts: a study report, a model card, a dashboard, and a versioned API — each traceable to a data snapshot, a cohort version, a commit SHA and a dependency lockfile.

### 1.2 The problem it solves

Healthcare organizations sit on longitudinal EHR and claims data and repeatedly fail to turn it into decisions, for four structural reasons:

| Problem | What it looks like in practice | What CareEvidence does |
|---|---|---|
| **Undefined cohorts** | "Diabetic patients" means something different in every analysis; no one can reproduce last quarter's number | Versioned, human-readable cohort protocol; cohort SQL derived from it; attrition funnel published |
| **Confounding treated as noise** | Crude rate comparisons presented as if causal; sicker patients got the drug | New-user active-comparator design, PS adjustment, balance diagnostics, negative controls |
| **Prediction and causation conflated** | A readmission risk score is used to argue an intervention "works" | Two physically separate engines, two report types, explicit language guardrails in the UI and API |
| **Analysis that cannot be re-run** | Ad hoc scripts on a laptop; results irreproducible six months later | `targets` pipeline, `renv` lockfile, snapshot IDs, containerized, CI-verified clean-clone reproduction |

### 1.3 Who it is for

A mid-size **integrated delivery network / payer analytics team**, or the **HEOR/RWE function of a pharma or device company**. Both need auditable population evidence *and* operational risk scores, from the same data, under the same governance.

### 1.4 Primary users and stakeholders

| Stakeholder | Cares about | Primary surface |
|---|---|---|
| RWE / epidemiology analyst | Cohort validity, balance, sensitivity analyses, calibration of estimates | Quarto study report, cohort diagnostics |
| Biostatistician | SAP adherence, model assumptions, CIs, multiplicity, PH assumption | Study report + reproducible analysis code |
| Medical data scientist | Feature timing, leakage, discrimination, calibration, drift | Model validation report, model registry |
| Clinical operations manager | Which discharges to prioritize today, at what threshold, at what workload | Shiny risk view + API |
| Medical director / clinical lead | Is this credible, what are the limits, what is intended use | Executive summary + model card |
| Data governance / privacy | De-identification, least-privilege, audit trail, no PHI in logs | Privacy doc, DB role matrix, audit tables |
| Platform / MLOps engineer | Deployability, health, versioning, rollback | Docker, CI, monitoring endpoints |

---

## 2. Real-World Use Cases

Six concrete use cases. **UC-1, UC-2, UC-5 are MVP.** The rest are V1/V2.

**UC-1 — Comparative safety/effectiveness study (RWE core).**
New users of drug class A vs active comparator B. Outcome: first all-cause hospitalization within 365 days. Design: new-user active-comparator, 365-day washout, PS-matched. Deliverable: M14-structured study report with crude and adjusted HR, KM curves, balance table, negative-control calibration plot, sensitivity analyses.

**UC-2 — 30-day readmission risk stratification (medical ML core).**
At the moment of discharge from an index admission, score the probability of unplanned readmission within 30 days. Deliverable: calibrated model, threshold chosen for a stated operational capacity (e.g. "care management can call 60 patients/week"), served via API, monitored for drift.

**UC-3 — Incidence and prevalence surveillance.**
Annual incidence rate of a condition per 100,000 person-years, by age band and sex, with denominator cohorts constructed on required prior observation. Directly answers the most common HEOR interview question ("how do you build a denominator?").

**UC-4 — Drug utilisation and adherence.**
Treatment initiation, duration of exposure, PDC/MPR adherence, discontinuation and switching patterns. This is the exact deliverable in payer/HEOR job descriptions.

**UC-5 — Utilization and cost burden.**
Per-patient-per-year admissions, ED visits, and cost, comparing cohorts, with the count/cost distribution handled honestly (zero-inflation, right skew) rather than with a t-test on means.

**UC-6 — Data quality / fitness-for-use gate.**
Before any study runs, a fitness-for-use assessment on the data source: completeness of key variables, plausibility, temporal stability, and whether the exposure/outcome/covariates of the protocol can actually be operationalized. This is M14's two-phase feasibility, implemented. Blocks the pipeline if it fails.

---

## 3. Users & Roles

| Role | Auth | DB privileges | Can see | Can do |
|---|---|---|---|---|
| **Public/demo viewer** | none (demo mode) | none — reads pre-computed artifacts only | Aggregate results, KM curves, model metrics, model card | Nothing that touches patient rows |
| **Analyst** | API key / session | `careevidence_read` on `results` + `cdm` schemas | Cohort diagnostics, patient-level listings within study cohort, full report | Re-run parameterized reports; propose a new cohort version |
| **Data scientist** | API key | read on `cdm`, write on `features`, `model_registry` | Feature tables, model artifacts, drift metrics | Train, register, promote a challenger model |
| **Clinical ops user** | session | none — API only | Risk-scored worklist for their unit, threshold explanation | Export worklist; record a triage disposition |
| **Governance reviewer** | session | read on `audit_event`, `pipeline_run` | Version lineage, run history, DQ status, access log | Freeze a study version; revoke a model |
| **Pipeline service account** | secret from env/Secrets Manager | `careevidence_etl` — write to `raw`, `cdm`, `results` | n/a | Run ETL, cohort generation, analysis, training |
| **Admin** | separate credential | owner | everything | Migrations, role grants |

**Design rule enforced in code:** the Shiny app connects with a **read-only** role and can never mutate a cohort definition. Dashboard filters are *display* filters over pre-computed results; they cannot silently redefine the study population. This is the difference between a dashboard and a research artifact, and I want it enforced at the database-grant level, not by convention.

---

## 4. Complete Architecture

### 4.1 System diagram

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ LAYER 0 — SOURCE                                                             │
│                                                                              │
│  Synthea generator          Ground-truth overlay          Vocabulary         │
│  (CSV / FHIR export)        (seeded exposure +            (Athena concept    │
│   patients, encounters,      outcome injection with        subset, redistrib-│
│   conditions, meds,          KNOWN true HR; neg/pos        utable metadata   │
│   procedures, obs, costs)    control outcomes)             only)             │
└───────────────┬──────────────────────┬──────────────────────────┬────────────┘
                │                      │                          │
                ▼                      ▼                          ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│ LAYER 1 — INGESTION            [R: readr/arrow, DBI, targets]                │
│  • checksum every source file → source_manifest                              │
│  • assign snapshot_id (immutable, = hash of manifest + generation seed)       │
│  • bulk COPY into raw.* — NO transformation, NO cleaning                     │
│  • raw is append-only and never edited (this is your audit floor)            │
└───────────────┬──────────────────────────────────────────────────────────────┘
                ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│ LAYER 2 — OMOP CDM 5.4        [SQL migrations + ETL-Synthea pattern]         │
│                                                                              │
│   person · observation_period · visit_occurrence · condition_occurrence      │
│   drug_exposure · procedure_occurrence · measurement · observation           │
│   death · cost · payer_plan_period · concept · concept_ancestor              │
│                                                                              │
│   ▸ source codes (SNOMED/RxNorm/LOINC/ICD) mapped to standard concept_id     │
│   ▸ every row carries snapshot_id                                            │
└───────────────┬──────────────────────────────────────────────────────────────┘
                ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│ LAYER 3 — DATA QUALITY & FITNESS-FOR-USE   [Achilles, DataQualityDashboard]  │
│  • structural checks: PK/FK, date ordering, plausible ranges, no future dates│
│  • temporal stability, completeness of protocol-required variables           │
│  • M14 feasibility gate: can exposure/outcome/covariates be operationalized? │
│  • FAIL ⇒ pipeline halts. quality_issue + pipeline_run written either way.   │
└───────────────┬──────────────────────────────────────────────────────────────┘
                ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│ LAYER 4 — COHORT ENGINE       [CodelistGenerator, CohortConstructor,          │
│                                CohortGenerator/CirceR]                       │
│  cohort_definition (versioned, hash of the JSON/SQL, links to protocol.md)   │
│         │                                                                    │
│         ├─▸ concept sets built + reviewed (CodelistGenerator)                │
│         ├─▸ target cohort  (new users of A)                                  │
│         ├─▸ comparator     (new users of B)   ← active comparator            │
│         ├─▸ outcome cohorts (primary + 20–50 NEGATIVE CONTROLS)              │
│         └─▸ index date · washout · eligibility · time-at-risk · censoring    │
│  OUT: cohort_member(person_id, cohort_id, cohort_version, index_date,        │
│                     tar_start, tar_end, censor_reason) + attrition funnel    │
└──────┬─────────────────────────────────────────────────┬─────────────────────┘
       │                                                 │
       ▼ (estimation path)                               ▼ (prediction path)
┌────────────────────────────────┐        ┌──────────────────────────────────────┐
│ LAYER 5A — RWE ENGINE          │        │ LAYER 5B — FEATURE + ML ENGINE       │
│ [PatientProfiles,              │        │ [FeatureExtraction / dbplyr,         │
│  CohortCharacteristics,        │        │  tidymodels, glmnet, xgboost,        │
│  survival, CohortSurvival,     │        │  probably, yardstick, DALEX]         │
│  CohortMethod, Cyclops,        │        │                                      │
│  EmpiricalCalibration]         │        │ • feature_spec_v1.yml declares, per  │
│                                │        │   feature: lookback window + the     │
│ 1 baseline covariates          │        │   assertion "available at t0"        │
│ 2 Table 1 + SMD (pre)          │        │ • features built ONLY from data with │
│ 3 propensity model             │        │   date < index_datetime              │
│ 4 match / IPTW / stratify      │        │ • split: patient-level, then         │
│ 5 overlap + positivity + SMD   │        │   TEMPORAL holdout (train on early   │
│   (post) + equipoise plot      │        │   window, test on later window)      │
│ 6 outcome model: Cox / cond.   │        │ • baselines: prevalence, LACE-style, │
│   logistic / Poisson           │        │   penalized logistic                 │
│ 7 KM + log-rank + PH check     │        │ • challenger: xgboost / ranger       │
│ 8 utilization + cost models    │        │ • calibration: isotonic/Platt +      │
│ 9 NEGATIVE CONTROLS → empirical│        │   calibration curve + Brier          │
│   calibration of p and CI      │        │ • threshold set by OPERATIONAL       │
│10 sensitivity: alt washout,    │        │   capacity, not 0.5                  │
│   alt TAR, alt PS spec,        │        │ • subgroup metrics by age/sex/etc.   │
│   E-value for unmeasured conf. │        │ • explainability: global VIP + SHAP  │
└──────────────┬─────────────────┘        └───────────────┬──────────────────────┘
               │                                          │
               ▼                                          ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│ LAYER 6 — ARTIFACT + REGISTRY LAYER                                          │
│                                                                              │
│  results.analysis_result   ── every estimate, tagged:                        │
│      (study_id, cohort_version, snapshot_id, commit_sha, renv_hash,          │
│       estimate, ci_lo, ci_hi, p, calibrated_p, calibrated_ci, analysis_type) │
│                                                                              │
│  model_registry  ── vetiver_model() pinned via {pins} to board_folder/board_s3│
│      (model_name, version_ts, training window, feature_spec_hash,            │
│       cohort_version, snapshot_id, commit_sha, metrics, threshold,           │
│       input prototype, status: challenger|champion|revoked)                  │
│                                                                              │
│  RULE: nothing is served that is not registered. Rollback = repin prior      │
│        version. No artifact exists without its full lineage tuple.           │
└───────────────┬──────────────────────────────────────────────────────────────┘
                ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│ LAYER 7 — PRODUCT SURFACES                                                   │
│                                                                              │
│  Quarto reports          Shiny (bslib)              plumber API              │
│  ├ rwe_study_report      ├ Executive                ├ /health /version       │
│  │  (M14 section order)  ├ Cohort + attrition       ├ /v1/cohorts            │
│  ├ model_validation      ├ Balance / SMD / overlap  ├ /v1/evidence/{study}   │
│  │  (TRIPOD+AI shaped)   ├ Outcomes + KM + calib.   ├ /v1/predict/readmission│
│  ├ model_card            ├ Cost / utilization       ├ /v1/models/{id}/card   │
│  └ dq_report             ├ Risk model + threshold   ├ /v1/quality/latest     │
│                          ├ Explainability/subgroup  └ /metrics (Prometheus)  │
│  parameterized by        ├ Data quality / ops                                │
│  study_id + model_version└ Governance / lineage     read-only DB role        │
└───────────────┬──────────────────────────────────────────────────────────────┘
                ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│ LAYER 8 — OPERATIONS                                                         │
│  targets orchestration · renv lock · Docker · GitHub Actions CI              │
│  monitoring: data freshness · schema drift · missingness · score drift (PSI) │
│              calibration drift · API latency/error rate · run status         │
│  logging: structured JSON, request-id, NEVER patient payloads                │
│  alerting: threshold breach → CI failure / CloudWatch alarm                  │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Data flow, component by component

**Source → Ingestion.** Synthea writes CSVs. The loader hashes each file, writes a `source_manifest` row, computes `snapshot_id`, and bulk-loads into `raw.*`. Nothing is cleaned here. The reason: when a result is questioned six months later, you need to be able to point at the exact bytes that produced it. `raw` is your audit floor.

**Ingestion → OMOP.** SQL transformations map Synthea's native codes to standard concepts and populate CDM 5.4 tables. Two non-obvious pieces: `observation_period` (when was this person actually observable — without it every incidence rate is wrong) and `cost`.

**OMOP → DQ gate.** Achilles computes descriptive statistics; DataQualityDashboard runs a large battery of standardized checks. On top of those, your **protocol-specific** fitness-for-use checks: is the exposure recorded at sufficient volume, is the outcome ascertainable, are the covariates present. This is the M14 feasibility step and it is the gate — a red check stops the pipeline rather than producing a quietly wrong number.

**DQ → Cohort engine.** Concept sets are generated and reviewed first (a "diabetes" concept set is a research decision, not a lookup). Then target, comparator and outcome cohorts, plus 20–50 negative control outcomes. The cohort definition is content-hashed; the hash appears on every downstream result.

**Cohort → 5A (estimation).** New-user active-comparator design controls for prevalent-user bias and depletion of susceptibles. Index = first exposure. Washout = 365 days with no prior exposure to either drug and required prior observation. Time-at-risk = index+1 to index+365, censored at death, disenrollment, or switching. Baseline covariates measured strictly in `[index-365, index-1]`.

**Cohort → 5B (prediction).** Different cohort entirely: index is *discharge datetime* from a qualifying admission. Features come only from data timestamped before that moment. Split is patient-level first (so no patient appears in both train and test), then temporal (train on the earlier period, evaluate on the later), because temporal generalization is what actually breaks in deployment.

**Both → Artifacts.** Every number written to `analysis_result` or `model_registry` carries the full lineage tuple. If you cannot answer "which snapshot, which cohort version, which commit produced this?" the number does not get written.

**Artifacts → Product.** Shiny and the API read *only* curated result tables and registered models. Neither has read access to `cdm.person`. Reports are parameterized Quarto renders.

**Everything → Ops.** `targets` gives dependency-aware re-execution: change the cohort SQL and only the downstream nodes rebuild. This is what makes iteration survivable.

---

## 5. Production Tech Stack

| Layer | Choice | Why this and not the alternative |
|---|---|---|
| Language | R 4.4+ | The target roles are R roles. Python appears only for Synthea/ETL glue. |
| Source data | Synthea + seeded ground-truth overlay | No PHI, redistributable, reproducible from a seed |
| Dev DB | DuckDB (file) | Zero-infra, fast CI, same `CDMConnector` code path |
| Prod DB | PostgreSQL 16 | Real concurrency, roles, migrations, RDS-deployable |
| CDM | OMOP CDM 5.4 | The lingua franca of RWE; unlocks the whole tool ecosystem |
| DB access | DBI, RPostgres, duckdb, dbplyr | Push filtering/aggregation to SQL; never `SELECT *` into RAM |
| CDM interface | CDMConnector, omopgenerics | Pipe-friendly cdm reference; backend-agnostic |
| Concept sets | CodelistGenerator | Code lists are research artifacts, not magic numbers |
| Cohorts | CohortConstructor and/or CohortGenerator + CirceR | Standard, testable, portable cohort logic |
| Characterization | PatientProfiles, CohortCharacteristics | Table 1 and SMDs the way the field expects them |
| Rates | IncidencePrevalence | Correct denominators and person-time, free |
| Drug use | DrugUtilisation | Adherence/persistence/switching — direct HEOR relevance |
| Survival | survival, survminer, CohortSurvival | KM, log-rank, Cox, PH diagnostics |
| Causal | CohortMethod, Cyclops, WeightIt/MatchIt | Large-scale PS, matching, IPTW, balance diagnostics |
| Calibration of estimates | EmpiricalCalibration | Negative-control calibrated p-values and CIs — the differentiator |
| Prediction | tidymodels, glmnet, xgboost, ranger, probably, yardstick | Idiomatic modern R modeling with recipe-based leakage control |
| Explainability | vip, DALEX, fastshap | Global + local, honest about SHAP's limits |
| Model registry | **vetiver + pins** | The idiomatic R answer: versioning, input prototype validation, plumber generation, S3/Connect boards. (MLflow's R support is weaker — verify current status before choosing it.) |
| Orchestration | targets | Dependency graph, skip-unchanged, reproducible re-runs |
| Environment | renv | Lockfile is part of every artifact's lineage |
| Reporting | Quarto | Parameterized, multi-format, citations, session capture |
| Tables | gtsummary, gt, rtables | Publication-grade Table 1 |
| Dashboard | Shiny + bslib + shiny modules | Modular = testable |
| API | plumber (+ vetiver_api) | Auto input validation, OpenAPI docs |
| API tests | httr2, testthat | Contract + integration |
| Testing | testthat 3e, pointblank, dbplyr fixtures | Unit, data-contract, and leakage tests |
| Container | Docker (rocker/r-ver pinned) + Compose | Reproducible runtime |
| CI/CD | GitHub Actions | Test + render + build + scan on every push |
| Cloud | AWS ECS Fargate + RDS + S3 + CloudWatch **(document; deploy a cheaper equivalent)** | See §11.3 on cost |
| Secrets | env vars locally, Secrets Manager in cloud, gitleaks in CI | Never in the repo |

---

## 6. New / High-Value Technologies

These are the pieces you have not used before. For each: what it does, why teams use it, why it's worth your time, where it sits.

### OMOP CDM 5.4
**What:** a standardized relational schema plus standardized vocabularies for observational health data. **Why teams use it:** it lets the same analysis code run against Optum, Truven, CPRD, or a hospital warehouse without rewriting, and it enables federated network studies where data never leaves the site. **Why learn it:** it is the single most transferable credential in RWE. Every OHDSI-shop job description assumes it. **Where:** Layer 2.

### CDMConnector / omopgenerics (DARWIN EU)
**What:** a pipe-friendly, backend-agnostic interface to an OMOP CDM — `cdm` object, dbplyr under the hood, DuckDB or Postgres. **Why teams use it:** it makes OMOP analytics feel like tidyverse instead of like 800-line SQL. It is the modern layer over OHDSI's older Java-flavored tooling. **Why learn it:** actively developed through 2026, increasingly the default in European RWE, and rising in US shops. **Where:** Layers 4–5, everything.

### OHDSI HADES (CohortMethod, PatientLevelPrediction, FeatureExtraction, Achilles, DataQualityDashboard, EmpiricalCalibration)
**What:** the reference implementation of population-level estimation, patient-level prediction, characterization and data quality on OMOP. **Why teams use it:** methods are peer-reviewed and pre-validated, so you argue about the *study*, not the code. **Why learn it:** naming `CohortMethod` and `EmpiricalCalibration` in an interview is a competence signal that cannot be faked. **Where:** Layers 3, 4, 5A, 5B.

### Empirical calibration with negative controls
**What:** run your study against dozens of outcomes the exposure cannot cause, observe the distribution of estimates you get (which should be centered on null but usually isn't, because of residual confounding), and use that empirical null to calibrate the p-value and CI of your real estimate. **Why teams use it:** it is currently the most credible answer to "how do I know residual confounding isn't driving this?" **Why learn it:** almost nobody at your career stage knows this exists. It is a five-minute answer that reframes how an interviewer sees you. **Where:** Layer 5A, step 9.

### targets
**What:** a make-like pipeline for R with a dependency graph and content-based invalidation. **Why teams use it:** analytical pipelines are re-run constantly with small changes; targets rebuilds only what's affected, and guarantees the artifact matches the code. **Why learn it:** it is the reproducibility answer for R, and it makes your "clean-clone reproduction" claim actually true. **Where:** Layer 8, orchestrating 1–6.

### vetiver + pins
**What:** model versioning, input-prototype validation, plumber API generation, and monitoring hooks for R models. **Why teams use it:** it closes the training→serving gap without leaving R, versions across local/S3/Connect boards, and catches schema mismatches at the endpoint. **Why learn it:** "MLOps in R" is a rare skill and it is exactly what a Medical Data Scientist job wants that a biostatistician can't offer. **Where:** Layers 6–7.

### probably (calibration) + PROBAST/TRIPOD+AI thinking
**What:** calibration curves, isotonic/Platt recalibration, threshold analysis; plus the reporting frameworks for clinical prediction models. **Why teams use it:** in clinical deployment, a miscalibrated model with great AUC is dangerous — a 0.9 score must mean 90%. Regulators and journals expect calibration to be reported. **Why learn it:** "AUC 0.78" is a student answer. "AUC 0.78, calibration slope 0.94, intercept -0.03, and here's the decision curve at our operating threshold" is a hire. **Where:** Layer 5B.

### pointblank / data contracts
**What:** declarative data validation with pass/fail reporting on tables. **Why teams use it:** silent data drift is the top cause of wrong healthcare numbers. **Why learn it:** it turns "I checked the data" into an artifact. **Where:** Layer 3.

### DuckDB
**What:** an in-process analytical database — SQLite for OLAP. **Why teams use it:** local analytics at Postgres speed with no server. **Why learn it:** it has become a default tool in data engineering, and here it makes your CI fast. **Where:** Layers 1–5, dev/CI.

---

## 7. Data Architecture

### 7.1 Schemas

```
raw.*             immutable landing, append-only, snapshot_id on every row
cdm.*             OMOP CDM 5.4 (person, observation_period, visit_occurrence,
                  condition_occurrence, drug_exposure, procedure_occurrence,
                  measurement, observation, death, cost, concept, concept_ancestor)
study.*           cohort_definition, cohort_member, concept_set, attrition
features.*        feature_spec, feature_readmission_v1 (materialized, timestamped)
results.*         analysis_result, balance_diagnostic, survival_curve,
                  negative_control_result, model_metric, subgroup_metric
registry.*        model_registry, model_artifact_ref, promotion_event
ops.*             pipeline_run, quality_issue, source_manifest, audit_event,
                  monitoring_metric
```

### 7.2 The tables that matter most

**`study.cohort_definition`** — `cohort_id, cohort_version, name, definition_json, definition_hash, protocol_ref, created_at, created_by, superseded_by`. The hash is what makes the study auditable: a result carrying `definition_hash = a3f9…` can be tied to exactly one definition forever.

**`study.cohort_member`** — `person_id, cohort_id, cohort_version, index_date, tar_start, tar_end, censor_date, censor_reason, snapshot_id`. Grain: one row per person per cohort per version. Note `censor_reason` — being able to say *why* follow-up ended (death, disenrollment, switch, administrative end) is the difference between a survival analysis and a plot.

**`features.feature_spec`** — `feature_name, source_table, lookback_days, aggregation, available_at_t0 (boolean, asserted), owner, version`. This is the single most important anti-leakage artifact in the system, because it makes the timing assumption **declarative and therefore testable**. A test iterates every feature and asserts no contributing source row has a date ≥ index.

**`results.analysis_result`** — `result_id, study_id, analysis_type, cohort_version, snapshot_id, commit_sha, renv_hash, estimate, se, ci_lo, ci_hi, p_value, calibrated_ci_lo, calibrated_ci_hi, calibrated_p, n_target, n_comparator, n_events, run_id`. Two CI columns is the point: raw and negative-control-calibrated, side by side.

**`registry.model_registry`** — `model_id, model_name, version_ts, pin_hash, feature_spec_hash, cohort_version, snapshot_id, commit_sha, renv_hash, train_window, test_window, auroc, auprc, brier, calib_slope, calib_intercept, threshold, threshold_rationale, status, promoted_by, promoted_at, revoked_reason`.

### 7.3 Data contracts (enforced in CI)

- Every `person_id` in `cohort_member` exists in `cdm.person`
- No `index_date` outside that person's `observation_period`
- No `condition_start_date` after `death_datetime`
- No feature source row with date ≥ its cohort member's `index_datetime`
- Attrition funnel arithmetic reconciles: each step's exclusions sum to the drop
- `snapshot_id` is constant within a run and present on every result row
- Zero duplicate `(person_id, cohort_id, cohort_version)` pairs

### 7.4 Snapshots and time

`snapshot_id` is deterministic: hash of the source manifest plus the generation seed. Same seed ⇒ same snapshot ⇒ same results, byte-for-byte, forever. This is what lets your README say "clone, run three commands, get the numbers in the report" and be telling the truth.

---

## 8. Analytics Architecture

### 8.1 The estimation pipeline (5A)

```
protocol.md + sap.md  (written and git-tagged FIRST)
      ↓
concept sets → target / comparator / outcome / negative controls
      ↓
new-user active-comparator cohort · 365d washout · required prior observation
      ↓
baseline covariates strictly in [index-365, index-1]
      ↓
Table 1 + standardized mean differences (unadjusted)
      ↓
propensity model  →  overlap / positivity / preference-score distribution
      ↓
1:1 matching (primary)  ‖  IPTW with trimming (sensitivity)
      ↓
post-adjustment SMD (target: all |SMD| < 0.1) — if it fails, the design fails
      ↓
outcome models:
   • Cox PH on time-to-first-event  → HR + CI, PH assumption (Schoenfeld)
   • Kaplan-Meier + log-rank
   • absolute risk difference + NNT (report absolute, always)
   • counts: negative binomial for admissions/ED
   • cost: GLM gamma-log or two-part model, never OLS on raw cost
      ↓
NEGATIVE CONTROLS → empirical null → calibrated p and CI
      ↓
sensitivity: alt washout (180/730), alt TAR, alt PS spec, unadjusted,
             E-value for unmeasured confounding
      ↓
M14-structured study report
```

**Design decisions to document as ADRs**, because these are the interview questions: why active comparator over non-user; why new-user over prevalent-user; why 365-day washout; why matching over weighting as primary; why time-to-first-event over recurrent events; how you handle competing risk of death.

### 8.2 The prediction pipeline (5B)

```
prediction cohort: index = discharge_datetime of qualifying index admission
      ↓
label: unplanned readmission within (t0, t0+30d]; competing risk of death
       handled explicitly and documented
      ↓
features from feature_spec_v1.yml, ALL with available_at_t0 = TRUE
      ↓
split: (1) patient-level grouping  (2) temporal holdout by index_date
      ↓
preprocessing INSIDE the recipe, fit on training folds only
      ↓
baselines: prevalence · simple clinical score · penalized logistic
      ↓
challenger: xgboost, tuned on training folds only
      ↓
discrimination: AUROC, AUPRC (report AUPRC — the outcome is imbalanced)
calibration: curve, slope, intercept, Brier
clinical utility: decision curve / net benefit at the operating threshold
      ↓
threshold ← operational capacity ("we can call 60/week"), NOT 0.5.
            Report PPV, NPV, sensitivity, specificity, and expected
            weekly workload at that threshold.
      ↓
subgroups: age band, sex, prior-utilization tertile, index-condition group.
           Report AUROC and CALIBRATION per subgroup. A model that
           discriminates equally but is miscalibrated in one subgroup will
           systematically over- or under-treat that group.
      ↓
explainability: global VIP + local SHAP on synthetic exemplar patients,
                with an explicit note that SHAP is not a causal claim
      ↓
model card + vetiver pin + registry row
```

### 8.3 The wall between them

Physically separate directories, separate report templates, separate API namespaces, separate result tables. In the Shiny UI, effect estimates render with a "association / adjusted estimate" chip and prediction outputs with a "risk score — not a treatment recommendation" chip. The API's prediction response includes a `not_for_clinical_use` field.

This sounds like decoration. It is not — conflating the two is *the* recurring failure in healthcare analytics, and demonstrating that you have designed against it is a senior signal.

---

## 9. Application Features

### 9.1 Shiny tabs (MVP tabs marked ★)

★ **Executive** — study question in one sentence; cohort sizes; crude and adjusted effect with calibrated CI; readmission model AUROC/calibration; data freshness; a prominent synthetic-data banner.

★ **Cohort** — the protocol rendered inline; version and hash; attrition funnel (Sankey or waterfall) with counts at each exclusion; index date definition; TAR diagram.

★ **Balance** — Table 1 (gtsummary) before/after; SMD love plot with the 0.1 reference line; propensity/preference score overlap histogram.

★ **Outcomes** — KM curves with risk table; Cox HR forest; absolute risk difference; sensitivity analysis forest; **negative control calibration plot** (this one is the showpiece).

**Cost & Utilization** — admissions and ED per person-year, cost distribution (log scale, honest about skew), adjusted differences.

★ **Risk Model** — ROC and PR curves, calibration curve with the diagonal, threshold slider that live-updates PPV/NPV/sensitivity/specificity/confusion matrix *and expected weekly workload*, decision curve.

**Explainability & Subgroups** — global importance; a synthetic patient explorer with local SHAP; subgroup table of AUROC + calibration slope with confidence intervals.

**Data Quality & Ops** — DQ check pass/fail grid, missingness by variable, last successful run, snapshot ID, row counts.

★ **Governance** — study version, cohort hash, model version, snapshot ID, commit SHA, renv hash, intended use, limitations, and a link to the model card. One screen that proves the whole thing is traceable.

### 9.2 Non-negotiable UI rules

- Filters never redefine the study population — they subset display of pre-computed results, and the UI says so
- No patient-level real data anywhere; the patient explorer uses labelled synthetic exemplars
- Every estimate shows its CI; no bare point estimates
- Every screen carries the synthetic-data disclaimer

---

## 10. API Design

Base: `/v1`. Versioned in path. OpenAPI served at `/__docs__/`.

| Method | Route | Purpose | Auth |
|---|---|---|---|
| GET | `/health` | liveness | none |
| GET | `/version` | app version, commit SHA, model version, snapshot ID | none |
| GET | `/v1/cohorts` | list cohort definitions with versions and hashes | key |
| GET | `/v1/cohorts/{id}/attrition` | attrition funnel counts | key |
| GET | `/v1/cohorts/{id}/summary` | baseline characteristics, SMDs | key |
| GET | `/v1/evidence/{study_id}` | effect estimates, raw + calibrated CI, diagnostics | key |
| GET | `/v1/evidence/{study_id}/negative-controls` | the empirical null distribution | key |
| POST | `/v1/predict/readmission` | score synthetic patient features | key |
| POST | `/v1/predict/readmission/batch` | score a batch (bounded size) | key |
| GET | `/v1/models` / `/v1/models/{id}/card` | registry listing / model card | key |
| GET | `/v1/quality/latest` | DQ + pipeline status | key |
| GET | `/metrics` | Prometheus-format ops metrics | internal |

**Prediction response shape:**

```json
{
  "risk_score": 0.187,
  "risk_band": "high",
  "threshold": 0.142,
  "threshold_rationale": "capacity-based: top 12% by predicted risk",
  "model_version": "readmission_30d@20260901T140322Z-4f2a1",
  "feature_spec_hash": "b7c1e9…",
  "prediction_id": "9f3c…",
  "generated_at": "2026-09-01T14:11:02Z",
  "not_for_clinical_use": true,
  "disclaimer": "Trained on synthetic data. Not validated for clinical decision-making."
}
```

**API rules:**
- Reject unknown fields (400) — do not silently ignore them; a typo'd feature name that gets ignored produces a wrong score with no error
- Validate against the vetiver input prototype; return which field failed
- Reject physiologically impossible values (age 300, negative length of stay)
- Rate limit; bound batch size
- Log `prediction_id`, model version, latency, and status — **never the feature payload**
- No endpoint returns raw CDM rows

---

## 11. Scalability

### 11.1 Where it actually breaks

| Bottleneck | At what scale | Mitigation |
|---|---|---|
| Loading patient rows into R | ~10M rows | Push filter/aggregate to SQL via dbplyr; only pull the analysis-ready frame |
| Covariate construction | wide covariate sets × large cohorts | FeatureExtraction's sparse representation; batch by person chunks |
| Propensity model | 10k+ covariates | Cyclops large-scale regularized regression (built for exactly this) |
| Cohort generation | large CDM | Index `(person_id, date)` on every clinical table; temp tables in the write schema |
| Shiny under concurrency | >20 users | App reads only small pre-computed result tables; never computes on request |
| API latency | burst load | Model loaded once at startup, not per request; horizontal scale behind ALB |

### 11.2 Scaling patterns worth implementing even at portfolio scale

- **Pre-computation over on-demand.** Everything the dashboard shows is a `targets` output, not a live query. This is how real clinical dashboards stay fast and is a design decision you can defend.
- **Incremental snapshots.** New snapshot → only downstream targets rebuild.
- **Backend portability.** Because you use `CDMConnector`, moving DuckDB → Postgres → (in principle) Redshift/Databricks is a connection change.

### 11.3 A frank note on cloud cost

ECS Fargate + RDS + ALB running continuously is real money for a portfolio. Recommended: **document** the AWS architecture fully (diagram, task definitions, IAM, terraform or at minimum documented CLI), and **deploy** something cheap that stays up — a container on a small VPS, or Shiny on a free tier with a free managed Postgres. A permanently-live demo URL beats an AWS bill. Note in the README that the AWS path is designed and scripted but not left running, and why. Verify current free-tier limits before committing.

---

## 12. Security & Governance

### 12.1 Privacy posture

The repo is synthetic-only. But the *architecture* must be one that would work with PHI, and `docs/privacy_security.md` must state exactly what changes if it were real:

| Control | Portfolio (synthetic) | If PHI |
|---|---|---|
| De-identification | n/a — no identifiers exist | Safe Harbor (18 identifiers removed) or Expert Determination; document which and why |
| Encryption | TLS in transit | + at rest (RDS/S3 KMS), key rotation |
| Access | API key, read-only app role | SSO + MFA, RBAC, minimum-necessary, BAA with every vendor |
| Audit | `ops.audit_event` | Immutable, tamper-evident, retained per policy, reviewed |
| Cell suppression | not required | Suppress aggregate cells with n < 11 |
| Data residency | n/a | Documented; no cross-border without agreement |
| Logging | no payloads | Same rule, enforced and audited |

Do **not** claim HIPAA compliance or certification. Say: "designed with HIPAA de-identification concepts; implemented on synthetic data; a PHI deployment would additionally require X, Y, Z." That distinction is itself the signal — overclaiming compliance is a red flag to anyone in the field.

### 12.2 Database role matrix

| Role | raw | cdm | study | features | results | registry | ops |
|---|---|---|---|---|---|---|---|
| `careevidence_etl` | RW | RW | RW | RW | RW | RW | RW |
| `careevidence_analyst` | – | R | R | R | RW | R | R |
| `careevidence_app` | – | – | R | – | R | R | R |
| `careevidence_api` | – | – | R | – | R | R | – |
| `careevidence_admin` | owner | owner | owner | owner | owner | owner | owner |

Grants live in a migration file. A test asserts the app role cannot write to `study.cohort_definition`.

### 12.3 Analytical governance

- Protocol and SAP git-tagged before first analysis; deviations recorded in `docs/protocol_deviations.md`
- Cohort changes bump `cohort_version`; old versions are never edited, only superseded
- Model promotion requires: CI green, AUROC ≥ baseline + margin, calibration slope within [0.8, 1.2], no subgroup calibration failure, model card updated. Recorded in `promotion_event`.
- Rollback = repin the prior version. Never patch a released artifact.
- Model card sections: intended use, **excluded uses**, training data and period, cohort definition, features and their timing, performance overall and by subgroup, calibration, threshold and rationale, known limitations, monitoring plan, contact, review date.

### 12.4 Application security

Parameterized SQL only; secrets from env/Secrets Manager with gitleaks in CI; pinned base images with Trivy scanning; dependency audit; no stack traces to clients; strict CORS; structured logs without payloads.

---

## 13. Production SDLC

| Phase | Deliverables | Exit criteria | Est. |
|---|---|---|---|
| **1. Define** | Research question, estimand, `protocol.md`, `sap.md`, intended use, prediction target definition, success criteria | Protocol git-tagged `protocol-v1` before any estimate exists | 1 wk |
| **2. Design** | CDM schema + migrations, cohort logic in prose, `feature_spec_v1.yml`, API contract, DB role matrix, threat model, test plan, ADRs 001–010 | Schema reviewed; every design decision has an ADR | 1 wk |
| **3. Data layer** | Synthea generation + ground-truth overlay, raw loader, OMOP ETL, Achilles + DQD, fitness-for-use gate | Clean clone → seeded DB → all DQ checks pass | 2 wk |
| **4. Cohort + RWE** | Concept sets, cohorts, attrition, Table 1, SMDs, PS, matching, Cox/KM, cost/utilization, negative controls, calibration, sensitivity | Pipeline recovers the known true HR within CI; negative controls centered on null | 3 wk |
| **5. ML** | Feature build, splits, baselines, challenger, calibration, threshold, subgroups, SHAP, vetiver pin | Beats baseline; calibration slope in range; every leakage test green | 2 wk |
| **6. Productize** | Quarto ×4, Shiny modules, plumber API, OpenAPI | Reports render from a clean clone; API contract tests pass | 2 wk |
| **7. Verify** | Full test suite, integration test, clean-clone reproduction, load smoke test | Fresh clone reproduces every reported number | 1 wk |
| **8. Deploy** | Dockerfiles, Compose, CI workflow, migrations, live demo, AWS design doc | Demo URL live; CI green on main; `v1.0` tagged | 1 wk |
| **9. Monitor** | Freshness, drift (PSI), calibration drift, API metrics, alert thresholds, runbook | Drift job runs; a synthetic drift injection triggers the alert | 1 wk |
| **10. Improve** | Champion/challenger comparison, one documented iteration with a retrospective | An ADR showing you changed your mind based on evidence | ongoing |

**~15 weeks at a serious part-time pace.** Section 14 tells you what to cut.

---

## 14. Scaling Roadmap

### MVP — `v0.1` — target 4–5 weeks. Build exactly this.
- Synthea → Postgres/DuckDB, OMOP CDM subset (person, observation_period, visit_occurrence, condition_occurrence, drug_exposure, measurement, death, cost)
- Basic DQ checks + fitness-for-use gate
- **One** study: new-user active-comparator, one primary outcome, PS matching, Table 1 + SMD, KM + Cox
- **One** model: penalized logistic 30-day readmission, patient + temporal split, calibration curve, threshold with rationale
- Quarto study report + model validation report
- Shiny with 4 tabs: Executive, Cohort, Outcomes, Risk Model
- `/health`, `/version`, `/v1/predict/readmission`
- testthat: cohort fixtures, leakage tests, API contract
- Docker Compose + GitHub Actions
- README + protocol + model card

**Cut from MVP:** negative controls, cost modeling, SHAP, subgroups, monitoring, AWS, xgboost, incidence/prevalence, drug utilisation.

### V1 — portfolio-complete — +5 weeks. This is the version you show recruiters.
- Ground-truth overlay + **negative controls + empirical calibration** ← highest value single addition
- xgboost challenger + champion/challenger comparison
- Subgroup performance and calibration
- SHAP + synthetic patient explorer
- Cost and utilization analysis with appropriate models
- Sensitivity analyses + E-value
- vetiver registry + promotion gate
- Full Shiny (9 tabs) + full API
- Drift monitoring + alerting
- Live deployed demo + 3-minute recorded walkthrough

### V2 — advanced — optional, only if the field is where you land.
- IncidencePrevalence and DrugUtilisation analyses (UC-3, UC-4)
- `PatientLevelPrediction` implementation alongside tidymodels, with a comparison writeup
- Competing-risk survival (Fine-Gray) for death as a competing event
- Self-controlled case series as a design sensitivity analysis
- Study package structure (`R CMD check`-clean, installable, like an OHDSI study repo)
- Federated/network design writeup: how this runs at 5 sites without moving data

### Enterprise — describe, never build.
Real EHR/claims feeds with delta loads; Atlas/WebAPI; vocabulary refresh; multi-tenant RBAC and SSO; airflow/dagster orchestration; feature store; A/B evaluation of the risk model against usual care; EHR integration via FHIR/SMART; clinical governance committee; IRB; model revalidation cadence; incident response. A one-page "what would change at enterprise scale" section is worth more than a half-built version of any of it.

---

## 15. Final System Walkthrough

Follow one patient, one estimate and one prediction end to end.

1. `make generate` runs Synthea with seed `42` and the ground-truth overlay. Patient `P-8817`, female, 71, type 2 diabetes, prior CHF admission, initiates drug A on 2019-04-12. The overlay assigned her exposure with probability increasing in prior utilization — this is the confounding you injected — and generated her outcome under true HR 0.75.
2. The loader hashes the CSVs, writes `source_manifest`, computes `snapshot_id = 7a3f…`, and COPYs into `raw.*`. Nothing cleaned.
3. ETL maps her SNOMED and RxNorm codes to standard concepts, populates `cdm.person`, `cdm.observation_period` (2016-01-01 → 2022-12-31), `cdm.condition_occurrence`, `cdm.drug_exposure`.
4. Achilles + DQD run. 412 checks, 0 failures. Fitness-for-use gate: exposure n=4,102, outcome ascertainable, covariates ≥95% complete. **Pass** — pipeline proceeds.
5. Cohort engine evaluates `cohort_v1.3` (hash `a3f9…`). P-8817 has 365 days of prior observation and no prior exposure to A or B → qualifies. `index_date = 2019-04-12`, `tar = [2019-04-13, 2020-04-11]`. She appears in the attrition funnel's final row.
6. Covariates measured in `[2018-04-12, 2019-04-11]`: age band, sex, Charlson, prior admissions (3), prior ED (1), 14 comorbidity flags, 9 drug classes, 6 lab groups.
7. Table 1 shows imbalance — prior admissions SMD 0.31, drug A users are sicker. Propensity model fits; preference-score plot shows good overlap; 1:1 matching yields 3,844 pairs; post-match all |SMD| < 0.08. P-8817 matched to P-2290.
8. Cox on matched pairs: **crude HR 1.09 (0.97–1.23)** — the confounding, visible. **Adjusted HR 0.76 (0.66–0.88)** — recovers the injected truth of 0.75. Absolute risk difference −3.1 per 100 person-years. Schoenfeld test p=0.42, PH holds.
9. 47 negative control outcomes run through the identical pipeline. Their estimates center at HR 1.02 with modest spread → residual systematic error is small. Empirical calibration widens the CI slightly to **0.65–0.90**. Both raw and calibrated CIs go into `analysis_result` and into the report.
10. Sensitivity: 180-day washout → 0.78; IPTW instead of matching → 0.74; 730-day TAR → 0.79. E-value 2.1. The conclusion is stable, and you can say so with evidence.
11. Separately, the prediction cohort forms. P-8817 is discharged 2019-06-03 at 14:20 after a 4-day admission. Features are built strictly from data before that timestamp; the leakage test walks every feature and confirms no contributing row has a date ≥ index.
12. Split: patients before 2020-01-01 train, after test. P-8817 lands in train. Penalized logistic baseline AUROC 0.681; xgboost 0.724, AUPRC 0.211 against a 12.4% event rate. Calibration slope 0.97, intercept −0.02, Brier 0.096.
13. Threshold set at 0.142 — the top 12% of scores — because the stated care-management capacity is 60 calls/week. At that threshold: sensitivity 0.41, PPV 0.29, NPV 0.93. Decision curve shows net benefit over treat-all and treat-none across the plausible range.
14. Subgroups: AUROC holds across age bands, but calibration slope in the 85+ group is 0.71 — **under-predicting risk in the oldest patients**. This is documented as a limitation in the model card and flagged for the next iteration. Finding and reporting this is worth more than hiding it.
15. `vetiver_pin_write()` stores the model as `readmission_30d@20260901T140322Z-4f2a1`, with input prototype. A `model_registry` row records the full lineage tuple. Promotion gate passes; status → champion.
16. Quarto renders the M14-structured study report, the validation report, the model card, and the executive summary — all parameterized by `study_id` and `model_version`.
17. Shiny starts with the read-only role and reads only `results.*` and `registry.*`. The plumber API loads the pinned champion once at startup.
18. `POST /v1/predict/readmission` with a synthetic feature payload returns `risk_score: 0.187`, `risk_band: "high"`, the model version, and `not_for_clinical_use: true`. The request is logged with a `prediction_id` and latency; the payload is not.
19. The monitoring job compares this week's score distribution to the training distribution (PSI 0.04, fine), checks missingness, and re-computes calibration on the newest labelled window.
20. CI on every push: DQ checks, cohort fixture tests, leakage tests, statistical regression tests against stored expected values, API contract tests, Docker build, secret scan, report render smoke test.

---

## 16. Recruiter Perspective — what this proves, by role

| Role | What they screen for | Where this project proves it |
|---|---|---|
| **Healthcare Data Analyst** | SQL at scale, healthcare data literacy, dashboards, clear communication | dbplyr/SQL pushdown, OMOP CDM, encounters/claims/cost modeling, Shiny, executive summary |
| **RWE Analyst** | Cohort protocol discipline, confounding control, study reporting, regulatory awareness | M14-structured protocol + SAP, new-user active-comparator design, PS matching, sensitivity analyses, **negative controls + empirical calibration** |
| **AI Medical Analyst** | Clinical ML with awareness of what breaks it | Leakage-safe features declared and tested, calibration, capacity-based thresholding, subgroup audit, SHAP with honest caveats |
| **Biostatistician** | Estimand thinking, survival methods, assumptions, uncertainty | Cox + PH diagnostics, KM + log-rank, competing risk handling, absolute risk + NNT, E-value, calibrated CIs |
| **Medical Data Scientist** | Full lifecycle from data to served, monitored model | targets, renv, vetiver + pins registry, plumber API, drift monitoring, promotion gate, rollback |
| **Medical Analytics Manager** | Judgment, governance, ability to defend numbers and to say no | Protocol-before-analysis with commit-history proof, ADRs, model card with excluded uses, role matrix, "what would change with PHI", documented limitations including the 85+ calibration finding |

**The three things that will actually get you interviews**, in order:

1. **Negative controls with empirical calibration.** Very few candidates at any level bring this up. It signals you've read the methods literature, not just tutorials.
2. **A demonstrated ability to recover a known effect** — the ground-truth overlay. It converts "I ran a model" into "I validated a pipeline."
3. **The protocol timestamp.** A git tag proving the SAP existed before the estimate. This is the cheapest, most credible integrity signal in the whole repo.

**Three things to say in interviews, verbatim-ready:**
- "I separated estimation from prediction at the architecture level, because conflating them is the most common failure in healthcare analytics."
- "My adjusted estimate recovered the injected true hazard ratio, and my negative controls confirmed the residual systematic error was small enough to calibrate."
- "The model was well-calibrated overall but under-predicted risk in patients over 85, so I documented it as a limitation rather than shipping it silently."

---

## 17. Repository Structure

```
careevidence-ai/
├── README.md                     problem, architecture, findings, demo, disclaimer
├── renv.lock
├── _targets.R
├── Makefile                      make generate | seed | pipeline | test | serve
├── config/
│   ├── study.yml                 study id, windows, TAR, seeds
│   ├── cohort_v1.yml
│   ├── feature_spec_v1.yml       ← the anti-leakage contract
│   └── model.yml                 hyperparameter grid, promotion thresholds
├── sql/
│   ├── migrations/               001_schemas … 0NN_grants (ordered, idempotent)
│   ├── etl/                      synthea → OMOP CDM 5.4
│   ├── cohorts/                  target, comparator, outcomes, negative controls
│   └── features/                 leakage-safe feature views
├── R/
│   ├── ingest.R  quality.R  fitness_for_use.R
│   ├── cohort.R  concept_sets.R
│   ├── rwe_covariates.R  rwe_propensity.R  rwe_balance.R
│   ├── rwe_outcomes.R  survival.R  cost_utilization.R
│   ├── negative_controls.R  calibration.R  sensitivity.R
│   ├── features.R  train_model.R  calibrate_model.R  explain_model.R
│   ├── subgroups.R  registry.R  monitoring.R  db.R  logging.R
├── data-raw/
│   └── generate_synthea.R        seeded generation + ground-truth overlay
├── app/
│   ├── app.R
│   └── modules/                  one file per tab, each independently testable
├── api/
│   ├── plumber.R
│   └── validators.R
├── reports/
│   ├── rwe_study_report.qmd      M14 section order
│   ├── model_validation_report.qmd
│   ├── executive_summary.qmd
│   └── data_quality_report.qmd
├── tests/
│   ├── testthat/                 unit + leakage + statistical regression
│   ├── sql/                      data contracts
│   ├── api/                      httr2 contract tests
│   └── fixtures/                 hand-built patients that MUST / MUST NOT qualify
├── docs/
│   ├── protocol.md               ← git-tagged before analysis
│   ├── sap.md                    ← git-tagged before analysis
│   ├── architecture.md           (this document)
│   ├── data_dictionary.md
│   ├── model_card.md
│   ├── privacy_security.md
│   ├── monitoring_plan.md
│   ├── protocol_deviations.md
│   ├── limitations.md
│   └── adr/                      001-why-omop … 012-why-capacity-threshold
├── docker/
│   ├── Dockerfile.pipeline  Dockerfile.shiny  Dockerfile.api
├── docker-compose.yml
└── .github/workflows/
    ├── ci.yml                    tests, render, build
    └── security.yml              gitleaks, trivy, renv audit
```

---

## 18. Immediate Next Steps

1. **Write `docs/protocol.md` before anything else.** Research question, estimand, target/comparator, index, washout, eligibility, outcomes, covariates, analysis plan. Commit it. Tag it `protocol-v1`. That tag is evidence.
2. Stand up Synthea locally, generate 10k patients with a fixed seed, and look at the raw CSVs by hand for an hour. Do not skip this — you cannot design an ETL for data you haven't looked at.
3. Get OMOP CDM 5.4 DDL running on DuckDB, load `person` and `observation_period` only, and query them from R via `CDMConnector`. That single working query is the spine of the whole project.
4. Write the ground-truth overlay script with an explicit true HR before you write any analysis code. You need the answer key first.
5. Only then start the cohort engine.

**Primary references:** Book of OHDSI (ohdsi.github.io/TheBookOfOhdsi) · OMOP CDM docs (ohdsi.github.io/CommonDataModel) · DARWIN EU package docs (darwin-eu.github.io) · HADES (ohdsi.github.io/Hades) · ICH M14 (via FDA guidance database and EMA) · tidymodels.org · vetiver.posit.co · Epidemiologist R Handbook (epirhandbook.com) · Mastering Shiny · R Packages 2e · targets manual (books.ropensci.org/targets).
