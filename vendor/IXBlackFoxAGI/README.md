# IX-BlackFox-AGI

**Adaptive learning and planning in Julia, with native Ada/SPARK authorization.**

The objective is to develop true AGI. **That objective has not been achieved or established by this release.** This implementation learns action models from interaction, plans with those learned models, discovers reusable procedures, retains its experience, and revises predictions when evidence contradicts them.

**Version: 0.1.0**, retained for this initial unpublished release. Native execution has been verified on Linux. No Python runtime, paid model API, pretrained model, or external Julia package is required. Native Windows execution and GNATprove have not been verified here. No GitHub push or remote CI result is claimed.

## First-release cognitive extension (verification pending)

This initial release now also contains an **implemented, opt-in metacognitive
controller**, evidence-derived relational concept induction, and
context-preserving nonstationary learning repair, and bounded
self-generated inquiry selection. The feature constructor
separates training, selection, and untouched audit contexts rather than
renaming previously supplied rules. The action controller uses measured
prediction failures to choose diagnostic exploration and records its choice
before the existing mandatory Ada-gated adapter dispatch.

The new code is **not yet proven to pass native Julia/Ada tests in this edited
archive**, because those toolchains were unavailable during the edit.
The test fixture and GitHub CI are supplied for execution. Do not infer that
previously recorded results apply to this modified code. The release version
remains **0.1.0**. Read [the cognitive engineering delta](docs/COGNITIVE_ENGINEERING_DELTA.md)
for implemented mechanisms, failure limits, and an honest Sally comparison.

After building the native gate, inspect a saved checkpoint or derive candidate
concepts and measured reliability profiles:

```bash
julia --project=. bin/ixbf.jl cognition results/lifetime/trained-seed-101.toml
julia --project=. bin/ixbf.jl concepts results/lifetime/trained-seed-101.toml
```

To enable the new decision controller when writing a host adapter, call
`pursue!(mind, env, goal; cognitive_control=true)`; or run
`inquire!(mind, env; steps=10)` to execute native-gated experiments chosen
from measured prediction failures and gaps. The default remains off
so that the original experimental baselines are not silently changed.

## What the system actually does

- Starts with no command-effect rules and learns conditional effects and prerequisites from before/after observations, including unsuccessful interventions.
- Replaces object identities with variables so acquired models can transfer to new objects and larger configurations.
- Plans multiple actions ahead using learned transitions, without consulting the simulator during search.
- Investigates unfamiliar dynamics when it lacks a supported plan, compares predicted and observed consequences, and replans after acting.
- Discovers parameterized action sequences from successful episodes and reuses them as search shortcuts.
- Abstains when evidence conflicts; repeated confirmed contradictions can replace a command model's working dynamics regime.
- Saves learned evidence, procedures, budgets and a chained trace. Replay reconstructs the model and checks consistency against the checkpoint.
- Requires an Ada authorization decision before runtime adapter dispatch. An unavailable native library is a hard failure.

The learner consumes already-symbolic, fully observed relations and syntactic commands. It does not provide general language understanding, visual grounding, arbitrary representation invention, unrestricted source self-modification, or evidence of human-level generality. The older numeric expression learner remains available as a separate experiment.

## Historical executed results (pre-extension snapshot only)

| Evaluation | Observed result |
|---|---:|
| Julia integration and functional assertions | **572 passed** |
| Held-out delivery, switch, workshop and combined instances | **160/160 solved** |
| Reactive control with the same learned models | 112/160 solved |
| Uniform random action control | 36/160 solved |
| Cold block-manipulation acquisition with randomized relation/command names | **20/20 solved** |
| Cold random-action control, same 300-action limit | 5/20 solved |
| Checkpoint reconstruction audit | **PASS** |

**The table below and `VALIDATION_REPORT.md` describe the original uploaded source, not the new edited sources.** Rerun the suite before citing those results for this archive.

The cold learner began with empty memory and averaged **55.8 actions**, with 55 prediction errors across the 20 acquisition cases. The frozen transfer planner made 881 predictions with no observed mismatches. These are internally authored symbolic simulations, not proof of AGI. The combined tasks join independent mechanics. The original failed development cases are retained.

Read [VALIDATION_REPORT.md](VALIDATION_REPORT.md) for scope, raw evidence and unverified areas; [the evaluation protocol](docs/INTERACTION_PROTOCOL.md) specifies what each comparison measures.

## Build and use the included learned memory

Install Julia 1.10 and GNAT/GPRbuild, then run from this directory:

```bash
gprbuild -p -P ada/ix_guard.gpr
gprbuild -p -P ada/guard_test.gpr
./ada/test_bin/guard_smoke
julia --project=. bin/ixbf.jl inspect results/lifetime/trained-seed-101.toml
julia --project=. bin/ixbf.jl plan results/lifetime/trained-seed-101.toml examples/problem.toml results/my-plan.toml
```

The external example supplies facts, syntactic commands and a goal, without supplying transition rules. The included checkpoint produces a three-command plan for a new object. Planning writes a proposal file; it does not execute external actions.

For a fresh interaction-learning run and an untrained combination of environments:

```bash
julia --project=. examples/lifetime.jl
```

To create a fresh learned checkpoint, inspect it, or independently replay its evidence:

```bash
julia --project=. bin/ixbf.jl train results/new-mind.toml 47
julia --project=. bin/ixbf.jl inspect results/new-mind.toml
julia --project=. bin/ixbf.jl audit results/lifetime/trained-seed-101.toml
```

Windows setup, PowerShell commands and first-push instructions are in [WINDOWS_HANDOFF.md](docs/WINDOWS_HANDOFF.md). Build the native library on your own platform; compiler binaries and platform-specific build products are excluded from the ZIP.

## Reproduce the checks

```bash
bash tools/run-checks.sh
```

Or run the components individually:

```bash
julia --project=. test/runtests.jl
julia --project=. experiments/evaluate.jl
julia --project=. experiments/open_world.jl
julia --project=. experiments/cognitive_campaign.jl
IXBF_SEEDS=10 julia --project=. benchmarks/run.jl
```

The GitHub workflow builds Ada, executes the tests and both interaction campaigns, and uploads the resulting evidence. Its remote status becomes known only after it actually runs. The optional SPARK workflow is separate.

## Source and evidence map

| Path | Purpose |
|---|---|
| `src/relational.jl` | Object-variable induction, conditional transition models, planning |
| `src/mind.jl` | Interaction loop, exploration, consequences and persistent memory |
| `src/procedures.jl` | Learned action-sequence abstractions and search reuse |
| `src/concepts.jl` | Context-disjoint fitting, selection and audit of derived relational features |
| `src/metacognition.jl` | Prediction confidence and evidence-conditioned strategy selection |
| `src/inquiry.jl` | Bounded self-generated diagnostic inquiry objectives |
| `src/audit.jl` | Independent model reconstruction and source fingerprinting |
| `ada/src/` | Native decision function and contracts |
| `bin/ixbf.jl` | Train, inspect, audit and external-problem planning CLI |
| `experiments/` | Host-only simulators and executed comparison campaigns |
| `test/` | Integration, negative controls and independent randomized-rule checks |
| `experiments/cognitive_campaign.jl` | Ten independently named feature-transfer tasks plus parity negative controls; publishes every case |
| `results/` | All case observations, learned checkpoints and verification logs |
| `docs/ARCHITECTURE.md` | Learning mechanisms, hypothesis limits and trust boundaries |

Custom adapters implement `perceive`, `commands`, and `transition!` for an `Environment`. The core does not dispatch by the simulator family names. Predicates and commands are interpreted through observed consequences, within the supported symbolic hypothesis class.

## Authority, provenance and licensing

The Ada decision function is not an operating-system sandbox and cannot authenticate a host's observations. Checkpoint and trace hashes check integrity and consistency; they are not signatures or independent attestations. Formal code proof, intelligence evidence and real-world safety are distinct questions.

This implementation does not vendor donor code. The current review of Sally, Cognition and WorldTwin is recorded in [DONOR_AUDIT.md](docs/DONOR_AUDIT.md), with exact archive hashes.

The project remains **source-available for restricted evaluation only**, under [LICENSE](LICENSE). Commercial and operational rights require a separate written agreement with Bryce Lovell. It is not an open-source license.

**AI proposes. Humans decide.**
