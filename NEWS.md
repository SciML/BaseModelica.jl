# Unreleased

- Known upstream limitation: models that keep algebraic equations after simplification
  and have a `when` or other event can fail with problem-level `saveat` (including an
  experiment `Interval`): `ArgumentError: range step cannot be zero`. ModelingToolkit
  appends the parent system's algebraic equations to every affect, making it implicit.
  ModelingToolkitBase's `compile_implicit_affect` forwards problem-level `saveat` to an
  `ImplicitDiscreteProblem` with a zero-length time span. Use
  `create_odeproblem(file; saveat = Float64[])`
  and pass the interval as `saveat` to `solve` instead. The README and docs show this path.
- If-equations can read derivatives defined by other equations, including in only
  one branch. The Julia parser accepts a negative left side after `else`.
- Unfixed state starts supply missing initial values after state selection, while
  explicit initial equations and algebraic initialization constraints take precedence.
  Completed starts yield to user initial values, including coupled linear state overrides
  through `ODEProblem` and `remake(...; u0 = ...)`. Ambiguous starts are chosen in
  declaration order. For coupled groups, parameter-only `remake` keeps the previous
  initial point as its guess; pass `u0` or rebuild `ODEProblem` to reevaluate starts.
  Nonlinear algebraic equations can read states with unfixed starts. Nonlinear coupled
  groups retain declaration-order start defaults and nonlinear iteration guesses;
  a user `u0` on a sibling can overdetermine initialization (`InitialFailure`).
  Linear initialization constraints are rank-checked at declared parameter values:
  inconsistent constraints fail clearly and redundant constraints use starts for free
  coordinates. Whole-array initial reductions participate in retained-array incidence.
  After `simplify = false`, the exported `check_algebraic_crossings(compiled)` hook also
  completes initialization and finalizes array reinit targets;
  `complete_unfixed_initialization(compiled)` is available for other discrete backends.
  On `:mtk`, use `check_algebraic_crossings` for array reinit finalization. Keep the
  returned system from either hook. Time-driven changes between differential and
  algebraic state constraints are rejected before solving.
- Whole-array reads in `when` bodies and relation-Boolean definitions participate in
  the same event dependency checks as element reads, including reductions and aliases.

- `arrays = :keep` preserves supported numeric arrays as ModelingToolkit array symbols
  and emits whole-array equations, except in models with when-equations, where the
  discrete backend currently returns scalar equations. Unsupported declarations fall back
  individually to scalar symbols, with debug diagnostics. Matrix powers and mixed loop/whole-array
  if-equation branches preserve Modelica array semantics. The default remains
  `arrays = :scalarize`.

- Initial and regular if-equations share branch semantics: balanced branches retain
  symbolic `ifelse` expressions, so tunable parameters follow `remake` and dynamic initial
  conditions are supported. Unbalanced branches select at load without evaluating inactive
  equations or adding a zero fallback. Dynamic unbalanced conditions raise an unsupported
  feature error; tunable parameters used in structural selection are named in a warning
  once per load and require reloading to change the equation structure.
- Modelica `promote(A, n)` adds trailing singleton dimensions. `scalar`, `vector` and
  `matrix` also validate dimensionality when converting arrays.
- Both parsers accept field access on function results, such as `f(x).y`.
- Partly assigned array and record function locals report unassigned execution paths
  instead of failing with an internal type error.

- Records support nested components and parameters, starts and bindings, constructors,
  and record inputs/outputs and field assignments in user functions. Function record values
  use NamedTuples internally; model records expand into fields before numeric array
  lowering. Literal-sized arrays of records support per-record and `each` field modifiers.
- Symbolic `if` branches in user functions read their own earlier assignments, including
  nested branches and array outputs such as MSL `Frames.Quaternions.from_T`.
- `floor`, `ceil`, `integer`, and `div` evaluate at load in structural array dimensions,
  including function outputs and array constructors. Ordinary equation values stay symbolic.
- Both parsers accept `each`, `public`, and `protected`. The Julia parser also preserves
  zero-argument calls and named arguments, recognizes annotations after initial algorithms,
  and rejects external record functions instead of silently returning field defaults.

- Direct when-relations preserve their root direction during event iteration using
  a crossing-rate-scaled tolerance at that instant. A shorter tangent step reduces
  rate-estimate cancellation for late-time sine/angle crossings. Non-finite estimates
  fall back to `1e-9` so reinit-enabled events can still iterate. The tangent normally
  comes from the pre-reinit interpolant; if non-finite, identity- and diagonal-mass
  ODEs use the RHS at the current, possibly post-reinit, state. Only differential
  rows of a diagonal mass matrix have an RHS-derived tangent. Landing within another
  threshold's tolerance can delay its firing until the end of the next accepted
  step, possibly the simulation stop time (see README).
- The `:mtk` backend checks both default and custom (`simplify = f`) compilation for
  when-crossings that depend on retained algebraic unknowns (zero mass-matrix rows),
  including through observed aliases and chains of equation-defined Booleans. Hysteresis
  Boolean crossings on such unknowns are also rejected: wrong-side root updates can
  latch their memory. Plain level-semantic relations (`off = s < 0`, as in ideal diodes
  and switches) remain supported on algebraic signals. The diagnostic names the
  condition. `simplify = false` does not run the check; users compiling themselves can
  call `BaseModelica.check_algebraic_crossings(compiled)`.
- Coincident when roots handle their own crossing on every callback pass, including
  steep and late-time roots outside the crossing-value tolerance. Pending roots use
  a sign check along the solution tangent instead of a blind near-zero flip, avoiding
  duplicate firings and noise from differencing local interpolants. Exact-zero roots
  also follow the tangent direction instead of inventing another edge. Coincidence is
  recognized only within `32eps(Float64)*max(1, abs(t))`; larger solver root-location
  errors can change elsewhen priority. Vern9 can also report the same root twice
  upstream. See README's "Known limitations" for details.
- Ordinary equations reject cross-variable `pre()` reads instead of silently using the
  current value. Boolean self-reference for hysteresis remains supported. This limitation
  rejects MSL Logical.Pre and RSFlipFlop, StateGraph, and the friction models that use
  cross-variable `pre()` equations.
- Initial equations and initial algorithms again resolve `pre(v)` of discrete variables
  to their initialization values, including `pre(v) = pre(w)` start constraints. Other
  initial-section `pre()` reads raise `UnsupportedFeatureError` rather than a bare MTK error.

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
