# Unreleased

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
  unsupported; calls hidden behind equation-defined intermediate variables are not
  detected and may still miss events.
- Logical use of when-assigned Booleans now raises `UnsupportedFeatureError` with a
  diagnostic explaining the limitation, instead of symbolic type errors.
  This validation also covers if-expression and if-equation conditions.
