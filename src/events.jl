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
#   :event     when-bodies; `pre(x)` is `Pre(x)`, the value just before the event
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

function when_clauses(when_eq::BaseModelicaWhenEquation)
    length(when_eq.whens) == length(when_eq.thens) ||
        error("Malformed when-equation: $(length(when_eq.whens)) conditions but $(length(when_eq.thens)) bodies")
    clauses = WhenClause[]
    for (condition, body) in zip(when_eq.whens, when_eq.thens)
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
        push!(clauses, WhenClause(condition, sample_args(condition), assignments, reinits))
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
        foreach(walk, SymbolicUtils.arguments(x))
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

The evaluated body of every `when`/`elsewhen` branch that shares one trigger. Branches with
an identical zero-crossing (or identical `sample(start, interval)`) fire at the same
instant, so BaseModelica merges them into one block.

All expressions are symbolic, built from the symbols of [`DiscreteModel`](@ref):

- `condition`: the Boolean condition, e.g. `h(t) < 0`, with `pre(x)` evaluated as `x`.
  `nothing` for a `sample` trigger.
- `crossing`: an expression that crosses zero upwards when `condition` becomes true, e.g.
  `-h(t)` for `h < 0`. The block fires on that rising edge only. `nothing` for a `sample`
  trigger.
- `sample`: `nothing`, or `(start, interval)` for `when sample(start, interval)`.
- `assignments`: `v => rhs` for each `v = rhs` in the body; `v` is a discrete variable.
- `reinits`: `x => rhs` for each `reinit(x, rhs)`; `x` is a continuous state, and no
  state appears twice in one block.

In `rhs`, `pre(x)` is `ModelingToolkit.Pre(x)` (the value just before the event), for
discrete and continuous `x` alike. Any other variable appears as its plain symbol: a plain
discrete `v` means its new value at this event, a plain continuous `x` means its value at
the event instant (which equals its pre-event value).
"""
struct WhenBlock
    condition::Any
    crossing::Any
    sample::Union{Nothing, Tuple{Float64, Float64}}
    assignments::Vector{Pair{Any, Any}}
    reinits::Vector{Pair{Any, Any}}
end

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
                    initial_conditions = [], initialization_eqs = [])

What [`lower_discrete`](@ref) returns. BaseModelica builds the `System` from it:

- `equations`: every equation of the system, replacing `DiscreteModel.equations` (return
  those unchanged if the backend does not rewrite them).
- `continuous_events`, `discrete_events`: passed to `System`.
- `initial_conditions`: `variable => value` pairs, passed as `initial_conditions`.
- `initialization_eqs`: added to the model's own initialization equations.
"""
Base.@kwdef struct LoweredDiscrete
    equations::Vector{Equation}
    continuous_events::Vector{Any} = Any[]
    discrete_events::Vector{Any} = Any[]
    initial_conditions::Vector{Pair} = Pair[]
    initialization_eqs::Vector{Equation} = Equation[]
end

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
`@discretes`; each `when` trigger becomes a `SymbolicContinuousCallback` that fires on the
rising edge, and `sample(0, interval)` becomes a periodic `SymbolicDiscreteCallback`.
Assignments and `reinit` become affect equations in which continuous variables read their
pre-event value (`Pre`).
"""
struct MTKEventsBackend <: AbstractDiscreteBackend end

function lower_discrete(::MTKEventsBackend, model::DiscreteModel)
    lowered = LoweredDiscrete(;
        equations = model.equations,
        initial_conditions = Pair[sym => start for (sym, start) in model.discretes]
    )
    for block in model.when_blocks
        affects, discretes = mtk_affect(block, model)
        if isnothing(block.sample)
            # `affect_neg = nothing`: fire only when the condition becomes true (rising edge).
            # The reinitialization is that of the Boolean callbacks, so that a root shared
            # with them fires both (see relation_booleans.jl).
            push!(
                lowered.continuous_events, ModelingToolkitBase.SymbolicContinuousCallback(
                    continuous_conditions([block.crossing], !isempty(model.states)), affects;
                    affect_neg = nothing, discrete_parameters = discretes,
                    reinitializealg = EVENT_REINITIALIZATION
                )
            )
        else
            start, interval = block.sample
            start == 0 ||
                unsupported("sample(start, interval) with start ≠ 0 is not supported by the :mtk discrete backend")
            push!(
                lowered.discrete_events, ModelingToolkitBase.SymbolicDiscreteCallback(
                    interval, affects; discrete_parameters = discretes
                )
            )
        end
    end
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
    when_blocks(clauses; boolean_definitions)

Evaluate the AST-level `WhenClause`s into [`WhenBlock`](@ref)s, merging clauses that share
a trigger: separate callbacks with identical roots do not all fire at the same instant.
`boolean_definitions` are the definitions of the Booleans defined by an equation (see
[`lower_relation_booleans`](@ref)).
"""
function when_blocks(clauses; boolean_definitions = Dict{Symbol, Any}())
    blocks = WhenBlock[]
    for clause in clauses
        condition = crossing = nothing
        if isnothing(clause.sample)
            condition = with_eval_mode(() -> eval_AST(clause.condition), :condition)
            # `when b` for a Boolean defined by a relation triggers on that relation
            condition = expand_relation_boolean(condition, boolean_definitions)
            crossing = to_zero_crossing(condition)
        end
        assignments, reinits = with_eval_mode(:event) do
            Pair{Any, Any}[var => eval_AST(rhs) for (var, rhs) in clause.assignments],
                Pair{Any, Any}[state => eval_AST(rhs) for (state, rhs) in clause.reinits]
        end
        idx = findfirst(b -> isequal(b.crossing, crossing) && b.sample == clause.sample, blocks)
        if isnothing(idx)
            push!(blocks, WhenBlock(condition, crossing, clause.sample, assignments, reinits))
        else
            append!(blocks[idx].assignments, assignments)
            append!(blocks[idx].reinits, reinits)
        end
    end
    for block in blocks
        states = first.(block.reinits)
        for (i, state) in enumerate(states)
            any(isequal(state), states[1:(i - 1)]) &&
                unsupported("`$(symbol_name(state))` is reinitialized twice in the same event")
        end
    end
    return blocks
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
