# IX-AGI runtime components

- `IXAGI.BF`: complete BlackFox Julia engine nested under its original module.
- `DualOrganism.left`: BlackFox native-gated action/world-model learner and symbolic planner.
- `DualOrganism.right`: independent relational effect learner maintaining its own evidence memory. This is NOT IX-Sally.
- `NeuralCallosum`: continuously clocked **numeric** activation link with one-step delay, sparse signed projection, bounded plasticity, optional phase windows, and lesion mode. No text, peer answers, authorization data, or hidden transition oracle is transferred.
- `:late_fusion` is a deliberately strong negative control: right-hand predictions reach the decision point without any neural-signal channel; if it matches the coupled system, dual-signal necessity is not established.
- `choose!`: attempts a BlackFox plan first. In true coupled mode the right subsystem emits **only numerical estimated-state-change activity**, transmitted through a delayed sign-sensitive projection. The left matches that activation against a numerical goal representation, without receiving the peer’s proposed future symbolic state. The explicit `:late_fusion` negative-control mode can consult the right symbolic predicted state directly. Without aligned evidence the agent HOLDs or gathers new observations.
- `step!`: passes all real adapter dispatch through actual `BF.act!`; permission and risk remain mandatory. The right hemisphere can never dispatch on its own.
- `save_organism` / `load_organism`: separate BlackFox snapshot and callosal/right snapshot with digests. These are tamper-detection hashes, not authenticated signatures against a malicious actor.

The independent predictor generalizes command arguments by role, but keeps names
for external persistent objects. This requires stable environmental object identity;
it is not general representation learning. A test environment with a persistent
`hub` makes the feature learnable. Novel object vocabulary or new environments
may defeat it and must be tested as negative controls.

Native build: `gprbuild -p -P vendor/IXBlackFoxAGI/ada/ix_guard.gpr`.
Julia run: `julia --project=. bin/ixagi.jl`.

No demonstrated consciousness, self-awareness, artificial general intelligence,
formal proof of systemwide safety, or deployment suitability.
