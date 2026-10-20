# Executed validation report

> **HISTORICAL BASELINE ONLY.** This report and its source fingerprint were
> produced for the original uploaded v0.1.0 code before the cognitive extension.
> The newly modified files and test suite were **not** executed in this editing
> environment (Julia, GNAT, and GPRbuild unavailable). This file must not be
> used as a passing validation receipt for the revised release. See
> [docs/COGNITIVE_ENGINEERING_DELTA.md](docs/COGNITIVE_ENGINEERING_DELTA.md).


Verification date: 2026-10-17. Source version: **0.1.0**, retained for the initial unpublished release.

**Native execution passed on Linux x86_64 with Julia 1.10.10 and GNAT 13.3.0.**

| Check | Observed result |
|---|---|
| Ada compilation with assertions and overflow checks | PASS |
| Ada smoke tests | PASS, 10 checked decisions |
| Julia integration and functional tests | PASS, 572 assertions across 15 test sets |
| Checkpoint replay and model/evidence consistency | PASS |
| External TOML problem planning | PASS, 3 primitive commands |
| Original numeric experiment | 80 rows recorded, including unsupported controls |
| GitHub remote CI | Not executed, no repository push performed |
| Native Windows execution | Not executed |
| GNATprove formal verification | Not executed |
| AGI objective | Not achieved or established |

## Held-out transfer, learning disabled

Five independently trained models each received 32 new instances. Every planner action had a supported model prediction; **881 predictions, zero observed mismatches**. These are supplied symbolic simulations with known mechanics, new object identifiers and configurations, and one composition of independent domains.

| Domain | Planner | Reactive control | Uniform random actions |
|---|---:|---:|---:|
| courier | 40/40 | 13/40 | 0/40 |
| switchboard | 40/40 | 40/40 | 7/40 |
| workshop | 40/40 | 40/40 | 25/40 |
| combined | 40/40 | 19/40 | 4/40 |
| **Total** | **160/160** | **112/160** | **36/160** |

Random action selection ignores the learned model; its diagnostic predictions still use that model. The reactive control also has the same learned model. Neither baseline learns during evaluation. Each policy has 40 actions per case. Correlated cases and internal simulator authorship limit interpretation.

## Starting without a world model

On 20 fresh block-manipulation seeds with command and relation names randomized, the online learner solved **20/20** goals, averaging **55.8 actions**, maximum **88 actions**. Uniform random actions solved **5/20** within the same 300-action limit. The learner made **55 prediction errors while acquiring the new dynamics**. Errors are retained in the report rather than removed from the score.

Development seeds 201–205 initially produced only **1/5** learner successes, versus **2/5** random. Correcting the exploration policy produced **5/5** on those development cases; confirmation used fresh seeds 301–320. Before/after development evidence is included.

## Scope of the results

The environment observations are already symbolic and fully supplied by the host. These tests do not demonstrate vision, language understanding, human-level breadth, arbitrary new representations, unrestricted self-modification, partial-observation inference, real-world transfer or AGI. The combined environment composes independent requirements rather than learning a new cross-domain causal law.

## Evidence locations

- `results/verification/julia-tests.log`: complete passing test summaries.
- `results/verification/checkpoint-replay.log`: independent reconstruction audit.
- `results/lifetime/report.toml` and `cases.csv`: all 480 policy/case evaluations.
- `results/lifetime/trained-seed-*.toml`: retained learned evidence and procedures.
- `results/open_world/report.toml`: all 40 fresh-seed learner/control evaluations.
- `results/open_world/development-*.toml`: failed and corrected development runs.
- `results/numeric.csv`: original bounded numeric experiments.
- `results/example-plan.toml`: actual output for the external example problem.

Runtime-source SHA-256: `da327214cd856e955511d3f694959968d2f9ae48d3868bf5d916f2d631a7dc3c`.

Raw reports also fingerprint the evaluation scripts. Checkpoints and trace chains establish internal consistency, not independent sensor authenticity or third-party certification.
