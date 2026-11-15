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
#   :normal    continuous equations; `pre(v)` of a discrete variable is `v` (they differ
#              only at event instants), otherwise `Pre(x)`
#   :condition when-conditions; `pre(x)` is the current value of `x`
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

# `pre(x)` evaluated in the current mode; `arg` is the plain symbol for `x`.
function apply_pre(arg)
    mode = EVAL_MODE[]
    mode === :condition && return arg
    name = relation_boolean_name(arg)
    isnothing(name) || return relation_boolean_pre(name)
    mode === :normal && is_discrete_variable(arg) && return arg
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
function to_zero_crossing(cond)
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
        unsupported("compound when-condition `$cond`; only a single relation or Boolean variable is supported")
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

# Variables appearing under a time derivative in `eqs`: the continuous states.
function differentiated_variables(eqs)
    found = []
    function walk(x)
        x = Symbolics.unwrap(x)
        SymbolicUtils.iscall(x) || return
        if SymbolicUtils.operation(x) isa Symbolics.Differential
            arg = only(SymbolicUtils.arguments(x))
            any(isequal(arg), found) || push!(found, arg)
            return
        end
        return foreach(walk, SymbolicUtils.arguments(x))
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
- `condition`: the Boolean condition, e.g. `h(t) < 0`, with `pre(x)` evaluated as `x`.
  `nothing` for a `sample` trigger.
- `crossing`: an expression that crosses zero upwards when `condition` becomes true, e.g.
  `-h(t)` for `h < 0`. The block fires on that rising edge only. `nothing` for a `sample`
  trigger or a condition that varies only at events.
- `sample`: `nothing`, or `(start, interval)` for `when sample(start, interval)`.
- `assignments`: `v => rhs` for each `v = rhs` in the body; `v` is a discrete variable.
- `reinits`: `x => rhs` for each `reinit(x, rhs)`; `x` is a continuous state, and no
  state appears twice in one block.

In `rhs`, `pre(x)` is marked as `ModelingToolkit.Pre(x)`. Backends must interpret it
as a value shared by all active bodies while solving the whole equation system,
including Boolean equations and when-conditions (Modelica 3.6 §8.5 and §3.7.5).
Propagating conditions through callback passes must not advance `pre(x)`; discrete
pre-values advance only between whole-system event iterations. For continuous `x`,
use its pre-event value. Any other variable appears as its plain symbol: a plain
discrete `v` means its new value at this event, a plain continuous `x` means its value at
the event instant (which equals its pre-event value).
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
  equations, declaration equations). Discrete variables appear as their plain symbols, and
  `pre(v)` of a discrete `v` is already rewritten to `v`.
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
and `reinit` become one symbolic affect solve in which continuous variables read their
pre-event value (`Pre`). Sample clocks include their initial tick.
"""
struct MTKEventsBackend <: AbstractDiscreteBackend end

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
    # Root callbacks at the same instant all see the same transition. The first one
    # handles every coincident crossing, including scaled conditions.
    if select.root != 0 && !same_event_time(time, old[2n + 1])
        for (i, block) in enumerate(select.blocks)
            isnothing(block.crossing) && continue
            crossing = observed[Symbol(:crossing, i)]
            if select.root_directions[i] != 0
                current[i] = select.direction * select.root_directions[i] > 0
                # A rising root is an edge even if no accepted solver step observed
                # the false interval (e.g. consecutive bouncing-ball impacts).
                active[i] |= current[i]
            elseif abs(crossing) <= WHEN_ROOT_TOLERANCE
                current[i] = !previous[i]
            end
        end
        old[2n + 1] = time
    elseif !select.initialize
        # At the root the strict relation itself can still have its old value.
        # Preserve the direction selected by the continuous callback.
        for (i, block) in enumerate(select.blocks)
            isnothing(block.crossing) && continue
            abs(observed[Symbol(:crossing, i)]) <= ROOT_TOLERANCE &&
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

function lower_discrete(::MTKEventsBackend, model::DiscreteModel)
    lowered = LoweredDiscrete(;
        equations = model.equations,
        initial_conditions = Pair[sym => start for (sym, start) in model.discretes]
    )
    blocks = model.when_blocks
    isempty(blocks) && return lowered
    n = length(blocks)
    previous = [only(@discretes($(gensym(:when_previous))(t))) for _ in blocks]
    active = [only(@discretes($(gensym(:when_active))(t))) for _ in blocks]
    root_time = only(@discretes($(gensym(:when_root_time))(t)))
    sample_time = only(@discretes($(gensym(:when_sample_time))(t)))
    event_time = only(@discretes($(gensym(:when_event_time))(t)))
    ready = only(@discretes($(gensym(:when_ready))(t)))
    next_sample = only(@discretes($(gensym(:when_next_sample))(t)))
    snapshot_sources = unique(vcat(model.variables, first.(model.discretes)))
    snapshots = [only(@discretes($(gensym(:when_pre))(t))) for _ in snapshot_sources]
    execute = [only(@discretes($(gensym(:when_execute))(t))) for _ in blocks]
    bookkeeping = vcat(previous, active, [root_time, sample_time, event_time, ready], snapshots, execute)
    append!(lowered.parameters, vcat(bookkeeping, [next_sample]))
    append!(
        lowered.initial_conditions,
        [p => 0.0 for p in vcat(previous, active, snapshots, execute, [ready])]
    )
    append!(lowered.initial_conditions, [root_time => -Inf, sample_time => -Inf, event_time => -Inf, next_sample => Inf])
    modified = NamedTuple{(Tuple(Symbol(:m, i) for i in eachindex(bookkeeping))..., :next_sample)}(
        Tuple(vcat(bookkeeping, [next_sample]))
    )
    obs_names = [:time]
    obs_values = Any[t]
    for (i, block) in enumerate(blocks)
        push!(obs_names, Symbol(:condition, i))
        push!(obs_values, isnothing(block.condition) ? Num(false) : block.condition)
        isnothing(block.crossing) && continue
        push!(obs_names, Symbol(:crossing, i))
        push!(obs_values, block.crossing)
    end
    for (i, var) in enumerate(snapshot_sources)
        push!(obs_names, Symbol(:snapshot, i))
        push!(obs_values, var)
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
    for (i, block) in enumerate(blocks)
        isnothing(block.condition) && continue
        changed = Num(block.condition) != (previous[i] > 0.5)
        if !isnothing(block.crossing)
            changed &= Num(abs(block.crossing) > ROOT_TOLERANCE)
        end
        mismatch |= changed
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
    # the event's pre-values, while plain discrete variables take their new values
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
    push!(
        lowered.event_iteration, ModelingToolkitBase.SymbolicDiscreteCallback(
            Symbolics.unwrap(pending), affects; discrete_parameters = discretes,
            initialize = affects, reinitializealg = EVENT_REINITIALIZATION
        )
    )
    return lowered
end

"""
    mtk_affect(block, model)

Affect equations for `block`. Returns `(affects, discrete_parameters)`.

Continuous variables are read through `Pre`, matching Modelica: inside an event they keep
their pre-event value, and `reinit` takes effect only after the event. Every state not
reinitialized is held with `x ~ Pre(x)`; MTK solves the affect together with the observed
equations of the model, and without these equations states that are not assigned are
treated as free unknowns of that system.
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
            if varies_continuously(condition)
                crossing = Num(to_zero_crossing(condition))
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
    for cb in callbacks
        condition = cb.conditions
        # Empty preset-time conditions represent disabled callbacks.
        condition isa AbstractVector && isempty(condition) && continue
        if !(condition isa Union{Bool, Num, SymbolicUtils.BasicSymbolic}) ||
                SymbolicUtils.symtype(Symbolics.unwrap(condition)) !== Bool
            throw(ArgumentError(
                "event_iteration callbacks require symbolic Boolean conditions " *
                    "(or an empty preset-time vector); put preset-time and periodic callbacks in discrete_events"
            ))
        end
        pending |= Num(condition)
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
