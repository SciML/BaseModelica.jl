# Boolean variables defined by an equation, such as `off = s < 0` (the ideal diodes and
# switches of the MSL) or `y = pre(y) and u < a or u < b` (hysteresis).
#
# In Modelica a relation keeps its value while the solver integrates and changes only at
# events. At initialization and at every event the Booleans are solved together with the
# continuous part of the model (event iteration). The lowering:
#
# - Each Boolean `b` is a Real discrete parameter holding 0 or 1, and equations see
#   `b > 0.5`: ModelingToolkit cannot solve for a Bool parameter during initialization.
# - Initialization: `b => missing` with the initialization equation
#   `b ~ ifelse(definition, 1, 0)`, in which `pre(b)` is the start value of `b`. The
#   initialization solve finds the Booleans together with the unknowns they depend on, so
#   `b` does not keep a `start` value that contradicts its definition.
# - Events: every relation of a definition that depends on a continuous variable gets a
#   continuous callback on its zero-crossing. At the root the relation may evaluate either
#   way, so the direction of the crossing gives its new value. The callback then
#   re-evaluates every Boolean until none changes (`pre(b)` being the value of the previous
#   iteration).
# - A discrete callback, checked after every step, re-evaluates the Booleans when one of
#   them disagrees with its definition. That happens when a relation jumps at another event
#   (`reinit`, a `when` assignment) instead of crossing zero. A relation within
#   `ROOT_TOLERANCE` of its root is undetermined there, and the Booleans that depend on it
#   keep their value.
#
# The callbacks use the same root finding and reinitialization as the `when` callbacks of
# the `:mtk` backend: ModelingToolkit then compiles them into one vector callback, which
# fires every callback whose root is at the same instant. Separate callbacks with a common
# root, as in `when u > 0.5` and `b = u > 0.5`, would lose one of the two events.

# The expression that equations see for the Boolean held by the 0/1 parameter `sym`.
relation_boolean_value(sym) = sym > 0.5

# The name of the Boolean whose value expression is `x`, or nothing.
function relation_boolean_name(x)
    x isa Num || return nothing
    for (name, sym) in relation_boolean_syms
        isequal(x, relation_boolean_value(sym)) && return name
    end
    return nothing
end

# Preserve `pre(b)` for when snapshots and Boolean self-reference. Ordinary
# equations must validate the marker before lower_relation_booleans resolves it.
function relation_boolean_pre(name)
    return relation_boolean_value(ModelingToolkit.Pre(relation_boolean_syms[name]))
end

# Read a Boolean's left limit before selection has recorded the event snapshots.
function relation_boolean_left_limit(sym)
    haskey(relation_boolean_history, sym) || return sym
    time, snapshot = relation_boolean_history[sym]
    return ifelse(abs(t - time) <= 32eps(Float64) * max(1, abs(t)), snapshot, sym)
end

const BOOLEAN_CONNECTIVES = (&, |, !, ~, xor, ifelse)
const RELATIONS = (<, <=, >, >=)

# The atoms of the Boolean expression `x`: everything that is not a connective or a
# Boolean of `relation_boolean_syms`, e.g. relations and Boolean parameters.
function boolean_atoms!(atoms, x, values)
    x = Symbolics.unwrap(x)
    (x isa Bool || any(isequal(x), values)) && return atoms
    x isa SymbolicUtils.BasicSymbolic && SymbolicUtils.isconst(x) && return atoms
    if SymbolicUtils.iscall(x) && SymbolicUtils.operation(x) in BOOLEAN_CONNECTIVES
        foreach(arg -> boolean_atoms!(atoms, arg, values), SymbolicUtils.arguments(x))
    elseif !any(isequal(x), atoms)
        push!(atoms, x)
    end
    return atoms
end

# Whether `x` involves time or a continuous variable, i.e. can change between events.
function varies_continuously(x)
    return any(Symbolics.get_variables(Symbolics.unwrap(x))) do v
        # the independent variable counts as a parameter for `isparameter`
        isequal(v, t) || !ModelingToolkitBase.isparameter(v)
    end
end

# The zero-crossing of a relation atom `a op b` that varies continuously, or nothing. It is
# `(a - b) / 2` rather than `a - b` so that it never equals the condition of a `when`
# callback on the same relation: two identical conditions of one vector callback make the
# integrator fire the same event forever when both cross downwards at the same root.
function relation_crossing(atom)
    SymbolicUtils.iscall(atom) && SymbolicUtils.operation(atom) in RELATIONS || return nothing
    varies_continuously(atom) || return nothing
    a, b = SymbolicUtils.arguments(atom)
    return (a - b) / 2
end

# The value of the relation `atom` once its crossing has the sign `sign`.
relation_value_after(atom, sign) = (SymbolicUtils.operation(atom) in (>, >=)) == (sign > 0)

# A relation `a op b` is undetermined when |a - b| <= ROOT_TOLERANCE * (1 + |a| + |b|).
const ROOT_TOLERANCE = 1.0e-9

function crossing_scale(atom)
    a, b = SymbolicUtils.arguments(atom)
    return 1 + abs(a) + abs(b)
end

function evaluate_boolean(expr, values)
    value = concrete_value(SymbolicUtils.substitute(expr, values; fold = Val(true)))
    value isa Bool || error("could not evaluate the Boolean expression $expr (got $value)")
    return value
end

"""
    RelationBooleanUpdate

The affect of the relation-Boolean callbacks: event iteration over the Booleans.

- `definitions[k]`: the definition of the k-th modified Boolean, whose value expression
  (`b > 0.5`) is `values[k]`.
- `atoms`: the atoms of the definitions, observed at the event; `crossings[i]` is the index
  of the crossing of `atoms[i]` among the observed crossings, or 0.
- `forced`: atom index => value, for the relations whose crossing triggered the event.
- `depends[k]`: the indices of the atoms of `definitions[k]`.
"""
struct RelationBooleanUpdate
    definitions::Vector{Any}
    values::Vector{Any}
    atoms::Vector{Any}
    crossings::Vector{Int}
    forced::Dict{Int, Bool}
    depends::Vector{Vector{Int}}
end

function (update::RelationBooleanUpdate)(modified, observed, ctx, integ)
    natoms = length(update.atoms)
    n = length(update.values)
    old = collect(values(modified))
    # Keep the left limit even when the Boolean root callback precedes when selection.
    if !same_event_time(observed.time, old[n + 1])
        old[(n + 2):end] = old[1:n]
        old[n + 1] = observed.time
    end
    observed = Base.front(values(observed))
    # observed: the atoms, then |crossing| and the scale of each crossing
    ncross = (length(observed) - natoms) ÷ 2
    undetermined = falses(natoms)
    substitutions = Dict{Any, Any}()
    for (i, atom) in enumerate(update.atoms)
        if haskey(update.forced, i)
            substitutions[atom] = update.forced[i]
        else
            substitutions[atom] = Bool(observed[i])
            j = update.crossings[i]
            j == 0 || (
                undetermined[i] = observed[natoms + j] <=
                    ROOT_TOLERANCE * observed[natoms + ncross + j]
            )
        end
    end
    frozen = [any(i -> undetermined[i], deps) for deps in update.depends]
    current = Bool[v > 0.5 for v in old[1:n]]
    for _ in 0:length(current)
        for (value, b) in zip(update.values, current)
            substitutions[value] = b
        end
        next = Bool[
            frozen[k] ? current[k] : evaluate_boolean(d, substitutions)
                for (k, d) in enumerate(update.definitions)
        ]
        next == current && break
        current = next
    end
    old[1:n] = Float64.(current)
    return NamedTuple{keys(modified)}(Tuple(old))
end

"""
    lower_relation_booleans(eqs, model_name)

Take the equations defining the Booleans of `relation_boolean_syms` out of `eqs` and
lower them as described at the top of this file. Returns a named tuple with the remaining
`equations`, and the `parameters`, `bindings`, `initialization_eqs`, `continuous_events`,
`discrete_events` and `definitions` (name => definition) for the system.
"""
function lower_relation_booleans(eqs, model_name)
    has_states = !isempty(differentiated_variables(eqs))
    names = sort!(collect(keys(relation_boolean_syms)))
    syms = [relation_boolean_syms[name] for name in names]
    values = Any[Symbolics.unwrap(relation_boolean_value(sym)) for sym in syms]

    # A Boolean is defined by the first equation that has it alone on one side
    definitions = Dict{Symbol, Any}()
    equations = Equation[]
    for eq in eqs
        lhs = findfirst(isequal(eq.lhs), values)
        rhs = findfirst(isequal(eq.rhs), values)
        if !isnothing(lhs) && !haskey(definitions, names[lhs])
            definitions[names[lhs]] = eq.rhs
        elseif !isnothing(rhs) && !haskey(definitions, names[rhs])
            definitions[names[rhs]] = eq.lhs
        elseif !isnothing(lhs) || !isnothing(rhs)
            unsupported("Boolean `$(names[something(lhs, rhs)])` is defined by more than one equation")
        else
            push!(equations, eq)
        end
    end

    # Ordinary equations do not share the when backend's event-iteration snapshots.
    # Only self-referencing Boolean definitions can resolve pre locally. Reject other
    # reads before substitution can silently replace the left limit with the current value.
    for (name, definition) in definitions
        reads = condition_pre_arguments!(Num[], definition)
        any(arg -> !isequal(arg, relation_boolean_syms[name]), reads) &&
            unsupported("pre() in ordinary equations is only supported for a Boolean's self-reference (definition of `$name`)")
    end
    for eq in equations
        reads = condition_pre_arguments!(Num[], eq.lhs)
        condition_pre_arguments!(reads, eq.rhs)
        isempty(reads) || unsupported("pre() in ordinary equations is only supported for a Boolean's self-reference")
    end

    # Resolve the validated self-reference: current iteration, or initialization start.
    pre_markers = [Symbolics.unwrap(ModelingToolkit.Pre(sym)) for sym in syms]
    pre_current = Dict{Any, Any}(zip(pre_markers, Symbolics.unwrap.(syms)))
    pre_start = Dict{Any, Any}(zip(pre_markers, [relation_boolean_starts[n] for n in names]))
    initial_definitions = Dict(
        name => SymbolicUtils.substitute(definition, pre_start; fold = Val(true))
            for (name, definition) in definitions
    )
    equations = Equation[Symbolics.substitute(eq, pre_current) for eq in equations]
    for (name, definition) in definitions
        definitions[name] = Symbolics.substitute(definition, pre_current)
    end

    parameters = Num[]
    bindings = Pair[]
    initialization_eqs = Equation[]
    defined = Int[]
    undefined = Symbol[]
    for (i, name) in enumerate(names)
        start = relation_boolean_starts[name]
        if haskey(definitions, name)
            push!(defined, i)
            push!(parameters, ModelingToolkitBase.setguess(syms[i], start))
            push!(bindings, syms[i] => missing)
            initial_value = initial_definitions[name]
            push!(initialization_eqs, syms[i] ~ ifelse(initial_value, 1.0, 0.0))
        else
            push!(undefined, name)
            push!(parameters, ModelingToolkitBase.setdefault(syms[i], start))
        end
    end
    if !isempty(undefined)
        model_name isa BaseModelicaIdentifier && (model_name = model_name.name)
        @warn "BaseModelica model '$model_name': Booleans $(quoted_names(undefined)) have no defining equation and keep their start value"
    end

    continuous_events = Any[]
    discrete_events = Any[]
    if !isempty(defined)
        definitions_ = Any[Symbolics.unwrap(definitions[names[k]]) for k in defined]
        atoms = Any[]
        foreach(d -> boolean_atoms!(atoms, d, values), definitions_)
        depends = [findall(a -> any(isequal(a), boolean_atoms!(Any[], d, values)), atoms) for d in definitions_]
        # Distinct crossings; `a < b` and `b > a` share theirs, with opposite signs
        crossings = Any[]
        crossing_of = zeros(Int, length(atoms))
        crossing_sign = ones(Int, length(atoms))
        for (i, atom) in enumerate(atoms)
            c = relation_crossing(atom)
            isnothing(c) && continue
            j = findfirst(x -> isequal(x, c), crossings)
            if isnothing(j)
                j = findfirst(x -> isequal(x, -c), crossings)
                isnothing(j) || (crossing_sign[i] = -1)
            end
            isnothing(j) && (push!(crossings, c); j = length(crossings))
            crossing_of[i] = j
        end
        scales = Any[crossing_scale(atoms[findfirst(==(j), crossing_of)]) for j in eachindex(crossings)]
        event_time = only(@discretes($(gensym(:boolean_event_time))(t)))
        snapshots = [only(@discretes($(gensym(:boolean_pre))(t))) for _ in defined]
        append!(parameters, [event_time; snapshots])
        append!(bindings, [event_time => -Inf; [p => 0.0 for p in snapshots]])
        for (sym, snapshot) in zip(syms[defined], snapshots)
            relation_boolean_history[sym] = (event_time, snapshot)
        end
        modified_syms = vcat(syms[defined], [event_time], snapshots)
        modified = NamedTuple{Tuple(Symbol(:b, k) for k in eachindex(modified_syms))}(Tuple(modified_syms))
        observed = NamedTuple{
            Tuple(
                vcat(
                    [Symbol(:a, i) for i in eachindex(atoms)],
                    [Symbol(:c, j) for j in eachindex(crossings)],
                    [Symbol(:s, j) for j in eachindex(crossings)],
                    [:time]
                )
            ),
        }(Tuple(Num.(vcat(atoms, abs.(crossings), scales, [t]))))
        function affect(forced)
            update = RelationBooleanUpdate(
                definitions_, values[defined], atoms, crossing_of, forced, depends
            )
            return ModelingToolkitBase.ImperativeAffect(update; modified, observed)
        end
        for (j, c) in enumerate(crossings)
            crossed = findall(==(j), crossing_of)
            after(sign) = Dict{Int, Bool}(
                i => relation_value_after(atoms[i], sign * crossing_sign[i]) for i in crossed
            )
            push!(
                continuous_events, ModelingToolkitBase.SymbolicContinuousCallback(
                    continuous_conditions([c], has_states), affect(after(1));
                    affect_neg = affect(after(-1)), reinitializealg = EVENT_REINITIALIZATION
                )
            )
        end
        # Mismatches of the Booleans whose relations are all away from their roots
        mismatch = sum(eachindex(defined)) do k
            determined = prod(
                (
                    ifelse(abs(crossings[crossing_of[i]]) > ROOT_TOLERANCE * scales[crossing_of[i]], 1.0, 0.0)
                        for i in depends[k] if crossing_of[i] != 0
                );
                init = 1.0
            )
            determined * abs(ifelse(definitions_[k], 1.0, 0.0) - syms[defined[k]])
        end
        push!(
            discrete_events, ModelingToolkitBase.SymbolicDiscreteCallback(
                Symbolics.unwrap(mismatch > 0.5), affect(Dict{Int, Bool}());
                reinitializealg = EVENT_REINITIALIZATION
            )
        )
    end
    return (;
        equations, parameters, bindings, initialization_eqs, continuous_events,
        discrete_events, definitions,
    )
end
