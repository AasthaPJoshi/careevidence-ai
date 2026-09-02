# CareEvidence AI — Study Protocol

| | |
|---|---|
| **Protocol version** | v1.0 (initial) |
| **Status** | Draft — written before Synthea data has been generated or examined |
| **Study ID** | `study_htn_hosp_v1` |
| **Author** | Aastha Joshi |
| **Date** | 2026-09-01 |
| **Git tag** | `protocol-v1` (applied to the commit that adds this file) |

> **Why this document exists before any code.** Per ICH M14 (in effect
> 18 March 2026), a non-interventional real-world evidence study should
> start with the research question, not the dataset — question first,
> then a documented fitness-for-use assessment of the data, then design.
> This protocol is deliberately written and git-tagged **before** Synthea
> has generated a single patient. Some parameters below are marked
> **provisional**: they will be confirmed or revised once Phase 2's
> feasibility/fitness-for-use gate has actually looked at the generated
> population. Any revision is recorded as a dated entry in
> `docs/protocol_deviations.md`, not a silent edit to this file.

---

## 1. Background and rationale

Hypertension is one of the most common chronic conditions in
longitudinal EHR data, and comparative studies of first-line
antihypertensive classes are a standard, well-understood use case in
real-world evidence practice. This study is built as a **methods
demonstration**: a full new-user active-comparator design, executed
against a standardized common data model, on synthetic data where the
true treatment effect is known because it was injected by us — so the
pipeline's validity can be checked against a ground truth that no real
observational study ever has access to. See §14 for why this matters
more than the clinical result itself.

## 2. Research question and objectives

**Primary research question:** Among adults newly initiating
antihypertensive therapy, does initiation of an ACE inhibitor, versus
initiation of a thiazide diuretic, change the rate of all-cause
hospitalization within 365 days of treatment initiation?

**Primary objective:** Estimate the adjusted hazard ratio for
all-cause hospitalization, ACE inhibitor initiators vs. thiazide
diuretic initiators, controlling for measured confounding via
propensity score adjustment.

**Secondary objectives:**
- Estimate the absolute risk difference and number-needed-to-treat/harm.
- Describe healthcare utilization (admissions, ED visits) and cost by
  exposure group.
- Assess whether the adjusted estimate recovers the **known true
  hazard ratio** injected into the synthetic outcome-generation process
  (method-validation objective — see §14).
- Quantify residual systematic error using negative control outcomes
  and empirical calibration.

**This is not a regulatory or clinical study.** No treatment
recommendation is intended or should be inferred from any result.

## 3. Study design

New-user, active-comparator cohort design with propensity score
adjustment. Active comparator (rather than a non-user or general
population comparator) is chosen specifically to reduce confounding by
indication — both groups are, by construction, patients whose
clinician decided to start antihypertensive therapy.

## 4. Setting / data source

**Source:** Synthea-generated synthetic patient population (pinned
version, fixed generation seed — see `scripts/data_layer/00_generate_synthea.sh`),
standardized to OMOP CDM 5.4.

**This data is entirely synthetic. No real patient data is used at any
point in this project.**

To support method validation (§14), a documented, seeded overlay
process (`scripts/data_layer/04_generate_ground_truth_overlay.sh`) will
modify Synthea's native exposure assignment to introduce **known,
controlled confounding**, and will generate the outcome under a
**pre-specified true hazard ratio**. This overlay is fully described in
`docs/adr/` and its parameters are fixed and recorded before the cohort
or outcome pipeline is run. Because of this overlay, effect estimates
from this study are a validation of methodology, not a clinical
finding — this is stated in every report and dashboard screen.

**Provisional, pending feasibility check (Phase 2, Step 5):** that the
Synthea hypertension module and medication modules generate sufficient
volume of ACE inhibitor and thiazide diuretic new-initiators at the
planned population size (§11).

## 5. Study population

**Inclusion criteria:**
- Age ≥ 18 years at index date
- At least 365 days of continuous observation prior to index date
  (`observation_period` coverage)
- A new dispensing/prescription of an ACE inhibitor or a thiazide
  diuretic, with index date = date of that first qualifying exposure

**Exclusion criteria:**
- Any prior exposure to either drug class in the 365-day washout
  window before index (ensures "new user," not "prevalent user" or
  "switcher")
- Exposure to both drug classes on the same index date (ambiguous
  initiation)
- No further exclusions planned at this stage; more may be added after
  the feasibility check and recorded as a deviation.

## 6. Exposure definition

| | Target | Comparator |
|---|---|---|
| Drug class | ACE inhibitor (e.g., lisinopril) | Thiazide diuretic (e.g., hydrochlorothiazide) |
| Index date | Date of first qualifying dispensing | Date of first qualifying dispensing |
| Washout | 365 days with no prior exposure to either class | Same |
| Required prior observation | 365 days | Same |

Exact concept sets (RxNorm ingredient/class codes) will be built with
`CodelistGenerator` once the OMOP CDM is populated, and version-hashed
per `docs/architecture.md` §7.2.

## 7. Outcome definition

**Primary outcome:** First all-cause inpatient hospitalization
occurring in the interval (index date, index date + 365 days].

**Negative control outcomes (planned, ~20–50):** Outcomes with no
plausible causal relationship to antihypertensive class choice (e.g.,
accidental injury, routine dental visit), run through the identical
pipeline to characterize residual systematic error via empirical
calibration (`EmpiricalCalibration`). Concept sets for these are
finalized after the OMOP CDM is populated.

**Secondary outcomes:** All-cause emergency department visits;
all-cause healthcare cost in the 365-day follow-up window.

## 8. Covariates / confounders

Measured in the 365 days prior to index date (strictly before index,
per the anti-leakage rule in `docs/architecture.md` §7.2):

- Demographics: age, sex
- Comorbidity burden: Charlson-type comorbidity flags derivable from
  `condition_occurrence`
- Prior healthcare utilization: count of inpatient admissions, ED
  visits, outpatient visits in the prior year
- Prior medication classes (count of distinct drug classes dispensed)
- Relevant baseline labs/vitals where present (e.g., most recent blood
  pressure reading, renal function)

Exact covariate list will be finalized once `FeatureExtraction`-style
covariate construction is implemented and the feasibility check
confirms adequate completeness.

## 9. Follow-up, time-at-risk, and censoring

- **Time-at-risk (TAR):** index date + 1 day to index date + 365 days
- **Censoring events:** death, disenrollment (end of
  `observation_period`), switching to or adding the other exposure
  class, end of study period, whichever occurs first
- Censoring reason is recorded per patient (`censor_reason`), not just
  a censoring date, per `docs/architecture.md` §7.2

## 10. Study size

**Planned Synthea population:** 10,000 patients (see generation
manifest written by `00_generate_synthea.sh`). The realized number of
patients qualifying for the target and comparator cohorts is not yet
known and will be reported in the attrition funnel after cohort
construction (Phase 4). If the qualifying population is too small to
support a stable propensity model, the population size will be
increased and this section updated — logged as a protocol deviation,
not a silent rerun.

## 11. Statistical analysis (summary — full SAP in `docs/sap.md`)

1. Baseline Table 1 with standardized mean differences (unadjusted)
2. Propensity score model; 1:1 matching (primary) and IPTW (sensitivity)
3. Post-adjustment balance check (target: all |SMD| < 0.1)
4. Cox proportional hazards model on matched/weighted population;
   Kaplan-Meier curves; log-rank test; Schoenfeld residuals for the PH
   assumption
5. Absolute risk difference
6. Negative control analysis → empirical calibration of CI and p-value
7. Sensitivity analyses: alternative washout window (180d, 730d),
   alternative TAR, IPTW vs. matching, unadjusted vs. adjusted, E-value
   for unmeasured confounding

`docs/sap.md` will be written and tagged (`sap-v1`) before any of the
above is executed against real cohort data, consistent with this
protocol's own principle.

## 12. Bias, limitations, and intended use

- **Synthetic data.** No result in this study reflects a real clinical
  effect. The ACE inhibitor/thiazide comparison is a vehicle for
  demonstrating study design and analytic methodology, not a claim
  about either drug.
- **Injected ground truth.** Exposure assignment and outcome generation
  are modified by a documented overlay (§4) specifically so that
  pipeline validity can be checked. This is a deliberate choice to make
  the study auditable, not a limitation to hide.
- **Residual confounding.** Even on synthetic data with adjustment,
  negative controls are used to characterize whatever systematic error
  remains in the pipeline itself (coding, cohort logic, model
  specification) — see §7.
- **Not for clinical decision-making**, disclosed on every report,
  dashboard screen, and API response derived from this study.

## 13. Data management and governance

See `docs/architecture.md` for the full data architecture, role-based
access matrix, and audit trail design. `docs/privacy_security.md` (to
be written in Phase 2) will describe how this design would change if
real PHI were substituted for synthetic data.

## 14. Why the method-validation framing matters

A propensity-adjusted hazard ratio computed on Synthea without a known
answer key is not verifiable — there is no way to know if 0.87 is
correct, biased, or noise. By injecting a known true effect and known
null effects (negative controls), this study can report not just an
estimate, but evidence that **the estimation pipeline itself recovers
truth when truth is known**. That is the deliverable this protocol is
actually organized around.

## 15. Version history

| Version | Date | Change |
|---|---|---|
| v1.0 | 2026-09-01 | Initial protocol, drafted before Synthea generation |

## 16. Sign-off

Authored and version-controlled by Aastha Joshi. This is a portfolio
project; there is no institutional review board or sponsor. The git
tag `protocol-v1` on the commit introducing this file serves as the
protocol's timestamp of record.
