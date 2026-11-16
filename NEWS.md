# Unreleased

- Coincident when roots now handle their own crossing on every callback pass, including
  steep and late-time roots outside the crossing-value tolerance. A sign check on the
  local interpolant selects coincident roots before lower-priority elsewhen cascades.
- Ordinary equations reject cross-variable `pre()` reads instead of silently using the
  current value. Boolean self-reference for hysteresis remains supported.

- The `:mtk` backend rejects direct derivative reads in when-bodies (including reinit
  right-hand sides) with a translation-time diagnostic instead of stale values or `setsym`
  errors. Its non-state read guard also covers Real targets of `sign`, `floor`, `ceil`, `integer`,
  `div`, `mod` and `rem`. Symbolic `div` calls fail explicitly during expression
  translation, where Symbolics cannot yet construct the quotient. The guard conservatively
  follows equations connected to discrete values, Integers, relation Booleans and relations,
  including state-only if-expressions.
  Explicit continuous definitions from states, parameters and time now stop propagation:
  a downstream error involving a discrete setpoint no longer prevents sampling its
  continuous measurement. Implicit dependencies remain conservative. Rejected reads need
  separate algebraic event-step solves and reinit copies. Explicit `pre(v)` is supported.
- The `sign` body-read guard is conservative: `sign` is event-free (MLS 3.6 §3.7.1,
  `noEvent` expansion), but its value at a coincident root is numerically ill-defined
  without an algebraic event-step solve. It does not require discontinuity events.
- Models with `pre()` in any when-condition and `sample()` anywhere reject every
  multi-branch when/elsewhen chain with a non-sample branch: coincident priority replacement
  after snapshot advancement could otherwise leave the replaced branch's values and cascades in the solution.
  This includes equation-defined Boolean and discrete conditions, even when the sample
  is in a separate when-equation or the chain has no direct root.
- Reinitializing the same state in separate when-equations now fails during translation;
  multiple branches of a single when/elsewhen chain remain allowed (§8.3.6).
- Snapshot advancement between event-iteration steps now includes body-only state and
  algebraic reads. Bodies selected in a later step see a previous step's reinit copy,
  independently of unrelated conditions that happen to read `pre` of those unknowns.
- Unsupported compound when-condition diagnostics now show the original condition,
  preserving `pre(v)` rather than displaying a stripped `v` in its place.

- Self-resetting when-conditions no longer leave assignments armed for a later,
  unrelated event.
- Event iteration now advances snapshots of unknowns read through `pre` in
  when-conditions, including equation-defined Integer and discrete-time Real values.
  These conditions no longer abort with "Modelica event iteration did not converge"
  when an event changes the unknown.
- Continuous when roots also detect continuous variables that appear only inside
  `pre`, for accepted nonstandard conditions using `pre(continuous_variable)`.
  These condition snapshots advance during event iteration, including when the body
  reinitializes the state or changes an algebraic dependency.
- `WhenBlock.condition` now preserves `pre(v)` as `ModelingToolkit.Pre(v)`;
  previous versions replaced it with `v` in when-conditions. Backends must resolve
  these markers using shared values for each whole-system event iteration.
  `WhenBlock.crossing` contains plain `v`, since `pre(v) = v` between events.
- Equation-defined Boolean definitions and their left-limit history are not exposed
  in `DiscreteModel`. Independent backends cannot yet implement `pre(b)` for these
  Booleans from the public IR alone; delegate to `MTKEventsBackend` for these cases.
  SynchToolkit compatibility with Pre-marked conditions has not been verified.
- Calls to `floor`, `integer`, `ceil`, `div`, `mod`, or `rem` with continuous arguments
  written directly in when-conditions now raise `UnsupportedFeatureError` instead of
  silently missing required discontinuity events. Discontinuity event generation remains
  unsupported; when-conditions using equation-defined intermediates can still miss
  discontinuity events if the intermediate is not also covered by the body-read guard.
- Logical use of when-assigned Booleans now raises `UnsupportedFeatureError` with a
  diagnostic explaining the limitation, instead of symbolic type errors.
  This validation also covers if-expression and if-equation conditions.
