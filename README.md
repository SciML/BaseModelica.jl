# BaseModelica.jl

[![Join the chat at https://julialang.zulipchat.com #sciml-bridged](https://img.shields.io/static/v1?label=Zulip&message=chat&color=9558b2&labelColor=389826)](https://julialang.zulipchat.com/#narrow/stream/279055-sciml-bridged)
[![Global Docs](https://img.shields.io/badge/docs-SciML-blue.svg)](https://docs.sciml.ai/BaseModelica/stable/)

[![codecov](https://codecov.io/gh/SciML/BaseModelica.jl/branch/main/graph/badge.svg)](https://app.codecov.io/gh/SciML/BaseModelica.jl)
[![Build Status](https://github.com/SciML/BaseModelica.jl/workflows/CI/badge.svg)](https://github.com/SciML/BaseModelica.jl/actions?query=workflow%3ACI)

[![ColPrac: Contributor's Guide on Collaborative Practices for Community Packages](https://img.shields.io/badge/ColPrac-Contributor%27s%20Guide-blueviolet)](https://github.com/SciML/ColPrac)
[![SciML Code Style](https://img.shields.io/static/v1?label=code%20style&message=SciML&color=9558b2&labelColor=389826)](https://github.com/SciML/SciMLStyle)

A parser for the [Base Modelica](https://github.com/modelica/ModelicaSpecification/tree/MCP/0031/RationaleMCP/0031) format. Contains utilities to parse Base Modelica model files in to Julia objects, and to convert Base Modelica models to [ModelingToolkit](https://docs.sciml.ai/ModelingToolkit/stable/) models.

Base Modelica is as of yet only a proposal with no concrete specification, so the grammar and features of the language are subject to change.

## Supported features

- Real, Integer, Boolean and enumeration scalar variables, parameters and constants, with
  `start`/`fixed` attributes, `stateSelect`, initial equations and `parameter equation` guesses.
- Equations with arithmetic, relational and logical operators, `if`-expressions and
  `if`-equations, the built-in functions listed in `src/maps.jl` (including `der`, `pre`,
  `delay`, `noEvent`, `smooth`, `homotopy`), and scalar `for`-equations over constant ranges.
- `when`/`elsewhen` equations. A rising-edge condition (a relation or a Boolean variable)
  becomes a ModelingToolkit `SymbolicContinuousCallback`, and `sample(0, dt)` becomes a
  periodic `SymbolicDiscreteCallback`. In the body, `v = expr` updates a discrete variable
  and `reinit(x, expr)` resets a continuous state at the end of an event-iteration step.
  States stay fixed within each step; `pre(v)` reads the previous iteration's value.
  Plain body reads of non-state unknowns coupled by equations to discrete-time quantities
  (including connection aliases) currently raise `UnsupportedFeatureError`: these require
  recomputing algebraics before copying reinit values. Explicit `pre(v)` reads remain
  supported.
  The lowering is pluggable: other packages register backends with
  `BaseModelica.register_discrete_backend!`. With `using SynchToolkit` (SynchToolkit.jl
  ships the extension), `discrete_backend = :synchtoolkit` (experimental) makes discrete
  variables clocked variables on an `EventClock`/`Clock`, compiled by SynchToolkit.
- Boolean variables defined by an equation (`off = s < 0`, hysteresis with `pre`) keep their
  value between events and are solved consistently at initialization and re-evaluated at
  events. `if time < startTime` conditions become solver `tstops` on the system, and
  `assert` in an `initial algorithm` is checked at initialization. See the "Booleans,
  events and the solver" section of the documentation.
- User-defined functions with an `algorithm` section (`:=`, `if` and `for` statements over
  constant ranges). They are inlined symbolically into the equations.
- Array variables and parameters (`Real 'x'[3]`, `parameter Real 'A'[2, 2]`), scalarized at
  load into scalar unknowns named `x[1]`, `A[1,2]`, ... Sizes must be constants or
  parameters with constant values (`'k'['n'] = fill(1.0, 'n')`). Supported: `der` and the
  scalar built-ins elementwise, `+ - * /` with Modelica's array semantics (matrix·vector,
  scalar product), `.+ .- .* ./ .^`, subscripts, slices (`'x'[2:end]`, `'A'[1, :]`,
  `('A' * 'x')[1]`), `{...}`, `[a, b; c, d]`, `{e for i in r}`, `sum(e for i in r)`,
  `fill`, `zeros`, `ones`, `size`, `sum`, `product`, `min`/`max` of an array, `cat`,
  `transpose`, `identity`, `diagonal`, `cross`, `skew`, `outerProduct`, array start
  values (`start = fill(0.0, 3)`; a scalar attribute applies to every element), array
  equations, `for`-equations over constant or parameter ranges, and arrays as inputs and
  outputs of user functions (`output Real 'y'[size('u', 1)]`, element assignment).
- `sample(start, interval)` with constant or parameter arguments; parameters are evaluated
  with their values at load.
- Constants are inlined; parameters whose binding refers to other parameters become
  ModelingToolkit bindings, recomputed by `remake`; `annotation(Evaluate = true)` parameters
  are not tunable. Loading warns about `Evaluate = true` parameters and about parameters
  nothing references, since changing them does not change the model. See the
  "Constants and parameters" section of the documentation.

Not supported: records, arrays of records, Boolean- or enumeration-indexed dimensions, array
sizes that depend on a time-varying value, `when`-equations inside `for`-equations, algorithm sections
in models, `while` loops, multiple-output function calls, external functions, compound
continuous `when` conditions (`a and b`), `floor`/`integer`/`ceil`/`div`/`mod`/`rem`
with continuous arguments written directly in when-conditions, logical use of
when-assigned Booleans, and `edge`/`change`/`initial()`. These raise a
`BaseModelica.UnsupportedFeatureError` instead of producing a different model. Syntax
errors raise `BaseModelica.BaseModelicaParseError` (`:antlr`) or a
`ParserCombinator.ParserException` (`:julia`).

Discontinuity event generation for `floor`/`integer`/`ceil`/`div`/`mod`/`rem` is
unsupported. Calls hidden behind equation-defined intermediate variables are not
detected by the when-condition guard and may silently miss events.

## Installation

Assuming that you already have Julia correctly installed, it suffices to import
BaseModelica.jl in the standard way:

```julia
import Pkg;
Pkg.add("BaseModelica");
```

# Example

A Base Modelica model is in the file `ExampleFirstOrder.mo`. Inside of the file is a Base Modelica model specifying a simple first order linear differential equation:

```
package 'FirstOrder'
  model 'FirstOrder'
    parameter Real 'x0' = 0 "Initial value for 'x'";
    Real 'x' "Real variable called 'x'";
  initial equation
    'x' = 'x0' "Set initial value of 'x' to 'x0'";
  equation
    der('x') = 1.0 - 'x'; 
  end 'FirstOrder';
end 'FirstOrder';
```

To parse the model in the file to ModelingToolkit, use the `parse_basemodelica` function:

```julia
using BaseModelica

sys = parse_basemodelica("path/to/ExampleFirstOrder.bmo")
```

To automatically create an ODEProblem ready for simulation, use `create_odeproblem`:

```julia
using BaseModelica, DifferentialEquations

# Automatically sets tspan, reltol, and saveat (and dtmax for models without states)
# from the annotation if present
prob = create_odeproblem("path/to/ExampleFirstOrder.bmo")

# Solve and plot
sol = solve(prob)
```

If the model contains an experiment annotation like:
```modelica
annotation(experiment(StartTime = 0, StopTime = 2.0, Tolerance = 1e-06, Interval = 0.004))
```

The time span, relative tolerance, and save interval will be automatically configured from the annotation.
The settings are also stored on the system returned by `parse_basemodelica` and can be
read with `experiment_settings(sys)`.

## Unsimplified systems and Dyad

By default `parse_basemodelica` returns a system already compiled with `mtkcompile`.
Pass `simplify = false` to get the unsimplified `System`, for example to use the Dyad
pipeline (`DyadInterface.simplify_model` also adds the SynchToolkit pass when SynchToolkit
is loaded):

```julia
using BaseModelica, DyadInterface

model = parse_basemodelica("BouncingBall.bmo"; simplify = false)
settings = experiment_settings(model)
result = TransientAnalysis(; model, stop = settings.StopTime)

# or build the problem yourself:
prob = create_odeproblem("BouncingBall.bmo"; simplify = DyadInterface.simplify_model)
```
