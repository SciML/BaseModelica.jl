# Unreleased

- `WhenBlock.condition` now preserves `pre(v)` as `ModelingToolkit.Pre(v)`;
  previous versions replaced it with `v` in when-conditions. Backends must resolve
  these markers using shared values for each whole-system event iteration.
  `WhenBlock.crossing` contains plain `v`, since `pre(v) = v` between events.
- Equation-defined Boolean definitions and their left-limit history are not exposed
  in `DiscreteModel`. Independent backends cannot yet implement `pre(b)` for these
  Booleans from the public IR alone; delegate to `MTKEventsBackend` for these cases.
  SynchToolkit compatibility with Pre-marked conditions has not been verified.
- Calls to `floor`, `integer`, `ceil`, `div`, `mod`, or `rem` with continuous arguments
  in when-conditions now raise `UnsupportedFeatureError` instead of silently missing
  required discontinuity events. Discontinuity event generation remains unsupported.
- Logical use of when-assigned Booleans now raises `UnsupportedFeatureError` with a
  diagnostic explaining the limitation, instead of a symbolic `MethodError`.
