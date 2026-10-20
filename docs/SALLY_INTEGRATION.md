# IX-Sally integration boundary (unfulfilled prerequisite)

IX-Sally's repository description and earlier evaluation documents were reviewed,
but a complete executable checkout of its exact version was not present and
could not be fetched through this runtime's restricted network. Therefore
**this package does not mislabel a new module as the original IX-Sally**.

The present right hemisphere is a freshly implemented, stateful effect learner.
To incorporate the actual IX-Sally runtime, the authorized developer must add
its source checkout as a separate dependency, inspect its memory and reasoning
entry points, and implement a numerical (not conversational) state-vector export:

- Time-indexed model uncertainty, prediction-error and low-dimensional activity
- Recorded representation or hypothesis activations, without private hidden targets
- Schema and dimensionality negotiation and monotonic timestamps
- A source-origin digest that permits trace-to-action auditing
- Fail-closed behavior on malformed, stale, missing or nonfinite tensors
- Independently learned projection basis across heterogeneous representations
- Continuous held-out ablations, equal compute and native adapter tests

Do not present this as completed Sally integration. Do not replace it by
exchanging natural language between Sally and BlackFox.
