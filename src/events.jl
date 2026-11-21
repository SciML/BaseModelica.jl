# Lowering of Modelica `when` equations (discrete assignments and `reinit`) to
# ModelingToolkit. BaseModelica evaluates the when-equations into a backend-independent,
# symbolic `DiscreteModel`; an `AbstractDiscreteBackend` then turns it into MTK equations,
# events and initial conditions.
#
# The built-in `MTKEventsBackend` (`:mtk`) uses ModelingToolkit symbolic events. Other
# backends live in other packages and register themselves under a name with
# `register_discrete_backend!` (for example SynchToolkit.jl registers `:synchtoolkit` from
# its `SynchToolkitBaseModelicaExt` extension).

"""
    UnsupportedFeatureError(msg)

Thrown when a BaseModelica model uses a construct that cannot be converted to
ModelingToolkit yet. Conversion stops instead of producing a model that silently
omits or changes behaviour.
"""
struct UnsupportedFeatureError <: Exception
    msg::String
end

function Base.showerror(io::IO, e::UnsupportedFeatureError)
    return print(io, "UnsupportedFeatureError: ", e.msg)
end

unsupported(msg) = throw(UnsupportedFeatureError(msg))

# ── Evaluation modes ──────────────────────────────────────────────────────────
# The meaning of `pre(x)` depends on where it appears:
#   :normal    ordinary equations; preserve `Pre(x)` for validation (only Boolean
#              self-reference is supported by lower_relation_booleans)
#   :initial   initial sections; discrete `pre(x)` is the initialization value of `x`
#   :condition when-conditions; `pre(x)` is a per-iteration value, resolved by the backend
#   :event     when-bodies; `pre(x)` is `Pre(x)`, resolved by the event backend
const EVAL_MODE = Ref(:normal)

function with_eval_mode(f, mode::Symbol)
    old = EVAL_MODE[]
    EVAL_MODE[] = mode
    try
        return f()
    finally
        EVAL_MODE[] = old
    end
end

is_discrete_variable(sym) = symbol_name(sym) in discrete_variable_names

# A continuous (non-parameter, time-dependent) variable such as `x(t)`.
function is_continuous_variable(sym)
    sym isa Num || return false
    inner = Symbolics.unwrap(sym)
    SymbolicUtils.iscall(inner) || return false
    ModelingToolkitBase.isparameter(inner) && return false
    return !is_discrete_variable(sym) && !(symbol_name(sym) in bool_comparison_names)
end

function symbol_name(sym)
    sym isa Num || return nothing
    inner = Symbolics.unwrap(sym)
    SymbolicUtils.iscall(inner) || SymbolicUtils.issym(inner) || return nothing
    return try
        SymbolicIndexingInterface.getname(inner)
    catch
        nothing
    end
end

# Preserve `pre(x)` until equation validation or the event backend resolves it.
function apply_pre(arg)
    if EVAL_MODE[] === :initial
        is_discrete_variable(arg) && return arg
        unsupported("pre() in initial sections is only supported for discrete variables")
    end
    name = relation_boolean_name(arg)
    isnothing(name) || return relation_boolean_pre(name)
    return ModelingToolkit.Pre(arg)
end

# ── When-clause IR ────────────────────────────────────────────────────────────

"""
One branch (`when` or `elsewhen`) of a `when` equation, as AST. Internal; backends receive
the evaluated [`WhenBlock`](@ref)s instead.

- `condition`: the condition AST.
- `sample`: `nothing`, or `(start, interval)` when the condition is `sample(start, interval)`.
- `assignments`: `(variable, rhs_ast)` for each `v = expr` in the body.
- `reinits`: `(state, rhs_ast)` for each `reinit(x, expr)` in the body.
"""
struct WhenClause
    chain::Int
    priority::Int
    condition::Any
    sample::Union{Nothing, Tuple{Float64, Float64}}
    assignments::Vector{Tuple{Any, Any}}
    reinits::Vector{Tuple{Any, Any}}
end

function function_call_name(call)
    func_name = call.func_name
    if func_name isa BaseModelicaIdentifier
        return func_name.name
    elseif func_name isa BaseModelicaComponentReference
        return join((r.name for r in func_name.ref_list), ".")
    end
    return ""
end

# The when-equation inside an equation list entry, or nothing.
# Julia parser: BaseModelicaAnyEquation(BaseModelicaSimpleEquation(lhs = BaseModelicaWhenEquation))
# ANTLR parser: bare BaseModelicaWhenEquation
function as_when_equation(eq)
    eq isa BaseModelicaWhenEquation && return eq
    if eq isa BaseModelicaAnyEquation && eq.equation isa BaseModelicaSimpleEquation &&
            eq.equation.lhs isa BaseModelicaWhenEquation
        return eq.equation.lhs
    end
    return nothing
end

body_list(body) = isa(body, AbstractArray) ? body : [body]

function inner_equation(eq)
    inner = eq isa BaseModelicaAnyEquation ? eq.equation : eq
    # The Julia parser wraps structured equations in a BaseModelicaSimpleEquation lhs
    if inner isa BaseModelicaSimpleEquation && isnothing(inner.rhs) &&
            inner.lhs isa Union{BaseModelicaIfEquation, BaseModelicaForEquation, BaseModelicaWhenEquation}
        return inner.lhs
    end
    return inner
end

# The variable `ref` refers to, or an array of variables for an array reference
function resolve_variable(ref::BaseModelicaComponentReference)
    name = reference_name(ref)
    haskey(variable_map, name) || haskey(array_components, name) ||
        unsupported("unknown variable `$name` in when-equation")
    return eval_AST(ref)
end

# `(target, rhs_ast)` for each scalar target of `target = rhs`
function scalar_targets(target, rhs)
    is_array(target) || return [(target, rhs)]
    return [(target[i], BaseModelicaArrayElement(rhs, Tuple(i))) for i in CartesianIndices(target)]
end

function when_clauses(when_eq::BaseModelicaWhenEquation, chain::Int)
    length(when_eq.whens) == length(when_eq.thens) ||
        error("Malformed when-equation: $(length(when_eq.whens)) conditions but $(length(when_eq.thens)) bodies")
    clauses = WhenClause[]
    for (priority, (condition, body)) in enumerate(zip(when_eq.whens, when_eq.thens))
        assignments = Tuple{Any, Any}[]
        reinits = Tuple{Any, Any}[]
        for eq in body_list(body)
            inner = inner_equation(eq)
            if inner isa BaseModelicaSimpleEquation && inner.lhs isa BaseModelicaComponentReference &&
                    !isnothing(inner.rhs)
                for (var, rhs) in scalar_targets(resolve_variable(inner.lhs), inner.rhs)
                    is_discrete_variable(var) ||
                        unsupported("assignment to `$(symbol_name(var))` in a when-equation; only discrete variables can be assigned")
                    push!(assignments, (var, rhs))
                end
            elseif inner isa BaseModelicaSimpleEquation && inner.lhs isa BaseModelicaFunctionCall &&
                    isnothing(inner.rhs)
                fname = function_call_name(inner.lhs)
                args = inner.lhs.args.args
                if fname == "reinit"
                    length(args) == 2 && args[1] isa BaseModelicaComponentReference ||
                        unsupported("reinit expects `reinit(state, expression)`")
                    for (state, rhs) in scalar_targets(resolve_variable(args[1]), args[2])
                        is_continuous_variable(state) ||
                            unsupported("reinit target `$(symbol_name(state))` is not a continuous state")
                        push!(reinits, (state, rhs))
                    end
                elseif fname == "assert"
                    continue
                else
                    unsupported("`$fname(...)` inside a when-equation is not supported")
                end
            elseif inner isa BaseModelicaSimpleEquation && inner.lhs isa AbstractVector
                unsupported("tuple assignments inside a when-equation are not supported")
            else
                unsupported("$(nameof(typeof(inner))) inside a when-equation is not supported")
            end
        end
        push!(clauses, WhenClause(chain, priority, condition, sample_args(condition), assignments, reinits))
    end
    return clauses
end

function sample_args(condition)
    condition isa BaseModelicaFunctionCall && function_call_name(condition) == "sample" ||
        return nothing
    args = condition.args.args
    length(args) == 2 || unsupported("sample() expects `sample(start, interval)`")
    return (sample_argument(args[1], "start"), sample_argument(args[2], "interval"))
end

# The value of an argument of `sample`: a number, or an expression of parameters, which is
# evaluated with their values at load. The sampling times are fixed then: changing such a
# parameter afterwards does not move them.
function sample_argument(ast, what)
    value = eval_AST(ast)
    number = parameter_value(value)
    isnothing(number) &&
        unsupported("sample() $what `$value` is neither a constant nor a parameter with a value")
    return Float64(number)
end

"""
    to_zero_crossing(cond)

Convert a symbolic Boolean condition into an expression that crosses zero upwards when the
condition becomes true.
"""
function to_zero_crossing(cond; original = cond)
    inner = Symbolics.unwrap(cond)
    if !SymbolicUtils.iscall(inner)
        return cond - 0.5
    end
    op = SymbolicUtils.operation(inner)
    args = SymbolicUtils.arguments(inner)
    if op === (>=) || op === (>)
        return args[1] - args[2]
    elseif op === (<=) || op === (<)
        return args[2] - args[1]
    elseif op === (==)
        return args[1] - args[2]
    elseif op in (&, |, !, ~, ifelse)
        unsupported("compound when-condition `$original`; only a single relation or Boolean variable is supported")
    else
        # Bare Boolean variable applied to time (e.g. u(t)): `when u` means rising edge
        return cond - 0.5
    end
end


# The reinitialization after the continuous events created by BaseModelica. ModelingToolkit
# compiles the continuous callbacks that share it (and the root finding) into one vector
# callback, which fires all callbacks whose roots coincide.
const EVENT_REINITIALIZATION = BrownFullBasicInit()

"""
    continuous_conditions(crossings, has_states::Bool)

The condition equations `c ~ 0` of a continuous callback with zero-crossings `crossings`.
ModelingToolkit evaluates a callback with a single condition into a buffer the size of the
state vector, which throws a `BoundsError` when the system has no states. For such a system
a condition that never crosses zero is added, which makes it a vector callback with a
buffer of its own.
"""
function continuous_conditions(crossings, has_states::Bool)
    eqs = Equation[c ~ 0 for c in crossings]
    has_states || length(eqs) != 1 || push!(eqs, Num(1.0) ~ 0)
    return eqs
end

# Extension point for containers of expressions (such as array literals).
differentiated_children(x) =
    SymbolicUtils.iscall(x) ? SymbolicUtils.arguments(x) : ()

# Variables appearing under a time derivative in `eqs`: the continuous states.
function differentiated_variables(eqs)
    found = Any[]
    seen = Set{Any}()
    function walk(x)
        x = Symbolics.unwrap(x)
        if SymbolicUtils.iscall(x) && SymbolicUtils.operation(x) isa Symbolics.Differential
            arg = only(SymbolicUtils.arguments(x))
            if !(arg in seen)
                push!(seen, arg)
                push!(found, arg)
            end
            return
        end
        return foreach(walk, differentiated_children(x))
    end
    for eq in eqs
        walk(eq.lhs)
        walk(eq.rhs)
    end
    return found
end


# ── Discrete backend interface ────────────────────────────────────────────────

"""
    WhenBlock

One evaluated `when`/`elsewhen` branch. Branches keep their identity even when their
triggers coincide: only the first triggering branch of an elsewhen chain executes
(Modelica 3.6 §8.3.5). Independent chains may execute together.

All expressions are symbolic, built from the symbols of [`DiscreteModel`](@ref):

- `chain::Int`: identity of the when-equation, in model order.
- `priority::Int`: branch order within that chain (1 for `when`, 2 for its first `elsewhen`).
- `condition`: the Boolean condition, e.g. `h(t) < 0`, with `pre(x)` marked as
  `ModelingToolkit.Pre(x)`, just as in the body.
  `nothing` for a `sample` trigger.
- `crossing`: an expression that crosses zero upwards when `condition` becomes true, e.g.
  `-h(t)` for `h < 0`. It contains plain `v` in place of `Pre(v)`, since they agree
  between events. The block fires on that rising edge only. `nothing` for a `sample`
  trigger or a condition that varies only at events.
- `sample`: `nothing`, or `(start, interval)` for `when sample(start, interval)`.
- `assignments`: `v => rhs` for each `v = rhs` in the body; `v` is a discrete variable.
- `reinits`: `x => rhs` for each `reinit(x, rhs)`; `x` is a continuous state, and no
  state appears twice in one block.

In `rhs`, `pre(x)` is marked as `ModelingToolkit.Pre(x)`. Backends must interpret it
as a value shared by all active bodies while solving the whole equation system,
including Boolean equations and when-conditions (Modelica 3.6 §8.5 and §3.7.5).
Propagating conditions through callback passes must not advance `pre(x)`; discrete
pre-values advance only between whole-system event iterations. States stay fixed within
each event-iteration step, with reinit values copied at its end.
Any other variable appears as its plain symbol and means its new value in the simultaneous
solution, including algebraic and discrete-time unknowns. Backends must reject body
reads they cannot solve with these semantics.
"""
struct WhenBlock
    chain::Int
    priority::Int
    condition::Any
    crossing::Any
    sample::Union{Nothing, Tuple{Float64, Float64}}
    assignments::Vector{Pair{Any, Any}}
    reinits::Vector{Pair{Any, Any}}
end

# Older backends constructed blocks without chain metadata. Treat those as
# independent branches; parsed blocks always have a positive chain identity.
WhenBlock(condition, crossing, sample, assignments, reinits) =
    WhenBlock(0, 1, condition, crossing, sample, assignments, reinits)

"""
    when_edge(current, previous; initialize = false)

The rising-edge predicate for a Boolean when-condition. Accepts Boolean values or
symbolic Boolean expressions. Backends must store the previous condition, seed it
from the initialized condition, and update it after each event iteration. Ordinary
when-clauses are inactive during initialization (Modelica 3.6 §8.6); sample ticks
are scheduled separately. A block with both `crossing === nothing` and
`sample === nothing` uses this predicate during event iteration, not root finding.
"""
when_edge(current, previous; initialize = false) = initialize ? false : current & !previous

"""
    DiscreteModel

What BaseModelica hands to [`lower_discrete`](@ref): the continuous part of the model plus
its discrete variables and `when` equations, all as ModelingToolkit symbolics.

- `equations::Vector{Equation}`: the continuous equations (`der(x) = ...`, algebraic
  equations, declaration equations). Discrete variables appear as their plain symbols;
  unsupported `pre(v)` reads in ordinary equations have already been rejected.
- `variables::Vector`: the continuous unknowns, e.g. `x(t)`.
- `states::Vector`: the subset of `variables` that appear under `der`.
- `discretes::Vector{Pair}`: `v => start` for each discrete variable, where `v` is the
  symbol returned by [`declare_discrete`](@ref) and `start` is the value of `pre(v)` at
  the first event: the `start` attribute, an initial equation `pre(v) = c` or `v = c`, an
  `initial algorithm` assignment, or the Modelica default 0 (`false` for Booleans).
- `when_blocks::Vector{WhenBlock}`: see [`WhenBlock`](@ref), in model order.

Initial equations, parameters and Boolean relation variables (`off = s < 0`) are handled by
BaseModelica and are not part of the `DiscreteModel`.
"""
struct DiscreteModel
    equations::Vector{Equation}
    variables::Vector{Any}
    states::Vector{Any}
    discretes::Vector{Pair{Any, Any}}
    when_blocks::Vector{WhenBlock}
end

"""
    LoweredDiscrete(; equations, continuous_events = [], discrete_events = [],
                    initial_conditions = [], initialization_eqs = [], parameters = [],
                    event_iteration = [])

What [`lower_discrete`](@ref) returns. BaseModelica builds the `System` from it:

- `equations`: every equation of the system, replacing `DiscreteModel.equations` (return
  those unchanged if the backend does not rewrite them).
- `continuous_events`, `discrete_events`: passed to `System`.
- `initial_conditions`: `variable => value` pairs, passed as `initial_conditions`.
- `initialization_eqs`: added to the model's own initialization equations.
- `parameters`: auxiliary parameters used by the backend, including event bookkeeping.
- `event_iteration`: callbacks checked after the relation-Boolean update in each event
  iteration. These callbacks must become inactive once their assignments are consistent;
  conditions must be symbolic Boolean expressions (or an empty preset-time vector
  to disable the callback). Preset-time and periodic clocks belong in `discrete_events`
  and are checked once; other condition types raise `ArgumentError`.
"""
Base.@kwdef struct LoweredDiscrete
    equations::Vector{Equation}
    continuous_events::Vector{Any} = Any[]
    discrete_events::Vector{Any} = Any[]
    initial_conditions::Vector{Pair} = Pair[]
    initialization_eqs::Vector{Equation} = Equation[]
    parameters::Vector{Num} = Num[]
    event_iteration::Vector{Any} = Any[]
end

# Preserve the original positional constructor as new optional backend data is added.
LoweredDiscrete(equations, continuous_events, discrete_events, initial_conditions, initialization_eqs) =
    LoweredDiscrete(; equations, continuous_events, discrete_events, initial_conditions, initialization_eqs)


"""
    AbstractDiscreteBackend

Supertype of the strategies that lower Base Modelica discrete variables and `when`
equations to ModelingToolkit. Select one with the `discrete_backend` keyword of
[`parse_basemodelica`](@ref) and [`create_odeproblem`](@ref), either by passing an instance
or by the name it was registered under with [`register_discrete_backend!`](@ref).

A backend `B <: AbstractDiscreteBackend` implements:

- [`lower_discrete`](@ref)`(::B, model::DiscreteModel) -> LoweredDiscrete` (required).
- [`declare_discrete`](@ref)`(::B, name::Symbol)` (optional): the symbol for a discrete
  variable. Defaults to `@discretes name(t)`.
- [`compile_system`](@ref)`(::B, sys)` (optional): the simplification used for
  `simplify = true`. Defaults to `mtkcompile(sys)`.

Backends that throw for constructs they cannot represent should throw
[`UnsupportedFeatureError`](@ref).

The built-in backend is [`MTKEventsBackend`](@ref), registered as `:mtk`.
"""
abstract type AbstractDiscreteBackend end

"""
    declare_discrete(backend::AbstractDiscreteBackend, name::Symbol)

Return the ModelingToolkit symbol that represents the discrete variable `name`, a function
of the independent variable `ModelingToolkit.t_nounits`. Called once per discrete variable
while the model is read, before [`lower_discrete`](@ref). If the returned symbol is not a
parameter, BaseModelica adds it to the unknowns of the system.

The default returns `@discretes name(t)`, a discrete parameter updated by event affects.
"""
declare_discrete(::AbstractDiscreteBackend, name::Symbol) = only(@discretes($name(t)))

"""
    lower_discrete(backend::AbstractDiscreteBackend, model::DiscreteModel) -> LoweredDiscrete

Lower the discrete part of `model` (see [`DiscreteModel`](@ref)): return the equations,
events and initial conditions of the system as a [`LoweredDiscrete`](@ref). Every backend
must implement this method.
"""
function lower_discrete end

"""
    compile_system(backend::AbstractDiscreteBackend, sys)

Simplify the assembled `System` when [`parse_basemodelica`](@ref) is called with
`simplify = true`. The default is `mtkcompile(sys)`; a backend that needs extra compiler
passes overrides it. With `simplify = false` or a function, this method is not called.
"""
compile_system(::AbstractDiscreteBackend, sys) = mtkcompile(sys)

"""
    MTKEventsBackend()

The built-in discrete backend, registered as `:mtk` (the default). Discrete variables are
`@discretes`. Continuous roots, Boolean transitions during event iteration, and periodic
sample clocks select rising edges together, respecting `elsewhen` priority. Assignments
and `reinit` become one symbolic affect solve. States read their event-iteration
values (`Pre`), and explicit `pre(v)` reads the previous iteration's value. Plain reads
of derivatives and non-state unknowns connected to discrete values or event-generating
relations/functions are conservatively rejected. The event-free `sign` function is also
guarded: without an algebraic event-step solve its value at a coincident root is numerically
ill-defined. Explicit continuous definitions stop that propagation. If any when-condition
reads `pre` and any sample clock exists in the model, every multi-branch when/elsewhen chain
with a non-sample branch is rejected, since restoration after snapshot advancement is
unsupported.
When-crossings and hysteresis Boolean crossings that read retained algebraic unknowns,
including observed aliases, are rejected during compilation. Level-semantic relation
Booleans without downstream when-conditions remain supported. Sample clocks include their
initial tick.
"""
struct MTKEventsBackend <: AbstractDiscreteBackend end

# Carried by relation-Boolean affects through MTK's callback substitutions.
struct AlgebraicCrossingCondition
    description::String
end

# Algebraic interpolants can locate a crossing on its old side, then report it
# again after initialization. Direction preservation at one instant cannot make
# those distinct root reports safe. Check after compilation, when retained
# algebraic unknowns and eliminated (observed) aliases are known.
compile_system(::MTKEventsBackend, sys) = check_algebraic_crossings(mtkcompile(sys))

"""
    check_algebraic_crossings(compiled)

Check a compiled BaseModelica system for when-crossings and hysteresis Boolean crossings
that depend on retained algebraic unknowns in the `:mtk` backend, throwing
[`UnsupportedFeatureError`](@ref) if one is found. Return the
system otherwise, resolving retained-array reinit targets for analytically integrated
constant states. This check runs automatically for `simplify = true` and
`simplify = f`. After `simplify = false`, call it on the result of your own compilation.
"""
function check_algebraic_crossings(compiled)
    compiled = array_reinit_callback_targets(compiled)
    callbacks = ModelingToolkitBase.continuous_events(compiled)
    isempty(callbacks) && return compiled
    mass = ModelingToolkitBase.calculate_massmatrix(compiled)
    isone(mass) && return compiled
    # A zero column has no differential contribution. In MTK's diagonal
    # mass layout these are also the zero rows of the retained unknowns.
    algebraic = Set(
        Symbolics.unwrap(var) for (i, var) in enumerate(ModelingToolkitBase.unknowns(compiled))
            if all(iszero, view(mass, :, i))
    )
    isempty(algebraic) && return compiled
    definitions = Dict(Symbolics.unwrap(eq.lhs) => eq.rhs for eq in ModelingToolkitBase.observed(compiled))
    for callback in callbacks
        affect = callback.affect
        affect isa ModelingToolkitBase.ImperativeAffect || continue
        description = if affect.f isa WhenSelection
            "when-condition `$(affect.f.blocks[affect.f.root].condition)`"
        elseif affect.ctx isa AlgebraicCrossingCondition
            affect.ctx.description
        else
            continue
        end
        for condition in callback.conditions
            pending = collect(Symbolics.get_variables(condition.lhs - condition.rhs))
            seen = Set{Any}()
            while !isempty(pending)
                var = Symbolics.unwrap(pop!(pending))
                var in seen && continue
                push!(seen, var)
                var in algebraic && unsupported(
                    "$description: crossing depends on retained algebraic unknown `$var` " *
                        "(zero mass-matrix row); algebraic crossings for this condition are not supported by the :mtk backend"
                )
                haskey(definitions, var) && append!(pending, Symbolics.get_variables(definitions[var]))
            end
        end
    end
    return compiled
end

# Remove a common numeric scale before comparing roots. A small multiplier of a
# relation must not make a distant root look simultaneous with the current event.
function crossing_coefficient(x)
    value = concrete_value(x)
    value isa Real && return iszero(value) ? 1.0 : abs(Float64(value))
    x = Symbolics.unwrap(x)
    SymbolicUtils.iscall(x) || return 1.0
    op = SymbolicUtils.operation(x)
    args = SymbolicUtils.arguments(x)
    op === (+) && return maximum(crossing_coefficient, args)
    if op === (*)
        return prod(args; init = 1.0) do arg
            c = concrete_value(arg)
            c isa Real ? abs(Float64(c)) : 1.0
        end
    end
    return 1.0
end

# Simplification may drop a small additive constant while reducing a ratio. Only
# group roots after verifying the proposed ratio against the original expressions.
function proportional_crossing(a, b)
    ratio = concrete_value(Symbolics.simplify(a / b))
    ratio isa Real && isfinite(ratio) && !iszero(ratio) || return nothing
    difference = concrete_value(Symbolics.expand(a - ratio * b))
    return difference isa Real && iszero(difference) ? ratio : nothing
end

# Event selection is separate from the symbolic affect solve. All roots and sample
# clocks at an instant select branches together, then MTK solves their assignments and
# reinits simultaneously. The bookkeeping is stored in parameters, so separate solves
# and remakes never share mutable callback state.
struct WhenSelection
    blocks::Vector{WhenBlock}
    root::Int
    direction::Int
    root_directions::Vector{Int}
    nsnapshots::Int
    initialize::Bool
end

function WhenSelection(blocks, root, direction, nsnapshots; initialize = false)
    signs = zeros(Int, length(blocks))
    if root != 0
        for (i, block) in enumerate(blocks)
            isnothing(block.crossing) && continue
            ratio = proportional_crossing(block.crossing, blocks[root].crossing)
            isnothing(ratio) && continue
            signs[i] = ratio > 0 ? 1 : -1
        end
        signs[root] = 1
    end
    return WhenSelection(blocks, root, direction, signs, nsnapshots, initialize)
end

const WHEN_ROOT_TOLERANCE = 64eps(Float64)

same_event_time(a, b) = isfinite(b) && abs(a - b) <= 32eps(Float64) * max(1, abs(a), abs(b))

sample_tick(time, start, interval) = time >= start &&
    abs((time - start) / interval - round((time - start) / interval)) <= 32eps(Float64) * max(1, abs((time - start) / interval))

function (select::WhenSelection)(modified, observed, ctx, integ)
    n = length(select.blocks)
    old = collect(values(modified))
    time = observed.time
    current = Bool[observed[Symbol(:condition, i)] for i in 1:n]
    # Modelica 3.6 §8.6: ordinary when-clauses are inactive at initialization.
    # Seed their edge history from the initialized solution, including relations
    # exactly on a root. Sample clocks may still select their initial tick below.
    previous = select.initialize ? copy(current) : old[1:n] .> 0.5
    # A root and a clock can report the same instant a few floating-point units
    # apart. Retain the selected branches and the event's pre-values across them.
    if !same_event_time(time, old[2n + 3])
        old[(n + 1):(2n)] .= 0.0
        old[2n + 3] = time
        old[2n + 4] = 0.0
        for i in 1:select.nsnapshots
            old[2n + 4 + i] = observed[Symbol(:snapshot, i)]
        end
    end
    selected_before = old[(n + 1):(2n)] .> 0.5
    active = copy(selected_before)
    tolerance_offset = 3n + 4 + select.nsnapshots
    # Every root pass must handle its own crossing (and proportional crossings):
    # later roots at this instant can lie outside the crossing-value tolerance.
    # On the first pass, also check for a sign change within the event-time window.
    # This selects steep/late coincident roots before lower-priority cascades can run.
    if select.root != 0
        first_root = !same_event_time(time, old[2n + 1])
        # Estimate changes along the solution tangent over the event-time window.
        # Extrapolate the tangent, not the interpolant. A step of 1024 windows
        # resolves the rate above roundoff while keeping nonlinear error local.
        window = 32eps(Float64) * max(1, abs(time))
        h = 1024window
        du = integ(time, Val{1})
        # Some solvers have a zero-length interpolant after a root. Identity-
        # and diagonal-mass ODEs still give differential tangents via their RHS.
        if !all(isfinite, du) && integ.sol.prob isa ODEProblem &&
                (isone(integ.f.mass_matrix) || integ.f.mass_matrix isa Diagonal)
            du = if SciMLBase.isinplace(integ.sol.prob)
                rate = similar(integ.u)
                integ.f(rate, integ.u, integ.p, time)
                rate
            else
                integ.f(integ.u, integ.p, time)
            end
            if integ.f.mass_matrix isa Diagonal
                # M * du = f determines only differential rows. Keep algebraic
                # tangents unknown so crossings reading them use the finite floor.
                du = map(du, integ.f.mass_matrix.diag) do rate, mass
                    iszero(mass) ? NaN : rate / mass
                end
            end
        end
        ahead = SymbolicIndexingInterface.ProblemState(;
            u = integ.u .+ h .* du,
            p = SymbolicIndexingInterface.parameter_values(integ), t = time + h
        )
        for (i, block) in enumerate(select.blocks)
            isnothing(block.crossing) && continue
            crossing = observed[Symbol(:crossing, i)]
            g = SymbolicIndexingInterface.getsym(integ, block.crossing)
            change = (g(ahead) - crossing) * (window / h)
            # Retain this scale for discrete iteration at this root. Its symbolic
            # mismatch guard must use the same tolerance or it would never settle.
            # Extrapolation may leave a crossing's domain (e.g. sqrt near zero).
            old[tolerance_offset + i] = isfinite(change) ? max(ROOT_TOLERANCE, abs(change)) : ROOT_TOLERANCE
            if select.root_directions[i] != 0
                current[i] = select.direction * select.root_directions[i] > 0
                # A rising root is an edge even if no accepted solver step observed
                # the false interval (e.g. consecutive bouncing-ball impacts).
                active[i] |= current[i]
            elseif first_root
                # A root still on its old side can be reported by the solver later.
                # Do not pre-fire it merely because its crossing value is tiny.
                pending = previous[i] ? crossing > 0 : crossing < 0
                if abs(crossing) <= WHEN_ROOT_TOLERANCE && !pending && !iszero(crossing)
                    current[i] = !previous[i]
                elseif isfinite(change)
                    value = crossing + change
                    if iszero(crossing)
                        # A later root pass must not invent a falling edge for an
                        # already handled rising root that now evaluates to zero.
                        current[i] = iszero(value) ? previous[i] : value > 0
                    elseif (crossing < 0 && value >= 0) || (crossing > 0 && value <= 0)
                        current[i] = crossing < 0
                    end
                end
            elseif !first_root && abs(crossing) <= old[tolerance_offset + i]
                current[i] = previous[i]
            end
        end
        first_root && (old[2n + 1] = time)
    elseif !select.initialize
        # At the root the strict relation itself can still have its old value.
        # Preserve the direction selected by the continuous callback.
        for (i, block) in enumerate(select.blocks)
            isnothing(block.crossing) && continue
            tolerance = same_event_time(time, old[2n + 1]) ? old[tolerance_offset + i] : ROOT_TOLERANCE
            abs(observed[Symbol(:crossing, i)]) <= tolerance &&
                (current[i] = previous[i])
        end
    end
    for (i, block) in enumerate(select.blocks)
        if isnothing(block.sample)
            active[i] |= when_edge(current[i], previous[i]; initialize = select.initialize)
        else
            start, interval = block.sample
            active[i] |= !same_event_time(time, old[2n + 2]) && sample_tick(time, start, interval)
        end
    end
    # The block list is in chain/priority order. Clear lower-priority branches
    # before any body runs, rather than depending on callback execution order.
    chosen = Set{Int}()
    for (i, block) in enumerate(select.blocks)
        active[i] || continue
        if block.chain != 0 && block.chain in chosen
            active[i] = false
        else
            push!(chosen, block.chain)
        end
    end
    # Match the ready flag below: a no-op selection after the body cleared
    # its execute slots must not arm those assignments for a later event.
    if active != selected_before
        for i in 1:n
            slot = 2n + 4 + select.nsnapshots + i
            if active[i]
                old[slot] = 1.0
            elseif selected_before[i] || old[slot] < -0.5
                # A late coincident trigger replaced this branch. Restore its targets
                # before applying the higher-priority body, including distinct reinits.
                old[slot] = -1.0
            end
        end
    end
    old[1:n] = Float64.(current)
    old[(n + 1):(2n)] = Float64.(active)
    active == selected_before || (old[2n + 4] = 1.0)
    any(b -> !isnothing(b.sample) && sample_tick(time, b.sample...), select.blocks) &&
        (old[2n + 2] = time)
    return NamedTuple{keys(modified)}(Tuple(old))
end

# A single scheduler puts every sample clock on its absolute Modelica time grid.
# Public add_tstop! avoids the span-relative phase of numeric periodic callbacks.
struct SampleSelection
    select::WhenSelection
end

function (clock::SampleSelection)(modified, observed, ctx, integ)
    selected = clock.select(modified, observed, ctx, integ)
    time = observed.time
    next_time = minimum(clock.select.blocks) do block
        isnothing(block.sample) && return Inf
        start, interval = block.sample
        ticks = (time - start) / interval
        k = max(0, floor(ticks + 32eps(Float64) * max(1, abs(ticks))) + 1)
        return start + k * interval
    end
    next_time <= integ.sol.prob.tspan[2] && add_tstop!(integ, next_time)
    return merge(selected, (; next_sample = next_time))
end

# Explicit pre reads in conditions require whole-system iterations, rather than
# just callback passes propagating one simultaneous solution.
function condition_pre_arguments!(found, expr)
    expr = Symbolics.unwrap(expr)
    SymbolicUtils.iscall(expr) || return found
    if SymbolicUtils.operation(expr) isa ModelingToolkit.Pre
        push!(found, Num(only(SymbolicUtils.arguments(expr))))
    else
        foreach(arg -> condition_pre_arguments!(found, arg), SymbolicUtils.arguments(expr))
    end
    return found
end

struct AdvanceWhenPre
    nblocks::Int
    indices::Vector{Int}
end

function (advance::AdvanceWhenPre)(modified, observed, ctx, integ)
    old = collect(values(modified))
    n = advance.nblocks
    old[(n + 1):(2n)] .= 0.0
    for i in advance.indices
        old[2n + 4 + i] = observed[Symbol(:snapshot, i)]
    end
    return NamedTuple{keys(modified)}(Tuple(old))
end

# The current affect freezes non-state unknowns along with states. Reject plain
# reads that could change in the simultaneous event-step solution (§8.6), including
# connection aliases and implicit/transitive algebraic dependencies. States are known
# values in that solve and therefore stop dependency propagation.
function when_body_unknowns!(found, expr, candidates; skip_pre = false)
    expr = Symbolics.unwrap(expr)
    for var in candidates
        if isequal(expr, Symbolics.unwrap(var))
            any(isequal(var), found) || push!(found, var)
            return found
        end
    end
    SymbolicUtils.iscall(expr) || return found
    skip_pre && SymbolicUtils.operation(expr) isa ModelingToolkit.Pre && return found
    for arg in SymbolicUtils.arguments(expr)
        when_body_unknowns!(found, arg, candidates; skip_pre)
    end
    return found
end

# Includes event-free sign conservatively: its value at a coincident root is
# numerically ill-defined, and the backend has no algebraic event-step solve.
function has_event_discontinuity(expr)
    expr = Symbolics.unwrap(expr)
    SymbolicUtils.iscall(expr) || return false
    SymbolicUtils.operation(expr) in (<, <=, >, >=, ==, !=, sign, floor, ceil, div, mod, rem) && return true
    return any(has_event_discontinuity, SymbolicUtils.arguments(expr))
end

# Derivatives are event-step unknowns, not state snapshots. MTK cannot freeze
# their direct reads reliably (including reinit RHSs), even without an alias.
function reject_body_derivatives(expr)
    expr = Symbolics.unwrap(expr)
    SymbolicUtils.iscall(expr) || return nothing
    op = SymbolicUtils.operation(expr)
    op isa ModelingToolkit.Pre && return nothing
    if op isa Symbolics.Differential
        name = symbol_name(Num(only(SymbolicUtils.arguments(expr))))
        derivative = isnothing(name) ? expr : "der('$name')"
        unsupported(
            "plain derivative read `$derivative` in a when-body requires an algebraic event-step solve (not yet supported by :mtk)"
        )
    end
    foreach(reject_body_derivatives, SymbolicUtils.arguments(expr))
    return nothing
end

# Snapshot advancement discards the event-start values needed to undo a late
# priority replacement, including cascades caused by the replaced branch.
function validate_when_structure(blocks)
    reads = Any[]
    for block in blocks
        isnothing(block.condition) || condition_pre_arguments!(reads, block.condition)
    end
    if !isempty(reads) && any(b -> !isnothing(b.sample), blocks)
        for block in blocks
            isnothing(block.sample) || continue
            count(b -> b.chain == block.chain, blocks) > 1 || continue
            unsupported(
                "a multi-branch when/elsewhen chain with a non-sample branch in a model with sample() anywhere and pre() in when-conditions; " *
                    "coincident priority restoration after snapshot advancement is not yet supported by :mtk"
            )
        end
    end
    owners = Dict{Any, Int}()
    for block in blocks, (state, _) in block.reinits
        if haskey(owners, state) && owners[state] != block.chain
            unsupported("reinit of `$(symbol_name(state))` in multiple when-equations; use branches of the same when/elsewhen chain")
        end
        owners[state] = block.chain
    end
    return nothing
end

function when_body_dependencies(model::DiscreteModel)
    algebraics = filter(v -> !any(isequal(v), model.states), model.variables)
    discrete_quantities = vcat(first.(model.discretes), collect(values(relation_boolean_syms)))
    quantities = unique(vcat(algebraics, discrete_quantities))
    # Derivatives are unknowns too: e.g. der(x) = c; y = der(x). Keep them as
    # graph nodes without propagating through the known state x itself.
    for eq in model.equations, side in (eq.lhs, eq.rhs), var in Symbolics.get_variables(side)
        ModelingToolkitBase.isparameter(var) && continue
        any(v -> isequal(var, Symbolics.unwrap(v)), model.states) && continue
        union!(quantities, [Num(var)])
    end
    integer_unknowns = filter(algebraics) do v
        symbol_name(v) in integer_variable_names ||
            SymbolicUtils.symtype(Symbolics.unwrap(v)) <: Integer
    end
    # Peel off explicitly determined continuous signals. Sharing a downstream
    # equation with a discrete setpoint does not make y = 2*x event-dependent.
    # Keep relations/discontinuous functions guarded even on states: a left root
    # value need not equal their event value. Leave implicit systems conservative.
    fixed = Any[]
    while true
        before = length(fixed)
        for eq in model.equations, (target, rhs) in ((eq.lhs, eq.rhs), (eq.rhs, eq.lhs))
            any(isequal(target), algebraics) || continue
            any(isequal(target), integer_unknowns) && continue
            has_event_discontinuity(rhs) && continue
            reads = when_body_unknowns!(Any[], rhs, quantities)
            all(v -> any(isequal(v), fixed), reads) && union!(fixed, [target])
        end
        length(fixed) == before && break
    end
    filter!(v -> !any(isequal(v), fixed), quantities)
    equation_reads = [
        when_body_unknowns!(when_body_unknowns!(Any[], eq.lhs, quantities), eq.rhs, quantities)
            for eq in model.equations
    ]
    return (; algebraics, discrete_quantities, integer_unknowns, quantities, equation_reads)
end

function validate_when_body_reads(model::DiscreteModel)
    (; algebraics, discrete_quantities, integer_unknowns, equation_reads) = when_body_dependencies(model)
    affected = unique(vcat(discrete_quantities, integer_unknowns))
    # Relations can appear directly in an equation's if-expression rather than
    # through an equation-defined Boolean parameter.
    for (eq, reads) in zip(model.equations, equation_reads)
        (has_event_discontinuity(eq.lhs) || has_event_discontinuity(eq.rhs)) && union!(affected, reads)
    end
    while true
        before = length(affected)
        for reads in equation_reads
            any(v -> any(isequal(v), affected), reads) && union!(affected, reads)
        end
        length(affected) == before && break
    end
    for block in model.when_blocks, (_, rhs) in Iterators.flatten((block.assignments, block.reinits))
        reject_body_derivatives(rhs)
        for var in when_body_unknowns!(Any[], rhs, algebraics; skip_pre = true)
            any(isequal(var), affected) || continue
            unsupported(
                "plain read of non-state unknown `$(symbol_name(var))` in a when-body; " *
                    "its equations may change with discrete values or contain event-generating " *
                    "relations/functions, requiring a simultaneous " *
                    "algebraic event-step solve before reinit values are copied (not yet supported by :mtk)"
            )
        end
    end
    return nothing
end

# Relation callbacks run between symbolic body solves. A Boolean that depends on
# an assigned discrete value cannot be held while that same solve reads its new
# value. Follow definitions and algebraic aliases; pre(b) reads remain snapshots.
function validate_relation_boolean_body_reads(model::DiscreteModel, definitions)
    booleans = collect(values(relation_boolean_syms))
    body_reads = Any[]
    for block in model.when_blocks, (_, rhs) in Iterators.flatten((block.assignments, block.reinits))
        when_body_unknowns!(body_reads, rhs, booleans; skip_pre = true)
    end
    isempty(body_reads) && return nothing
    (; quantities, equation_reads) = when_body_dependencies(model)
    definition_reads = [
        relation_boolean_syms[name] => when_body_unknowns!(Any[], rhs, quantities)
            for (name, rhs) in definitions
    ]
    affected = Any[first.(model.discretes)...]
    while true
        before = length(affected)
        for reads in equation_reads
            any(v -> any(isequal(v), affected), reads) || continue
            # Boolean definitions are directed dependencies. Sharing a downstream
            # equation with a discrete setpoint must not taint a fixed Boolean.
            union!(affected, filter(v -> !any(isequal(v), booleans), reads))
        end
        for (sym, reads) in definition_reads
            any(v -> any(isequal(v), affected), reads) && union!(affected, [sym])
        end
        length(affected) == before && break
    end
    for sym in body_reads
        any(isequal(sym), affected) || continue
        unsupported(
            "plain read of relation Boolean `$(symbol_name(sym))` in a when-body; " *
                "its definition may change with discrete values, requiring a simultaneous " *
                "Boolean event-step solve (not yet supported by :mtk)"
        )
    end
    return nothing
end

function lower_discrete(::MTKEventsBackend, model::DiscreteModel)
    lowered = LoweredDiscrete(;
        equations = model.equations,
        initial_conditions = Pair[sym => start for (sym, start) in model.discretes]
    )
    blocks = model.when_blocks
    isempty(blocks) && return lowered
    validate_when_structure(blocks)
    validate_when_body_reads(model)
    n = length(blocks)
    previous = [only(@discretes($(gensym(:when_previous))(t))) for _ in blocks]
    active = [only(@discretes($(gensym(:when_active))(t))) for _ in blocks]
    root_time = only(@discretes($(gensym(:when_root_time))(t)))
    sample_time = only(@discretes($(gensym(:when_sample_time))(t)))
    event_time = only(@discretes($(gensym(:when_event_time))(t)))
    ready = only(@discretes($(gensym(:when_ready))(t)))
    next_sample = only(@discretes($(gensym(:when_next_sample))(t)))
    snapshot_sources = unique(vcat(model.variables, first.(model.discretes), collect(values(relation_boolean_syms))))
    snapshots = [only(@discretes($(gensym(:when_pre))(t))) for _ in snapshot_sources]
    execute = [only(@discretes($(gensym(:when_execute))(t))) for _ in blocks]
    root_tolerances = [only(@discretes($(gensym(:when_root_tolerance))(t))) for _ in blocks]
    bookkeeping = vcat(previous, active, [root_time, sample_time, event_time, ready], snapshots, execute, root_tolerances)
    append!(lowered.parameters, vcat(bookkeeping, [next_sample]))
    append!(
        lowered.initial_conditions,
        [p => 0.0 for p in vcat(previous, active, snapshots, execute, root_tolerances, [ready])]
    )
    append!(lowered.initial_conditions, [root_time => -Inf, sample_time => -Inf, event_time => -Inf, next_sample => Inf])
    modified = NamedTuple{(Tuple(Symbol(:m, i) for i in eachindex(bookkeeping))..., :next_sample)}(
        Tuple(vcat(bookkeeping, [next_sample]))
    )
    condition_reads = Any[]
    for block in blocks
        isnothing(block.condition) || condition_pre_arguments!(condition_reads, block.condition)
    end
    at_event = abs(t - event_time) <= 32eps(Float64) * max(1, abs(t))
    condition_pre = Dict(
        ModelingToolkit.Pre(var) => ifelse(at_event, snapshot, relation_boolean_left_limit(var))
            for (var, snapshot) in zip(snapshot_sources, snapshots)
    )
    condition_value(block) = isnothing(block.condition) ? Num(false) :
        Symbolics.substitute(block.condition, condition_pre)
    obs_names = [:time]
    obs_values = Any[t]
    for (i, block) in enumerate(blocks)
        push!(obs_names, Symbol(:condition, i))
        push!(obs_values, condition_value(block))
        isnothing(block.crossing) && continue
        push!(obs_names, Symbol(:crossing, i))
        push!(obs_values, block.crossing)
    end
    for (i, var) in enumerate(snapshot_sources)
        push!(obs_names, Symbol(:snapshot, i))
        push!(obs_values, relation_boolean_left_limit(var))
    end
    observed = NamedTuple{Tuple(obs_names)}(Tuple(obs_values))
    selection(root = 0, direction = 0; initialize = false) = ModelingToolkitBase.ImperativeAffect(
        WhenSelection(blocks, root, direction, length(snapshots); initialize); modified, observed
    )
    roots = Any[]
    for (i, block) in enumerate(blocks)
        if !isnothing(block.crossing)
            any(roots) do c
                !isnothing(proportional_crossing(block.crossing, c))
            end && continue
            push!(roots, block.crossing)
            push!(
                lowered.continuous_events, ModelingToolkitBase.SymbolicContinuousCallback(
                    continuous_conditions([block.crossing], !isempty(model.states)), selection(i, 1);
                    affect_neg = selection(i, -1), reinitializealg = EVENT_REINITIALIZATION
                )
            )
        end
    end
    # Check discrete Boolean transitions after the relation-Boolean iteration, rather
    # than trying to find a continuous root in a piecewise constant parameter.
    mismatch = Num(false)
    at_root = abs(t - root_time) <= 32eps(Float64) * max(1, abs(t))
    for (i, block) in enumerate(blocks)
        isnothing(block.condition) && continue
        changed = Num(condition_value(block)) != (previous[i] > 0.5)
        if !isnothing(block.crossing)
            tolerance = ifelse(at_root, root_tolerances[i], ROOT_TOLERANCE)
            changed &= Num(abs(block.crossing) > tolerance)
        end
        mismatch |= changed
    end
    # A condition such as `when pre(b)` may stay false throughout the first
    # iteration. Still enter selection at the Boolean event so its pre can advance
    # at this instant, rather than on the next accepted integration step.
    for var in condition_reads
        mismatch |= !at_event & (var != relation_boolean_left_limit(var))
    end
    push!(
        lowered.event_iteration, ModelingToolkitBase.SymbolicDiscreteCallback(
            concrete_value(mismatch) === false ? Float64[] : Symbolics.unwrap(mismatch),
            selection();
            initialize = any(b -> !isnothing(b.sample), blocks) ? nothing : selection(; initialize = true),
            reinitializealg = EVENT_REINITIALIZATION
        )
    )
    samples = [b.sample for b in blocks if !isnothing(b.sample)]
    for (start, interval) in samples
        interval > 0 || unsupported("sample() interval must be positive")
        start == 0 ||
            unsupported("sample(start, interval) with start ≠ 0 is not supported by the :mtk discrete backend")
    end
    if !isempty(samples)
        clock = ModelingToolkitBase.ImperativeAffect(
            SampleSelection(WhenSelection(blocks, 0, 0, length(snapshots))); modified, observed
        )
        initial_clock = ModelingToolkitBase.ImperativeAffect(
            SampleSelection(WhenSelection(blocks, 0, 0, length(snapshots); initialize = true)); modified, observed
        )
        push!(
            lowered.discrete_events, ModelingToolkitBase.SymbolicDiscreteCallback(
                Symbolics.unwrap(t >= next_sample), clock; initialize = initial_clock,
                reinitializealg = EVENT_REINITIALIZATION
            )
        )
    end
    # Re-solve all selected bodies together as conditions propagate. They share
    # the iteration's pre-values, while plain discrete variables take their new values
    # in the simultaneous solution, including bodies selected in a later pass.
    continuous_pre = Dict{Any, Any}()
    for var in model.variables
        continuous_pre[var] = ModelingToolkit.Pre(var)
        continuous_pre[ModelingToolkit.Pre(var)] = ModelingToolkit.Pre(var)
    end
    pre_values = Dict(
        ModelingToolkit.Pre(var) => ModelingToolkit.Pre(snapshot)
            for (var, snapshot) in zip(snapshot_sources, snapshots)
    )
    function body_value(rhs)
        rhs = Symbolics.substitute(rhs, continuous_pre; fold = Val(false))
        return Symbolics.substitute(rhs, pre_values)
    end
    assignments = Dict{Any, Any}()
    reinits = Dict{Any, Any}()
    for (i, block) in reverse(collect(enumerate(blocks)))
        for (target, rhs) in block.assignments
            assignments[target] = ifelse(
                ModelingToolkit.Pre(execute[i]) > 0.5, body_value(rhs),
                ifelse(
                    ModelingToolkit.Pre(execute[i]) < -0.5, body_value(ModelingToolkit.Pre(target)),
                    get(assignments, target, ModelingToolkit.Pre(target))
                )
            )
        end
        for (target, rhs) in block.reinits
            reinits[target] = ifelse(
                ModelingToolkit.Pre(execute[i]) > 0.5, body_value(rhs),
                ifelse(
                    ModelingToolkit.Pre(execute[i]) < -0.5, body_value(ModelingToolkit.Pre(target)),
                    get(reinits, target, ModelingToolkit.Pre(target))
                )
            )
        end
    end
    combined = WhenBlock(
        0, 0, nothing, nothing, nothing,
        Pair{Any, Any}[k => v for (k, v) in assignments],
        Pair{Any, Any}[k => v for (k, v) in reinits]
    )
    affects, discretes = mtk_affect(combined, model)
    push!(affects, ready ~ 0.0)
    append!(affects, [flag ~ 0.0 for flag in execute])
    append!(discretes, [ready; execute])
    pending = ready > 0.5
    affect = array_mtk_affect(affects, discretes)
    push!(
        lowered.event_iteration, ModelingToolkitBase.SymbolicDiscreteCallback(
            Symbolics.unwrap(pending), affect; discrete_parameters = discretes,
            initialize = affect, reinitializealg = EVENT_REINITIALIZATION
        )
    )
    if !isempty(condition_reads)
        # Advance the whole solution between event-iteration steps, including
        # states/unknowns read only by bodies. In particular, a step-2 body must
        # see the state copied by a step-1 reinit (§8.3.6), independently of
        # whether an unrelated condition also reads pre(state).
        indices = collect(eachindex(snapshot_sources))
        changed_pre = Num(false)
        for (var, snapshot) in zip(snapshot_sources, snapshots)
            any(isequal(var), condition_reads) || continue
            changed_pre |= var != snapshot
        end
        advance_observed = NamedTuple{Tuple(Symbol(:snapshot, i) for i in indices)}(
            Tuple(snapshot_sources[indices])
        )
        advance = ModelingToolkitBase.ImperativeAffect(
            AdvanceWhenPre(n, indices); modified, observed = advance_observed
        )
        # event_iteration_callbacks additionally gates this on all other callbacks
        # being inactive, including the equation-defined Boolean updates.
        push!(
            lowered.event_iteration, ModelingToolkitBase.SymbolicDiscreteCallback(
                Symbolics.unwrap(at_event & changed_pre), advance;
                reinitializealg = EVENT_REINITIALIZATION
            )
        )
    end
    return lowered
end

"""
    mtk_affect(block, model)

Affect equations for `block`. Returns `(affects, discrete_parameters)`.

State values are fixed within an event-iteration step; `reinit` values are copied at
its end. This affect freezes all non-discrete unknown reads as well, which is valid
only when their equations cannot change with the step's discrete-time solution.
`validate_when_body_reads` rejects the other cases until algebraic solves and reinit
copies are separated. Every state not reinitialized is held with `x ~ Pre(x)` so MTK
does not treat it as a free unknown of the affect system.
"""
function mtk_affect(block::WhenBlock, model::DiscreteModel)
    pre_values = Dict{Any, Any}()
    for x in model.variables
        pre_values[x] = ModelingToolkit.Pre(x)
        pre_values[ModelingToolkit.Pre(x)] = ModelingToolkit.Pre(x)
    end
    event_value(rhs) = Symbolics.substitute(rhs, pre_values; fold = Val(false))
    affects = Equation[var ~ event_value(rhs) for (var, rhs) in block.assignments]
    discretes = unique(first.(block.assignments))
    for (state, rhs) in block.reinits
        push!(affects, state ~ event_value(rhs))
    end
    for state in model.states
        any(r -> isequal(first(r), state), block.reinits) ||
            push!(affects, state ~ ModelingToolkit.Pre(state))
    end
    # Relation callbacks update these before each when-body solve. Hold their
    # current iteration values explicitly: otherwise MTK's discrete affect system
    # shifts plain Boolean reads (including those in algebraic equations) without
    # supplying the corresponding pre-value to the generated affect.
    for sym in values(relation_boolean_syms)
        push!(affects, sym ~ ModelingToolkit.Pre(sym))
        push!(discretes, sym)
    end
    return affects, discretes
end

"""
    when_blocks(clauses)

Evaluate the AST-level `WhenClause`s into [`WhenBlock`](@ref)s, preserving chain identity
and branch priority even when triggers coincide.
"""
function when_blocks(clauses)
    blocks = WhenBlock[]
    for clause in clauses
        condition = crossing = nothing
        if isnothing(clause.sample)
            condition = with_eval_mode(() -> eval_AST(clause.condition), :condition)
            # Relation-defined Booleans transition during event iteration. Their
            # conditions are discrete; only direct relations have continuous roots.
            # Between events pre(v) = v; classify that plain expression too, since
            # Pre(continuous v) itself looks like a parameter to Symbolics.
            plain = Symbolics.substitute(
                condition, Dict(
                    ModelingToolkit.Pre(v) => v for v in condition_pre_arguments!(Any[], condition)
                )
            )
            if varies_continuously(plain)
                crossing = Num(to_zero_crossing(plain; original = condition))
                crossing /= crossing_coefficient(crossing)
            end
        end
        assignments, reinits = with_eval_mode(:event) do
            Pair{Any, Any}[var => eval_AST(rhs) for (var, rhs) in clause.assignments],
                Pair{Any, Any}[state => eval_AST(rhs) for (state, rhs) in clause.reinits]
        end
        states = first.(reinits)
        for (i, state) in enumerate(states)
            any(isequal(state), states[1:(i - 1)]) &&
                unsupported("`$(symbol_name(state))` is reinitialized twice in the same event")
        end
        push!(
            blocks, WhenBlock(
                clause.chain, clause.priority, condition, crossing,
                clause.sample, assignments, reinits
            )
        )
    end
    return blocks
end

# MTK compiles each symbolic callback once. Reuse the compiled SciML callbacks
# during event iteration; duplicating symbolic callbacks recompiles the entire
# simultaneous affect solve for every round. Only the adjacent iteration callbacks
# belong to this loop (never user callbacks or sample clocks).
struct EventIteration
    count::Int
    id::Symbol
end

EventIteration(count) = EventIteration(count, gensym(:event_iteration))

function (iteration::EventIteration)(modified, observed, ctx, integ)
    callbacks = integ.opts.callback.discrete_callbacks
    index = findfirst(callbacks) do cb
        # ImperativeAffect's compiled callable retains the supplied user_affect.
        # Inspect only this marker, not MTK's generated getters/setters or indices.
        return hasproperty(cb.affect!, :user_affect) && cb.affect!.user_affect === iteration
    end
    isnothing(index) && error("event iteration callback is missing from the CallbackSet")
    first_index = index - iteration.count
    changed_any = false
    for _ in 1:1000
        changed = false
        for i in first_index:(index - 1)
            cb = callbacks[i]
            cb.condition(integ.u, integ.t, integ) || continue
            cb.affect!(integ)
            SciMLBase.reeval_internals_due_to_modification!(
                integ, false; callback_initializealg = cb.initializealg
            )
            SciMLBase.save_discretes!(integ, cb)
            changed = changed_any = true
        end
        if !changed
            @static if isdefined(SciMLBase, :derivative_discontinuity!)
                SciMLBase.derivative_discontinuity!(integ, changed_any)
            else
                SciMLBase.u_modified!(integ, changed_any)
            end
            return nothing
        end
    end
    error("Modelica event iteration did not converge at t = $(integ.t)")
end

function event_iteration_callbacks(booleans, lowered)
    callbacks = vcat(booleans.discrete_events, lowered.event_iteration)
    isempty(lowered.event_iteration) && return callbacks
    # Only iterate when a Boolean update, branch selection, or body solve is
    # pending. An always-true condition forces SciML to save at every step,
    # even when the affect reports that nothing changed.
    pending = Num(false)
    advances = Int[]
    for (i, cb) in enumerate(callbacks)
        if cb.affect isa ModelingToolkitBase.ImperativeAffect && cb.affect.f isa AdvanceWhenPre
            push!(advances, i)
            continue
        end
        condition = cb.conditions
        # Empty preset-time conditions represent disabled callbacks.
        condition isa AbstractVector && isempty(condition) && continue
        if !(condition isa Union{Bool, Num, SymbolicUtils.BasicSymbolic}) ||
                SymbolicUtils.symtype(Symbolics.unwrap(condition)) !== Bool
            throw(
                ArgumentError(
                    "event_iteration callbacks require symbolic Boolean conditions " *
                        "(or an empty preset-time vector); put preset-time and periodic callbacks in discrete_events"
                )
            )
        end
        pending |= Num(condition)
    end
    for i in advances
        cb = callbacks[i]
        condition = Num(cb.conditions) & !pending
        callbacks[i] = ModelingToolkitBase.SymbolicDiscreteCallback(
            Symbolics.unwrap(condition), cb.affect; reinitializealg = cb.reinitializealg
        )
        pending |= condition
    end
    loop = ModelingToolkitBase.ImperativeAffect(EventIteration(length(callbacks)))
    push!(
        callbacks, ModelingToolkitBase.SymbolicDiscreteCallback(
            Symbolics.unwrap(pending), loop; initialize = loop,
            reinitializealg = EVENT_REINITIALIZATION
        )
    )
    return callbacks
end

# ── Backend registry ──────────────────────────────────────────────────────────

const DISCRETE_BACKENDS = Dict{Symbol, AbstractDiscreteBackend}(:mtk => MTKEventsBackend())
# Names of the registered backends that `discrete_backend = :auto` may select.
const AUTO_BACKENDS = Set{Symbol}()
const DISCRETE_BACKENDS_LOCK = ReentrantLock()
# Packages known to provide a backend, used only for the error message when a backend is
# requested but not registered.
const BACKEND_PROVIDERS = Dict(:synchtoolkit => "SynchToolkit")

"""
    register_discrete_backend!(name::Symbol, backend::AbstractDiscreteBackend; auto = false)

Make `backend` available as `discrete_backend = name`. Packages that provide a backend call
this from `__init__` (of the package or of its BaseModelica extension), not at the top
level, so that the registration also happens when the package is loaded from a
precompiled image. Registering a name again replaces the previous backend.

With `auto = true` the backend is also chosen by `discrete_backend = :auto` (the default)
while it is registered. If several registered backends set `auto = true`, `:auto` throws
and the backend must be chosen by name. `:mtk` and `:auto` are reserved.

Returns `backend`.

## Examples

```julia
struct MyBackend <: BaseModelica.AbstractDiscreteBackend end
BaseModelica.lower_discrete(::MyBackend, model) =
    BaseModelica.lower_discrete(BaseModelica.MTKEventsBackend(), model)

function __init__()
    BaseModelica.register_discrete_backend!(:mine, MyBackend())
end
```
"""
function register_discrete_backend!(
        name::Symbol, backend::AbstractDiscreteBackend; auto::Bool = false
    )
    name in (:mtk, :auto) &&
        throw(ArgumentError("discrete backend name :$name is reserved"))
    @lock DISCRETE_BACKENDS_LOCK begin
        DISCRETE_BACKENDS[name] = backend
        auto ? push!(AUTO_BACKENDS, name) : delete!(AUTO_BACKENDS, name)
    end
    return backend
end

"""
    unregister_discrete_backend!(name::Symbol)

Remove the backend registered under `name`, if any. `:mtk` cannot be removed.
"""
function unregister_discrete_backend!(name::Symbol)
    name === :mtk && throw(ArgumentError("the :mtk discrete backend cannot be unregistered"))
    @lock DISCRETE_BACKENDS_LOCK begin
        delete!(DISCRETE_BACKENDS, name)
        delete!(AUTO_BACKENDS, name)
    end
    return nothing
end

"""
    select_backend(discrete_backend)

Resolve the `discrete_backend` keyword: an `AbstractDiscreteBackend` is used as is, a name
is looked up among the registered backends. `:auto` selects the one registered backend
with `auto = true`, or `:mtk` if there is none.
"""
function select_backend(backend)
    backend isa AbstractDiscreteBackend && return backend
    backend isa Symbol ||
        throw(ArgumentError("discrete_backend must be a Symbol or an AbstractDiscreteBackend, got $(repr(backend))"))
    return @lock DISCRETE_BACKENDS_LOCK begin
        if backend === :auto
            candidates = sort!(collect(AUTO_BACKENDS))
            length(candidates) > 1 && throw(
                ArgumentError(
                    "discrete_backend = :auto is ambiguous: the backends $(join(repr.(candidates), ", ")) all " *
                        "asked to be selected automatically. Pass one of them explicitly."
                )
            )
            return DISCRETE_BACKENDS[isempty(candidates) ? :mtk : only(candidates)]
        end
        haskey(DISCRETE_BACKENDS, backend) && return DISCRETE_BACKENDS[backend]
        registered = join(repr.(sort!(collect(keys(DISCRETE_BACKENDS)))), ", ")
        provider = get(BACKEND_PROVIDERS, backend, nothing)
        hint = isnothing(provider) ?
            "Backends are provided by packages; load the package that provides it." :
            "It is provided by $provider.jl: load $provider to enable it (`using $provider`)."
        throw(
            ArgumentError(
                "No discrete backend is registered as discrete_backend = $(repr(backend)). $hint " *
                    "Registered backends: $registered (or :auto)."
            )
        )
    end
end
