# BaseModelica.jl: BaseModelica Importers for ModelingToolkit.jl

BaseModelica.jl is an interface for the SciML open source software organization for importing
BaseModelica, a new standard from the Modelica association for lowered Modelica code. As such,
it makes it easy to import Modelica models into ModelingToolkit.

## Installation

To install BaseModelica.jl, use the Julia package manager:

```julia
using Pkg
Pkg.add("BaseModelica")
```

## API

```@docs
parse_basemodelica
parse_experiment_annotation
create_odeproblem
experiment_settings
BaseModelica.UnsupportedFeatureError
```

## Constants and parameters

How declarations map to ModelingToolkit, and what `remake` can change afterwards:

| BaseModelica | ModelingToolkit | changeable after loading? |
|---|---|---|
| `constant Real c = 9.81` | inlined: every reference becomes `9.81` | no; `c` is not in the system |
| `parameter Real p = 2.0` | tunable parameter with initial value `2.0` | yes |
| `parameter Real r = p*q` | parameter with binding `r = p*q` | no; recomputed from `p` and `q` |
| `parameter Integer n = 3 annotation(Evaluate = true)` | non-tunable parameter | not reliably, see below |

- **Constants** are inlined. ModelingToolkit's `@constants` only marks a parameter
  `tunable = false`, which `remake` can still change; a Modelica constant cannot change.
  The value of a constant is not available as `prob.ps[c]`. A constant whose value is not
  a number (no binding, say) stays a non-tunable parameter.
- **Dependent bindings** become ModelingToolkit bindings, so
  `remake(prob; p = [sys.p => 5.0])` recomputes `r`, and so does every parameter bound to
  `r`. A bound parameter cannot be set itself: `remake(prob; p = [sys.r => 7.0])` throws.
  Bindings are listed by `ModelingToolkit.bound_parameters(sys)`, not by `parameters(sys)`.
- **`Evaluate = true` parameters** were evaluated by the tool that wrote the file, which may
  have used their value to size an array, unroll a `for` loop, pick an `if` branch or remove
  a conditional component. They become parameters with `tunable = false`, and a binding
  such as `k = 2*n` is evaluated to a number. Their description reads
  `parameter 'n' was evaluated at translation (Evaluate=true); recompile to change it`.
  ModelingToolkit has no metadata that makes `remake` or `setp` reject a parameter, so
  changing one is not an error; loading such a model warns once, listing them. Change the
  value in the Modelica source and translate again instead.
- **Inert parameters**, which no equation, binding, start value or other attribute
  references, were most likely used at translation by a tool that did not mark them
  `Evaluate = true`. Loading the model warns once, listing them: changing them has no
  effect.

## Booleans, events and the solver

- **Booleans defined by an equation**, such as `off = s < 0` or the hysteresis
  `y = pre(y) and u < a or u < b`, hold their value between events, as relations do in
  Modelica. Each is a discrete parameter holding 0 or 1 (equations see `off > 0.5`), so
  `sol.ps[sys.off]` reads 0.0 or 1.0. It is solved during initialization together with the
  unknowns it depends on, instead of keeping a `start` value that contradicts its
  definition, and `remake` with new initial values solves it again. Every relation of a
  definition that varies continuously gets a zero-crossing event, after which the Booleans
  are re-evaluated until none changes. They are also re-evaluated after any step at which
  one disagrees with its definition, which catches relations that jump at another event
  (`reinit`, `when` assignments).
- **Time events**: the instants at which an if-condition comparing `time` with a number or
  an expression of parameters switches (`if time < startTime then ...`) are stored as
  `tstops` on the system. ModelingToolkit passes them to every problem built from it, so
  the solver stops there instead of stepping over the discontinuity, and they follow
  parameter changes.
- **Models without differential states**: error control does not limit the step size, so
  a single step can span the whole simulation. `create_odeproblem` sets `dtmax` to the
  experiment `Interval` (or a 500th of the time span) for such models, so that events
  between steps are found; when building the problem yourself, pass `dtmax`. Reading
  `sol(t; idxs = ...)` is exact between steps, while `sol[var]` only holds the saved
  points (`saveat` is the `Interval`).
- **`assert` in an `initial algorithm`** is checked once the model is initialized, with the
  current parameters and initial values: a failed assertion throws from `solve` (level
  `AssertionLevel.warning`: logs a warning). One that can never hold is rejected when the
  model is loaded. `assert` in equations is not checked.
- **Threads**: conversions are serialized by a lock, so `parse_basemodelica` can be called
  from several tasks. The `:antlr` parser calls Python and only runs on the main thread;
  use `parser = :julia` elsewhere.

## Discrete backends

How discrete variables and `when` equations are lowered is pluggable. BaseModelica
evaluates them into a symbolic [`BaseModelica.DiscreteModel`](@ref) and passes it to a
backend. The built-in backend, `:mtk`, uses ModelingToolkit symbolic events. Other packages
provide backends by subtyping [`BaseModelica.AbstractDiscreteBackend`](@ref) and calling
[`BaseModelica.register_discrete_backend!`](@ref) from `__init__`. For example,
SynchToolkit.jl registers `:synchtoolkit` from its `SynchToolkitBaseModelicaExt` extension,
so `discrete_backend = :synchtoolkit` works after `using SynchToolkit`.

Backend compatibility: `WhenBlock` preserves each branch and records its `chain` and
`priority`; independent equations with equal triggers are not merged. The original
five-argument constructor remains available for independent branches. A non-sample
block can have `crossing === nothing`: Boolean aliases and equation-defined Boolean
conditions change during event iteration. Use `block.condition` and
[`BaseModelica.when_edge`](@ref) with stored condition history for those blocks. Seed
that history at initialization without activating ordinary when-clauses. Backends can
return callbacks in `LoweredDiscrete.event_iteration` to have BaseModelica iterate them
after relation-Boolean updates until all conditions are inactive. Their conditions must
be symbolic Boolean expressions (or empty preset-time vectors for disabled callbacks);
other condition types raise `ArgumentError`. Preset-time and periodic clocks belong in
`discrete_events` and run once. These callback passes solve one simultaneous equation
system: all active bodies share the same `pre` values, including bodies activated by
Boolean equations or other when assignments. Pre-values advance together only between
whole-system event iterations, after solving the equations and when-conditions together
(Modelica 3.6 §8.5 and §3.7.5). States stay fixed within a step; reinit values are copied
at its end, before advancing their pre-values (§8.3.6).

The built-in `:mtk` backend rejects plain derivative reads in when-bodies and reinit
right-hand sides. It also conservatively rejects non-state reads connected through equations
to discrete values, Integers, relation Booleans, relations (even state-only if-expressions),
or `sign`/`floor`/`ceil`/`integer`/`div`/`mod`/`rem`. Implicit and alias dependencies are included;
explicit continuous definitions from states, parameters and time stop propagation, so an
unrelated downstream discrete setpoint does not prevent sampling a continuous measurement.
The rejected reads require a separate algebraic event-step solve before reinit copies.
Explicit `pre(v)` reads remain supported. Models with `pre()` in any when-condition also
reject a when/elsewhen chain mixing sample clocks and non-sample branches, since late
coincident priority replacement cannot restore values after snapshot advancement.
Symbolic `div` calls are rejected during expression translation.
A state may be reinitialized in multiple branches of one chain, but not in separate
when-equations; the latter is diagnosed during translation.
Backends that delegate event handling can use `lower_discrete(MTKEventsBackend(), model)`.

Backend compatibility change: `WhenBlock.condition` now preserves `pre(v)` as
`ModelingToolkit.Pre(v)` instead of replacing it with `v`. Backends must resolve those
markers using the iteration's shared pre-values. `WhenBlock.crossing` uses plain `v`
instead, because `pre(v) = v` between events. The public `DiscreteModel` does not expose
the definitions or left-limit history of equation-defined Booleans. Backends needing
`pre(b)` for those Booleans must currently delegate to `MTKEventsBackend`; independent
handling needs a future IR extension. SynchToolkit compatibility for these cases has
not been verified.

```@docs
BaseModelica.AbstractDiscreteBackend
BaseModelica.register_discrete_backend!
BaseModelica.unregister_discrete_backend!
BaseModelica.lower_discrete
BaseModelica.declare_discrete
BaseModelica.compile_system
BaseModelica.DiscreteModel
BaseModelica.WhenBlock
BaseModelica.when_edge
BaseModelica.LoweredDiscrete
BaseModelica.MTKEventsBackend
```

## Contributing

  - Please refer to the
    [SciML ColPrac: Contributor's Guide on Collaborative Practices for Community Packages](https://sciml.github.io/ColPrac/stable/)
    for guidance on PRs, issues, and other matters relating to contributing to SciML.

  - See the [SciML Style Guide](https://github.com/SciML/SciMLStyle) for common coding practices and other style decisions.
  - There are a few community forums:
    
      + The #diffeq-bridged and #sciml-bridged channels in the
        [Julia Slack](https://julialang.org/slack/)
      + The #diffeq-bridged and #sciml-bridged channels in the
        [Julia Zulip](https://julialang.zulipchat.com/#narrow/stream/279055-sciml-bridged)
      + On the [Julia Discourse forums](https://discourse.julialang.org)
      + See also [SciML Community page](https://sciml.ai/community/)

## Reproducibility

```@raw html
<details><summary>The documentation of this SciML package was built using these direct dependencies,</summary>
```

```@example
using Pkg # hide
Pkg.status() # hide
```

```@raw html
</details>
```

```@raw html
<details><summary>and using this machine and Julia version.</summary>
```

```@example
using InteractiveUtils # hide
versioninfo() # hide
```

```@raw html
</details>
```

```@raw html
<details><summary>A more complete overview of all dependencies and their versions is also provided.</summary>
```

```@example
using Pkg # hide
Pkg.status(; mode = PKGMODE_MANIFEST) # hide
```

```@raw html
</details>
```

```@eval
using TOML
using Markdown
version = TOML.parse(read("../../Project.toml", String))["version"]
name = TOML.parse(read("../../Project.toml", String))["name"]
link_manifest = "https://github.com/SciML/" * name * ".jl/tree/gh-pages/v" * version *
                "/assets/Manifest.toml"
link_project = "https://github.com/SciML/" * name * ".jl/tree/gh-pages/v" * version *
               "/assets/Project.toml"
Markdown.parse("""You can also download the
[manifest]($link_manifest)
file and the
[project]($link_project)
file.
""")
```
