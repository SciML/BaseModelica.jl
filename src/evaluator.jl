# function to convert "AST" to ModelingToolkit
using ModelingToolkit: t_nounits as t, D_nounits as D
using DiffEqBase: BrownFullBasicInit

@data BaseModelicaRuntimeTypes begin
    RTRecord()
    RTClass()
    RTFunction()
    #built in classes
    RTReal()
    RTInteger()
    RTBoolean()
    RTString()
end

function modelica_type_to_julia(type_str::AbstractString)
    if type_str == "Integer"
        return Int
    elseif type_str == "Boolean"
        return Bool
    elseif haskey(enum_map, type_str)
        return Int
    else  # "Real" or other
        return Float64
    end
end

function logical_operand(value)
    SymbolicUtils.symtype(Symbolics.unwrap(value)) === Bool ||
        unsupported("logical operand `$value` is not Boolean; logical use of when-assigned Booleans is not supported")
    return value
end

function eval_AST(expr::BaseModelicaExpr)
    return let f = eval_AST
        @match expr begin
            BaseModelicaNumber(val) => val
            BaseModelicaBool(val) => begin
                # val can be either a string "true"/"false" or a boolean true/false
                if isa(val, Bool)
                    val
                else
                    val == "true"
                end
            end
            BaseModelicaFactor(base, exp) => modelica_pow(f(base), f(exp))
            BaseModelicaSum(left, right) => modelica_add(f(left), f(right))
            BaseModelicaMinus(left, right) => modelica_sub(f(left), f(right))
            BaseModelicaUnaryMinus(operand) => -f(operand)
            BaseModelicaProd(left, right) => modelica_mul(f(left), f(right))
            BaseModelicaDivide(left, right) => modelica_div(f(left), f(right))
            BaseModelicaElementWiseSum(left, right) => f(left) .+ f(right)
            BaseModelicaElementWiseMinus(left, right) => f(left) .- f(right)
            BaseModelicaElementWiseProd(left, right) => f(left) .* f(right)
            BaseModelicaElementWiseDivide(left, right) => f(left) ./ f(right)
            BaseModelicaElementWiseFactor(base, exp) => f(base) .^ f(exp)
            BaseModelicaParens(inner) => f(inner)
            BaseModelicaNot(relation) => ~logical_operand(f(relation))
            BaseModelicaAnd(left, right) => logical_operand(f(left)) & logical_operand(f(right))
            BaseModelicaOr(left, right) => logical_operand(f(left)) | logical_operand(f(right))
            BaseModelicaLEQ(left, right) => f(left) <= f(right)
            BaseModelicaGEQ(left, right) => f(left) >= f(right)
            BaseModelicaLessThan(left, right) => f(left) < f(right)
            BaseModelicaGreaterThan(left, right) => f(left) > f(right)
            BaseModelicaEQ(left, right) => f(left) == f(right)
            BaseModelicaNEQ(left, right) => f(left) != f(right)
            _ => unsupported("expression $(nameof(typeof(expr))) is not supported")
        end
    end
end

function build_nested_ifelse(if_expr::BaseModelicaIfExpression, idx = 1)
    if idx > length(if_expr.conditions)
        return eval_AST(if_expr.expressions[end])
    end
    condition = logical_operand(eval_AST(if_expr.conditions[idx]))
    collect_time_events!(condition)
    then_value = eval_AST(if_expr.expressions[idx])
    else_value = build_nested_ifelse(if_expr, idx + 1)
    return modelica_ifelse(condition, then_value, else_value)
end

function eval_AST(if_expr::BaseModelicaIfExpression)
    return build_nested_ifelse(if_expr)
end

include("maps.jl")

function eval_AST(eq::BaseModelicaInitialEquation)
    inner_eq = inner_equation(eq.equation)
    # Skip tuple-return assignments like (a, b, , ) = func(...) — not supported
    inner_eq isa BaseModelicaSimpleEquation && inner_eq.lhs isa Vector && return Pair[]
    equations = eval_AST(inner_eq)
    isnothing(equations) && return Pair[]
    # Constraints can share a left side, e.g. {0, 0} = {x - 1, y - 2}.
    # Keep every row, including equations produced by initial for/if-equations.
    return Pair[eq.lhs => eq.rhs for eq in vcat(equations)]
end

function eval_AST(eq::BaseModelicaAnyEquation)
    equation = eval_AST(eq.equation)
    description = eq.description
    return equation
end

function eval_AST(annotation::BaseModelicaAnnotation)
    # Annotations are metadata and don't produce equations
    # For now, return nothing (they are parsed but ignored during evaluation)
    return nothing
end

# Helper function to extract a specific class modification value by name
function get_class_modification_value(modification, key_name::String)
    if isnothing(modification) || isempty(modification)
        return nothing
    end

    mod = modification[1]
    if isnothing(mod.class_modifications)
        return nothing
    end

    for arg in mod.class_modifications
        # Extract name string from BaseModelicaIdentifier
        arg_name = arg.name isa BaseModelicaIdentifier ? arg.name.name : arg.name
        if arg_name == key_name
            # If the arg has a modification with an expression, evaluate it
            if !isnothing(arg.modification) && !isnothing(arg.modification.expr) &&
                    !isempty(arg.modification.expr)
                return eval_AST(arg.modification.expr[end])
            end
        end
    end

    return nothing
end

function eval_AST(eq::BaseModelicaSimpleEquation)
    if eq.lhs isa Union{BaseModelicaIfEquation, BaseModelicaForEquation}
        return eval_AST(eq.lhs)
    end
    if isnothing(eq.rhs) && eq.lhs isa BaseModelicaFunctionCall
        # Function-call statement outside a when-equation: only assert is meaningful here
        fname = function_call_name(eq.lhs)
        fname == "assert" && return nothing
        unsupported("`$fname(...)` statement outside a when-equation is not supported")
    end
    lhs = eval_AST(eq.lhs)
    rhs = eval_AST(eq.rhs)

    # If either side is nothing (e.g., from assert or other non-equation statements),
    # return nothing to filter out this equation
    if isnothing(lhs) || isnothing(rhs)
        return nothing
    end

    return equate(lhs, rhs)
end

# The equations of a branch of an if-equation, flattened
function branch_equations(branch)
    result = Equation[]
    for eq in (isa(branch, AbstractArray) ? branch : [branch])
        inner = inner_equation(eq)
        eq_obj = eval_AST(inner)
        if eq_obj isa Equation
            push!(result, eq_obj)
        elseif eq_obj isa AbstractVector
            append!(result, eq_obj)
        end
    end
    return result
end

# Top-level when-equations go through the discrete backend. Encountering one
# here means it is in a structured equation body that is not lowered as events.
eval_AST(::BaseModelicaWhenEquation) =
    unsupported("when-equations in nested equation bodies are not supported")

# A concrete true condition is an else, even after symbolic conditions. OMC
# emits this form for if-equations without an explicit else (issue #41).
# Do not substitute tunable parameter defaults while normalizing the branches.
function normalize_if_equation(eq::BaseModelicaIfEquation)
    conditions = eltype(eq.ifs)[]
    branches = eltype(eq.thens)[]
    for (ast, branch) in zip(eq.ifs, eq.thens)
        condition = try
            load_if_condition(eval_AST(ast); resolve_parameters = false)
        catch err
            # An earlier parameter branch may make this condition unreachable.
            # Defer errors until branch selection actually needs the condition.
            err isa Union{BoundsError, UnsupportedFeatureError} || rethrow()
            nothing
        end
        condition === false && continue
        push!(branches, branch)
        condition === true && return BaseModelicaIfEquation(conditions, branches)
        push!(conditions, ast)
    end
    length(eq.thens) > length(eq.ifs) && push!(branches, eq.thens[end])
    return BaseModelicaIfEquation(conditions, branches)
end

# Non-tunable parameters are structural even when their branches have equal
# counts and targets. Never substitute tunable defaults on this first pass.
function load_if_condition(condition; resolve_parameters)
    bindings = resolve_parameters ? parameter_val_map : Dict(
        sym => value for (sym, value) in parameter_val_map
            if !ModelingToolkit.istunable(sym) && !(symbol_name(sym) in discrete_variable_names)
    )
    value = resolve_value(condition, bindings)
    return concrete_value(SymbolicUtils.substitute(value, Dict(); fold = Val(true)))
end

# Count scalar rows, not the unknowns referenced by each row. Record equations
# contribute one row per scalar field, just like their field-by-field form.
function scalar_equation_count(value)
    if value isa NamedTuple || is_array(value)
        elements = value isa NamedTuple ? values(value) : value
        # A generator counts concrete rows even for a retained symbolic array;
        # sum(f, array) can instead construct a symbolic reduction.
        return sum((scalar_equation_count(element) for element in elements); init = 0)
    end
    return 1
end

function branch_equation_count(branch)
    count = 0
    for entry in body_list(branch)
        eq = inner_equation(entry)
        current = if eq isa BaseModelicaIfEquation
            eq = normalize_if_equation(eq)
            selected = load_if_branch(eq; resolve_parameters = false)
            if !isnothing(selected)
                selected == 0 ? 0 : branch_equation_count(eq.thens[selected])
            else
                nested = balanced_if_equation_count(eq)
                if isnothing(nested)
                    selected = load_if_branch(eq)
                    isnothing(selected) && return nothing
                    selected == 0 ? 0 : branch_equation_count(eq.thens[selected])
                else
                    nested
                end
            end
        elseif eq isa BaseModelicaForEquation
            outer = LOCAL_SCOPE[]
            index = loop_index_name(eq.index)
            subtotal = 0
            for value in loop_range(eq.index)
                scope = isnothing(outer) ? Dict{Symbol, Any}() : copy(outer)
                scope[index] = value
                nested = with_local_scope(() -> branch_equation_count(eq.equations), scope)
                isnothing(nested) && return nothing
                subtotal += nested
            end
            subtotal
        elseif eq isa BaseModelicaSimpleEquation
            isnothing(eq.rhs) && continue # assert statements do not constrain a row
            lhs = eval_AST(eq.lhs)
            # Scalar residuals may have an array on their right side. Otherwise
            # only inspect the left side, leaving inactive right sides untouched.
            value = !is_array(lhs) && !(lhs isa NamedTuple) &&
                !isnothing(concrete_value(lhs)) ? eval_AST(eq.rhs) : lhs
            scalar_equation_count(value)
        else
            return nothing
        end
        isnothing(current) && return nothing
        count += current
    end
    return count
end

function balanced_if_equation_count(eq::BaseModelicaIfEquation)
    length(eq.thens) > length(eq.ifs) || return nothing
    count = nothing
    for branch in eq.thens
        current = try
            branch_equation_count(branch)
        catch err
            # An inactive branch can use invalid indices or unsupported calls.
            err isa Union{BoundsError, UnsupportedFeatureError} || rethrow()
            return nothing
        end
        isnothing(current) && return nothing
        isnothing(count) || current == count || return nothing
        count = current
    end
    return count
end

# Flatten targets across retained arrays and records before comparing branches.
function scalar_target_values(value)
    if value isa NamedTuple || is_array(value)
        elements = value isa NamedTuple ? values(value) : value
        return reduce(vcat, (scalar_target_values(element) for element in elements); init = Any[])
    end
    return Any[value]
end

# Residual equations (0 = expression) constrain the unknowns in their right side.
# Inspect references, rather than executing that expression during classification.
function residual_targets!(targets, node)
    if node isa BaseModelicaComponentReference ||
            (node isa BaseModelicaFunctionCall && function_call_name(node) == "der")
        value = eval_AST(node)
        for sym in scalar_target_values(value)
            is_inlined(sym) && continue
            isequal(sym, t) && continue
            name = symbol_name(Symbolics.wrap(sym))
            if !ModelingToolkitBase.isparameter(sym) || name in free_parameter_names ||
                    name in discrete_variable_names || name in bool_comparison_names
                push!(targets, Symbolics.unwrap(sym))
            end
        end
    elseif node isa BaseModelicaFunctionCall
        residual_targets!(targets, node.args)
    elseif node isa Union{AbstractVector, Tuple}
        foreach(child -> residual_targets!(targets, child), node)
    elseif node isa BaseModelicaASTNode
        for field in fieldnames(typeof(node))
            residual_targets!(targets, getfield(node, field))
        end
    end
    return targets
end

# Classify branches from their targets without evaluating right sides. In particular,
# a discarded equation may contain an out-of-bounds subscript or an undefined call.
function branch_targets(branch)
    targets = Set{Any}()
    for entry in body_list(branch)
        eq = inner_equation(entry)
        if eq isa BaseModelicaIfEquation
            eq = normalize_if_equation(eq)
            selected = load_if_branch(eq; resolve_parameters = false)
            if !isnothing(selected)
                nested = selected == 0 ? Set{Any}() : branch_targets(eq.thens[selected])
            else
                nested = balanced_if_targets(eq)
            end
            if isnothing(nested)
                selected = load_if_branch(eq)
                isnothing(selected) && return nothing
                nested = selected == 0 ? Set{Any}() : branch_targets(eq.thens[selected])
            end
            isnothing(nested) && return nothing
            union!(targets, nested)
        elseif eq isa BaseModelicaForEquation
            outer = LOCAL_SCOPE[]
            index = loop_index_name(eq.index)
            for value in loop_range(eq.index)
                scope = isnothing(outer) ? Dict{Symbol, Any}() : copy(outer)
                scope[index] = value
                nested = with_local_scope(() -> branch_targets(eq.equations), scope)
                isnothing(nested) && return nothing
                union!(targets, nested)
            end
        elseif eq isa BaseModelicaSimpleEquation
            isnothing(eq.rhs) && continue # assert statements do not constrain a target
            lhs = eval_AST(eq.lhs)
            elements = scalar_target_values(lhs)
            if all(value -> !isnothing(concrete_value(value)), elements)
                residual_targets!(targets, eq.rhs)
            else
                # Equation fields use unwrapped symbols too, so residual and
                # direct assignments compare the same targets.
                union!(targets, Symbolics.unwrap.(elements))
            end
        else
            return nothing
        end
    end
    return targets
end

function balanced_if_targets(eq::BaseModelicaIfEquation)
    length(eq.thens) > length(eq.ifs) || return nothing
    targets = nothing
    for branch in eq.thens
        current = try
            branch_targets(branch)
        catch err
            # An inactive branch can use indices outside the declared array.
            err isa Union{BoundsError, UnsupportedFeatureError} || rethrow()
            return nothing
        end
        isnothing(current) && return nothing
        isnothing(targets) || isequal(current, targets) || return nothing
        targets = current
    end
    return targets
end

# Zero denotes an absent else. `nothing` means the structure cannot be selected.
function load_if_branch(
        eq::BaseModelicaIfEquation; record_parameters = false, resolve_parameters = true
    )
    conditions = Any[]
    selected = 0
    for (i, ast) in enumerate(eq.ifs)
        condition = eval_AST(ast)
        push!(conditions, condition)
        value = load_if_condition(condition; resolve_parameters)
        value isa Bool || return nothing
        if value
            selected = i
            break
        end
    end
    if selected == 0 && length(eq.thens) > length(eq.ifs)
        selected = length(eq.thens)
    end
    record_parameters && foreach(record_if_parameters!, conditions)
    return selected
end

function eval_AST(if_eq::BaseModelicaIfEquation)
    if_eq = normalize_if_equation(if_eq)
    # Constants, non-tunable parameters and loop indices select at load, avoiding
    # inactive branches (which can contain y[i-1] at i=1).
    selected = load_if_branch(if_eq; resolve_parameters = false)
    if !isnothing(selected)
        return selected == 0 ? Equation[] : branch_equations(if_eq.thens[selected])
    end
    if isnothing(balanced_if_equation_count(if_eq))
        selected = load_if_branch(if_eq; record_parameters = true)
        isnothing(selected) && unsupported(
            "$(EVAL_MODE[] === :initial ? "initial " : "")if-equation condition must be evaluable at load time when branches do not have the same number of scalar equations, including an else; time-varying or discrete conditions require balanced branches"
        )
        return selected == 0 ? Equation[] : branch_equations(if_eq.thens[selected])
    end

    # Count balance alone is insufficient for a tunable parameter: changing
    # targets may change the state/initialization structure after remake.
    if isnothing(balanced_if_targets(if_eq))
        selected = load_if_branch(if_eq; record_parameters = true)
        if !isnothing(selected)
            return selected == 0 ? Equation[] : branch_equations(if_eq.thens[selected])
        end
    end

    branches = [branch_equations(branch) for branch in if_eq.thens]

    # A vectorized loop may assign y[1:1:n] where another branch assigns y.
    # Match their scalar targets when branch representations differ; identical
    # whole-array branches can retain their compact array equations.
    if !isempty(branches)
        targets = Set(eq.lhs for eq in first(branches))
        if any(branch -> !isequal(Set(eq.lhs for eq in branch), targets), branches)
            branches = [
                reduce(vcat, (vec(vcat(Symbolics.scalarize(eq))) for eq in branch); init = Equation[])
                    for branch in branches
            ]
        end
    end

    targets = Set(eq.lhs for eq in first(branches))
    differing_targets = any(branch -> !isequal(Set(eq.lhs for eq in branch), targets), branches)

    # Symbolic conditions with matching targets follow remake. Dynamic differing
    # targets need scalar row pairing, with explicit state derivatives first.
    foreach(cond -> collect_time_events!(eval_AST(cond)), if_eq.ifs)
    if differing_targets || any(branch -> length(Set(eq.lhs for eq in branch)) != length(branch) ||
            !isempty(differentiated_variables([0 ~ eq.rhs for eq in branch])), branches)
        rows = [
            reduce(vcat, (vec(vcat(Symbolics.scalarize(eq))) for eq in branch); init = Equation[])
                for branch in branches
        ]
        all(branch -> length(branch) == length(first(rows)), rows) ||
            unsupported("balanced if-equation branches must have the same number of scalar equations")
        return explicit_if_equation_rows(if_eq, rows)
    end

    # Helper to extract RHS for a specific variable from a branch's equation list
    function get_rhs_for_var(var_lhs, branch)
        idx = findfirst(eq -> isequal(eq.lhs, var_lhs), branch)
        return isnothing(idx) ? nothing : Symbolics.wrap(branch[idx].rhs)
    end

    # Collect all unique LHS variables across all branches, in order of appearance
    lhs_vars = []
    for branch in branches, eq in branch
        any(v -> isequal(v, eq.lhs), lhs_vars) || push!(lhs_vars, eq.lhs)
    end

    # Build nested ifelse for each variable
    function build_ifelse_for_var(var_lhs, idx = 1)
        if idx > length(if_eq.ifs)
            # Past all conditions
            return get_rhs_for_var(var_lhs, branches[end])
        end

        condition = logical_operand(eval_AST(if_eq.ifs[idx]))
        rhs = get_rhs_for_var(var_lhs, branches[idx])

        if isnothing(rhs)
            error("Variable $var_lhs not assigned in branch $idx")
        end

        else_expr = build_ifelse_for_var(var_lhs, idx + 1)
        return modelica_ifelse(condition, rhs, else_expr)
    end

    result_equations = []
    for var in lhs_vars
        ifelse_rhs = build_ifelse_for_var(var)
        push!(result_equations, var ~ ifelse_rhs)
    end

    return result_equations
end

# Pair differential rows by state, independently of their order or which side
# contains the derivative. Consuming a row twice (coupled derivatives) or leaving
# a derivative in an algebraic residual would recreate implicit initialization.
function explicit_if_equation_rows(if_eq, rows)
    states = differentiated_variables(reduce(vcat, rows; init = Equation[]))
    remaining = [trues(length(branch)) for branch in rows]
    conditions = [logical_operand(eval_AST(ast)) for ast in if_eq.ifs]
    function choose(values)
        rhs = values[end]
        for j in reverse(eachindex(conditions))
            rhs = modelica_ifelse(conditions[j], values[j], rhs)
        end
        return rhs
    end
    result = Equation[]
    for state in states
        derivative = D(Symbolics.wrap(state))
        values = Any[]
        for (j, branch) in enumerate(rows)
            indices = findall(eq -> any(v -> isequal(v, state), differentiated_variables([eq])), branch)
            length(indices) == 1 || unsupported(
                "if-equation derivative der($state) must occur in exactly one row of every branch; missing or repeated in branch $j"
            )
            i = only(indices)
            remaining[j][i] || unsupported(
                "if-equation cannot isolate der($state): a row contains coupled state derivatives in branch $j"
            )
            eq = branch[i]
            a, b, linear = Symbolics.linear_expansion(eq.rhs - eq.lhs, derivative)
            linear && !iszero(a) || unsupported(
                "if-equation cannot isolate der($state) in branch $j; the row must be linear in that derivative with a nonzero coefficient"
            )
            rhs = -b / a
            isempty(differentiated_variables([0 ~ rhs])) || unsupported(
                "if-equation cannot isolate der($state): a row contains coupled state derivatives in branch $j"
            )
            push!(values, rhs)
            remaining[j][i] = false
        end
        push!(result, derivative ~ choose(values))
    end
    algebraic = [branch[mask] for (branch, mask) in zip(rows, remaining)]
    for i in eachindex(first(algebraic))
        push!(result, 0 ~ choose([branch[i].rhs - branch[i].lhs for branch in algebraic]))
    end
    return result
end

# Names of variables assigned in when-equation bodies: these are discrete variables.
function collect_when_body_var_names(equations)
    names = Set{Symbol}()
    for eq in equations
        when_eq = as_when_equation(eq)
        isnothing(when_eq) && continue
        for body in when_eq.thens, body_eq in body_list(body)
            inner = inner_equation(body_eq)
            if inner isa BaseModelicaSimpleEquation &&
                    inner.lhs isa BaseModelicaComponentReference && !isnothing(inner.rhs)
                union!(names, element_names(inner.lhs))
            end
        end
    end
    return names
end

function eval_AST(x::String)
    return x
end

function eval_AST(x::BaseModelicaString)
    return x.string
end

function eval_AST(::Nothing)
    return nothing
end

function eval_AST(component::BaseModelicaComponentClause)
    #this mutates a dict
    #place holder to get simple equations working
    #also needs to account for "modifications"
    #also doesn't handle constants yet
    list = component.component_list
    type_prefix = component.type_prefix.dpc
    declaration = list[1].declaration
    name = Symbol(declaration.ident[1].name)
    if type_prefix == "parameter"
        component.type_specifier.type == "String" && return nothing
        julia_type = modelica_type_to_julia(component.type_specifier.type)
        variable_map[name] = only(@parameters($name::julia_type))

        # Extract parameter value from modification
        # Modifications can be:
        # 1. Simple assignment: = value
        # 2. Class modification with assignment: (attr1=val1, ...) = value
        # In case 2, expr has multiple elements; the value is the last element
        if !isnothing(declaration.modification) && !isempty(declaration.modification)
            modification = declaration.modification[1]
            if !isnothing(modification.expr) && !isempty(modification.expr)
                # Get the last element which should be the assigned value
                # If there's only one element, it's a simple assignment
                # If there are multiple elements, the last one is the value after class modifications
                value_expr = modification.expr[end]

                # Evaluate the expression to get the numeric value
                parameter_val_map[variable_map[name]] = eval_AST(value_expr)
            end
        end
        return variable_map[name]
    elseif isnothing(type_prefix)
        variable_map[name] = only(@variables($name(t)))
    end
end

"""
    collect_time_events!(condition)

Add to `tstops_collection` the instants at which a relation of `condition` between `time`
and an expression of parameters, such as `time < startTime`, changes. Such an if-condition
switches at a known time without generating an event, so the solver is made to stop there
instead of stepping over the discontinuity. The instants stay symbolic and follow changes
of the parameters.
"""
function collect_time_events!(condition)
    x = Symbolics.unwrap(condition)
    x isa SymbolicUtils.BasicSymbolic && SymbolicUtils.iscall(x) || return
    args = SymbolicUtils.arguments(x)
    if SymbolicUtils.operation(x) in RELATIONS
        a, b = args
        instant = isequal(a, t) ? b : isequal(b, t) ? a : nothing
        if !isnothing(instant) && !varies_continuously(instant)
            any(isequal(instant), tstops_collection) || push!(tstops_collection, instant)
        end
    else
        foreach(collect_time_events!, args)
    end
    return
end

function eval_AST(
        model::BaseModelicaModel; backend::AbstractDiscreteBackend = MTKEventsBackend(),
        simplify = true, arrays = :scalarize
    )
    empty!(variable_map)
    empty!(parameter_val_map)
    empty!(discrete_variable_names)
    empty!(integer_variable_names)
    empty!(free_parameter_names)
    empty!(evaluated_parameter_names)
    empty!(if_condition_parameter_names)
    empty!(tstops_collection)
    empty!(bool_comparison_names)
    empty!(relation_boolean_syms)
    empty!(relation_boolean_history)
    empty!(relation_boolean_starts)

    class_specifier = model.long_class_specifier

    composition = class_specifier.composition

    # Select array representations after expanding records into field declarations.
    components = scalarize_components(
        expand_record_components(composition.components); arrays,
        equations = composition.equations, parameter_equations = composition.parameter_equations, backend
    )
    equations = composition.equations
    initial_equations = composition.initial_equations
    parameter_equations = composition.parameter_equations

    # Pre-scan when-equation bodies to find variables that should be discrete parameters.
    # These variables only change at events and must not have continuous ODE equations.
    union!(discrete_variable_names, collect_when_body_var_names(equations))

    # Two-pass approach for components:
    # Pass 1: Create all symbols in variable_map (without evaluating parameter values)
    # Pass 2: Evaluate parameter values (now all symbols exist for cross-references)

    # Component names in declaration order. Everything handed to ModelingToolkit iterates
    # these rather than `variable_map`: the iteration order of a Dict keyed by Symbols
    # depends on what was parsed before in the session.
    declared_names = unique!([Symbol(comp.component_list[1].declaration.ident[1].name) for comp in components])

    vars = Any[]
    declaration_eqs = []
    # Collects stateSelect values keyed by variable name, populated in Pass 2.
    # Keyed by name (Symbol) rather than the symbol itself so the final state_priorities
    # dict can be built after Pass 3.5 when variable_map symbols are fully resolved.
    state_select_raw = Dict{Symbol, Int}()

    # Pass 1: Create all variables and parameters in variable_map
    for comp in components
        name = Symbol(comp.component_list[1].declaration.ident[1].name)
        type_prefix = comp.type_prefix.dpc
        comp.type_specifier.type == "Integer" && push!(integer_variable_names, name)
        length(comp.component_list) == 1 ||
            unsupported("component clauses declaring several components are not supported")

        if haskey(kept_array_dims, name)
            parameter = type_prefix == "parameter" || haskey(enum_map, comp.type_specifier.type)
            evaluated = parameter && is_evaluate_annotated(comp)
            evaluated && push!(evaluated_parameter_names, name)
            discrete = type_prefix == "discrete" || name in discrete_variable_names
            discrete && push!(discrete_variable_names, name)
            variable_map[name] = declare_array(
                name, kept_array_dims[name], modelica_type_to_julia(comp.type_specifier.type);
                parameter, tunable = !evaluated, discrete
            )
            parameter || discrete || push!(vars, variable_map[name])
            continue
        end

        if type_prefix == "parameter" || haskey(enum_map, comp.type_specifier.type)
            comp.type_specifier.type == "String" && continue
            julia_type = modelica_type_to_julia(comp.type_specifier.type)
            variable_map[name] = if type_prefix == "parameter" && is_evaluate_annotated(comp)
                push!(evaluated_parameter_names, name)
                only(@parameters $name::julia_type [tunable = false, description = evaluated_description(name)])
            else
                only(@parameters($name::julia_type))
            end
        elseif type_prefix == "constant"
            # A symbol for now, so that constants can refer to each other; replaced by its
            # value below. Unresolved constants keep this non-tunable symbol.
            comp.type_specifier.type == "String" && continue
            julia_type = modelica_type_to_julia(comp.type_specifier.type)
            variable_map[name] = only(@parameters $name::julia_type [tunable = false])
        elseif type_prefix == "discrete"
            # Explicitly declared discrete variables — treat same as when-body discretes.
            union!(discrete_variable_names, [name])
            variable_map[name] = declare_discrete(backend, name)
        elseif isnothing(type_prefix)
            if name in discrete_variable_names
                # Discrete variables only change at events; the backend decides how they
                # are represented (MTK discretes or SynchToolkit clocked variables).
                variable_map[name] = declare_discrete(backend, name)
            elseif comp.type_specifier.type == "Boolean"
                # Booleans defined by an equation (e.g. `off = s < 0`) hold their value
                # between events: a 0/1 discrete parameter, see relation_booleans.jl.
                # Equations see `off > 0.5`.
                push!(bool_comparison_names, name)
                disc_sym = only(@discretes($name(t)::Real))
                relation_boolean_syms[name] = disc_sym
                variable_map[name] = relation_boolean_value(disc_sym)
            else
                variable_map[name] = only(@variables($name(t)))
                push!(vars, variable_map[name])
            end
        end
    end

    inline_constants!(variable_map, components)
    # Values cached during pass 1 may refer to constants that are now inlined
    empty!(ELEMENT_CACHE)
    warn_structural_parameters(
        class_specifier.name, evaluated_parameter_names,
        inert_parameter_names(composition, components)
    )

    # Start values of discrete variables (the value of `pre(v)` at the first event).
    # Modelica's default start value is zero (false for Booleans).
    discrete_starts = Dict{Symbol, Any}()

    # Pass 2: Evaluate parameter values and handle start/fixed for variables
    for comp in components
        type_prefix = comp.type_prefix.dpc
        name = Symbol(comp.component_list[1].declaration.ident[1].name)
        declaration = comp.component_list[1].declaration

        if name in discrete_variable_names
            start_value = get_class_modification_value(declaration.modification, "start")
            isnothing(start_value) || (start_value = array_attribute(name, start_value))
            discrete_starts[name] = something(
                start_value, comp.type_specifier.type == "Boolean" ? false : 0.0
            )
            continue
        elseif name in bool_comparison_names
            # Every parameter symbol now exists, including forward references. Keep the
            # start symbolic so initialization (and remake) uses the current parameters.
            start_value = get_class_modification_value(declaration.modification, "start")
            isnothing(start_value) || (start_value = array_attribute(name, start_value))
            relation_boolean_starts[name] = ifelse(something(start_value, false), 1.0, 0.0)
            # A declaration equation `Boolean b = expr` defines b
            expr = binding_expression(declaration)
            isnothing(expr) || push!(declaration_eqs, variable_map[name] ~ eval_AST(expr))
            continue
        elseif !haskey(variable_map, name) || is_inlined(variable_map[name])
            # Skipped String component, or inlined constant
            continue
        end

        if type_prefix == "parameter" || type_prefix == "constant" ||
                haskey(enum_map, comp.type_specifier.type)
            comp.type_specifier.type == "String" && continue
            # Check for fixed = false (parameter to be solved during initialization)
            fixed_value = get_class_modification_value(declaration.modification, "fixed")
            is_free = !isnothing(fixed_value) && fixed_value === false

            if is_free
                push!(free_parameter_names, name)
                # start value is an initial guess, not a default
                start_value = get_class_modification_value(declaration.modification, "start")
                isnothing(start_value) || (start_value = array_attribute(name, start_value))
                if !isnothing(start_value)
                    variable_map[name] = ModelingToolkitBase.setguess(variable_map[name], start_value)
                end
            else
                # Collect into parameter_val_map; setdefault is applied in pass 3.5 below,
                # once every value has been collected (values may refer to parameters
                # declared later, e.g. V.signalSource.startTime = V.startTime).
                if !isnothing(declaration.modification) && !isempty(declaration.modification)
                    modification = declaration.modification[1]
                    if !isnothing(modification.expr) && !isempty(modification.expr)
                        value_expr = modification.expr[end]
                        parameter_val_map[variable_map[name]] = eval_AST(value_expr)
                    end
                end
            end
        elseif isnothing(type_prefix)
            # This is a variable - check for start and fixed attributes
            start_value = get_class_modification_value(declaration.modification, "start")
            isnothing(start_value) || (start_value = array_attribute(name, start_value))
            fixed_value = get_class_modification_value(declaration.modification, "fixed")

            var = variable_map[name]
            if !isnothing(start_value)
                # If fixed=true, use setdefault for initial condition
                # Otherwise use setguess for guess value
                is_fixed = !isnothing(fixed_value) &&
                    (fixed_value === true || fixed_value == true)
                if is_fixed
                    variable_map[name] = ModelingToolkitBase.setdefault(var, start_value)
                else
                    variable_map[name] = ModelingToolkitBase.setguess(var, start_value)
                end
            else
                # No explicit start: set a default guess of 0.0 so that all variables
                # have numeric guesses. Without this, MTK's initialization problem can
                # end up with symbolic (cyclic) guesses when missing_guess_value is not
                # forwarded through SCCNonlinearProblem → NonlinearProblem.
                variable_map[name] = ModelingToolkitBase.setguess(var, array_attribute(name, 0.0))
            end
            idx = findfirst(v -> SymbolicIndexingInterface.getname(v) == name, vars)
            !isnothing(idx) && (vars[idx] = variable_map[name])

            # stateSelect attribute: StateSelect.never/avoid/default/prefer/always → Int 1–5
            ss_value = get_class_modification_value(declaration.modification, "stateSelect")
            if is_array(ss_value) && !isempty(ss_value) && all(v -> v isa Int, ss_value) &&
                    all(==(first(ss_value)), ss_value)
                ss_value = first(ss_value)
            end
            if !isnothing(ss_value) && ss_value isa Int
                state_select_raw[name] = ss_value
            end

            # Check for declaration equation (e.g. Boolean 'y' = time >= 0.5)
            # A direct expression in the modification (not a named class attribute) is a
            # binding equation that must become an explicit MTK equation.
            if !isnothing(declaration.modification) && !isempty(declaration.modification)
                mod = declaration.modification[1]
                if !isnothing(mod.expr) && !isempty(mod.expr)
                    decl_val = eval_AST(mod.expr[end])
                    if !isnothing(decl_val)
                        push!(declaration_eqs, variable_map[name] ~ decl_val)
                    end
                end
            end
        end
    end

    # Pass 3: A parameter whose value refers to other parameters (`r = p*q`) keeps it as a
    # symbolic default, which ModelingToolkit turns into a binding: `r` is then recomputed
    # whenever `p` or `q` change, and cannot be set itself. A parameter marked
    # `Evaluate = true` was evaluated at translation, so its value is resolved to a number.
    for name in evaluated_parameter_names
        sym = variable_map[name]
        haskey(parameter_val_map, sym) || continue
        value = resolve_value(parameter_val_map[sym], parameter_val_map)
        parameter_val_map[sym] = something(concrete_value(value), value)
    end

    # Pass 3.5: Apply parameter values via setdefault: a number becomes an initial value,
    # an expression a binding. Symbols in the expressions may predate setdefault/setguess,
    # which is fine because metadata does not affect symbol equality.
    for name in declared_names
        haskey(variable_map, name) || continue
        sym = variable_map[name]
        val = get(parameter_val_map, sym, nothing)
        if !isnothing(val)
            variable_map[name] = ModelingToolkitBase.setdefault(sym, val)
        end
    end

    # Build state_priorities from stateSelect attributes collected in Pass 2.
    # variable_map is now fully resolved (after Pass 3.5), so symbol keys are stable.
    state_priorities = Dict(
        variable_map[name] => state_select_raw[name]
            for name in declared_names
            if haskey(state_select_raw, name) && haskey(variable_map, name) &&
            state_select_raw[name] != Int(StateSelectDefault)
    )

    # Split equations into when-equations (→ events) and regular equations.
    when_equation_list = []
    regular_equations = []
    initial_algorithms = []
    for eq in equations
        if eq isa BaseModelicaAlgorithmSection && eq.initial
            push!(initial_algorithms, eq)
            continue
        end
        when_eq = as_when_equation(eq)
        isnothing(when_eq) ? push!(regular_equations, eq) : push!(when_equation_list, when_eq)
    end

    # Flatten regular equations - some (like if-equations) return lists
    eqs = []
    for eq in regular_equations
        eq_obj = eval_AST(eq)
        if isa(eq_obj, Vector)
            # If-equations return a vector of equations
            append!(eqs, eq_obj)
        elseif !isnothing(eq_obj)
            push!(eqs, eq_obj)
        end
    end

    when_clause_list = WhenClause[]
    for (chain, when_eq) in enumerate(when_equation_list)
        append!(when_clause_list, when_clauses(when_eq, chain))
    end

    #vars_and_pars = merge(Dict(vars .=> vars), Dict(pars .=> pars))
    #println(vars_and_pars)
    #eqs = [substitute(x,vars_and_pars) for x in eqs]

    # Apply initial equations:
    # When free parameters are present, ALL initial equations must go into initialization_eqs
    # so they collectively constrain the initialization system that solves for the free params.
    # When no free parameters exist, regular variables use setdefault (simpler, more efficient).
    # Derivative LHS like der(x) always go to initialization_eqs (can't be setdefault).
    initialization_eqs = Equation[]
    has_free_params = !isempty(free_parameter_names)
    # `pre(v) = value` / `v = value` for a discrete v sets the start value of v
    assignments, initial_assertions = with_eval_mode(:initial) do
        initial_algorithm_assignments(initial_algorithms, composition.annotation)
    end
    for (var, value) in assignments
        name = symbol_name(var)
        if name in discrete_variable_names && value isa Number
            discrete_starts[name] = value
        elseif haskey(relation_boolean_syms, name) && value isa Bool
            relation_boolean_starts[name] = value ? 1.0 : 0.0
        else
            push!(initialization_eqs, var ~ value)
        end
    end
    initial_equations = filter(initial_equations) do eq
        # ANTLR stores initial for/if-equations directly; the direct-assignment
        # helpers below expect a simple equation wrapped in AnyEquation.
        inner = inner_equation(eq.equation)
        inner isa BaseModelicaSimpleEquation || return true
        array_discrete_initial!(discrete_starts, eq) && return false
        name = discrete_initial_target(eq)
        isnothing(name) && return true
        value = with_eval_mode(:initial) do
            eval_AST(inner.rhs)
        end
        if haskey(relation_boolean_syms, name)
            value isa Bool || return true
            relation_boolean_starts[name] = value ? 1.0 : 0.0
        else
            discrete_starts[name] = value
        end
        return false
    end
    initial_values = with_eval_mode(:initial) do
        [eval_AST(eq) for eq in initial_equations]
    end
    for pairs in initial_values
        for (var, value) in pairs
            set_discrete_initial!(discrete_starts, var, value) && continue
            found = false
            for (name, sym) in variable_map
                if isequal(sym, var)
                    found = true
                    if has_free_params
                        push!(initialization_eqs, sym ~ value)
                    else
                        new_sym = ModelingToolkitBase.setdefault(sym, value)
                        variable_map[name] = new_sym
                        idx = findfirst(v -> isequal(v, sym), vars)
                        !isnothing(idx) && (vars[idx] = new_sym)
                    end
                    break
                end
            end
            if !found
                # LHS not in variable_map (e.g. der(x)) → initialization constraint
                push!(initialization_eqs, var ~ value)
            end
        end
    end

    if !isempty(if_condition_parameter_names)
        model_name = class_specifier.name
        model_name isa BaseModelicaIdentifier && (model_name = model_name.name)
        # Symbols already occur in equations and binding expressions. Retain those
        # symbols and warn: MTK also permits remake of parameters marked non-tunable.
        @warn "BaseModelica model '$model_name': parameters $(quoted_names(sort!(collect(if_condition_parameter_names)))) select unbalanced if-equation branches at load time; changing them with remake does not update the equation structure, reload the model to change them"
    end

    # Pass 4: Apply explicit guess values from parameter equations.
    for param_eq in parameter_equations
        name = scalar_element_name(param_eq.component_reference)
        isnothing(name) && unsupported("guess value of an array slice")
        var = variable_map[name]
        value = eval_AST(param_eq.expression)
        variable_map[name] = ModelingToolkitBase.setguess(var, value)
        idx = findfirst(v -> SymbolicIndexingInterface.getname(v) == name, vars)
        !isnothing(idx) && (vars[idx] = variable_map[name])
    end

    # Booleans defined by an equation (`off = s < 0`), see relation_booleans.jl
    blocks = when_blocks(when_clause_list)
    booleans = lower_relation_booleans(Equation[declaration_eqs..., eqs...], class_specifier.name; blocks)
    real_eqs = booleans.equations

    # Collect all parameters from variable_map after all passes have applied defaults.
    # Both regular @parameters and @discretes symbols have PARAMETER type, so this
    # captures them all — including discrete variables that only appear in callbacks
    # and would be missed by auto-detection from equations.
    all_pars = Any[
        variable_map[name] for name in declared_names
            if haskey(variable_map, name) && !is_inlined(variable_map[name]) &&
            ModelingToolkitBase.isparameter(variable_map[name])
    ]
    append!(all_pars, booleans.parameters)

    # Build bindings for free parameters (fixed=false): p => missing signals MTK to
    # solve for p during initialization using initialization_eqs.
    bindings = Pair[
        variable_map[name] => missing for name in declared_names if name in free_parameter_names
    ]
    append!(bindings, booleans.bindings)

    # Lower when-equations through the discrete backend.
    event_eqs, event_vars = array_event_view(real_eqs, vars, blocks)
    discrete_model = DiscreteModel(
        event_eqs, copy(event_vars), differentiated_variables(event_eqs),
        array_discrete_starts(discrete_starts),
        blocks
    )
    backend isa MTKEventsBackend &&
        validate_relation_boolean_body_reads(discrete_model, booleans.definitions)
    lowered = lower_discrete(backend, discrete_model)
    real_eqs = lowered.equations
    append!(all_pars, lowered.parameters)

    # Discrete variables that the backend represents as (clocked) unknowns
    for name in discrete_variable_names
        sym = variable_map[name]
        ModelingToolkitBase.isparameter(sym) || push!(vars, sym)
    end

    event_callbacks = vcat(lowered.discrete_events, event_iteration_callbacks(booleans, lowered))
    append!(event_callbacks, initial_assertion_events(initial_assertions, class_specifier.name))

    @named sys = System(
        real_eqs, t, vars, all_pars;
        continuous_events = array_callbacks(vcat(lowered.continuous_events, booleans.continuous_events)),
        discrete_events = array_callbacks(event_callbacks),
        initialization_eqs = vcat(
            initialization_eqs, lowered.initialization_eqs, booleans.initialization_eqs
        ),
        initial_conditions = array_initial_conditions(lowered.initial_conditions),
        bindings = bindings,
        state_priorities = state_priorities,
        # One vector: ModelingToolkit reads a scalar tstop as a period
        tstops = isempty(tstops_collection) ? [] : Any[copy(tstops_collection)],
    )
    experiment = parse_experiment_annotation(composition.annotation)
    if !isnothing(experiment)
        sys = SymbolicUtils.setmetadata(sys, ExperimentAnnotation, experiment)
    end
    if simplify === true
        return compile_system(backend, sys)
    elseif simplify === false
        return sys
    else
        compiled = simplify(sys)
        return backend isa MTKEventsBackend ? check_algebraic_crossings(compiled) : compiled
    end
end

"""
    initial_algorithm_assignments(sections, annotation)

Run `initial algorithm` sections, which may only contain assignments and `assert` calls.
Returns the final `variable => value` pairs and the assertions as
`(condition, message, level)` tuples. Statements are sequential, so later statements see
earlier results, and `time` is the experiment start time (0 without an experiment
annotation).
"""
function initial_algorithm_assignments(sections, annotation)
    assertions = Tuple{Any, String, Symbol}[]
    isempty(sections) && return Pair[], assertions
    experiment = parse_experiment_annotation(annotation)
    scope = Dict{Symbol, Any}(:time => isnothing(experiment) ? 0.0 : experiment.StartTime)
    assigned = Symbol[]
    with_local_scope(scope) do
        for section in sections, st in section.statements
            if st isa BaseModelicaFunctionCall && function_call_name(st) == "assert"
                push!(assertions, evaluate_assert(st))
                continue
            end
            st isa BaseModelicaAssignment ||
                unsupported("initial algorithm sections may only contain assignments and assert calls")
            length(reference_parts(st.target)[1]) == 1 ||
                unsupported("initial algorithm assigns record component `$(st.target)`")
            name = scalar_element_name(st.target)
            isnothing(name) && unsupported("initial algorithm assigns a whole array or slice")
            haskey(variable_map, name) ||
                unsupported("initial algorithm assigns unknown variable `$name`")
            scope[name] = eval_AST(st.expression)
            name in assigned || push!(assigned, name)
        end
    end
    return Pair[variable_map[name] => scope[name] for name in assigned], assertions
end

# `(condition, message, level)` of `assert(condition, message[, level])`; `level` is
# `:warning` for `AssertionLevel.warning` and `:error` otherwise.
function evaluate_assert(call::BaseModelicaFunctionCall)
    args = call.args.args
    length(args) in (2, 3) || unsupported("assert expects `assert(condition, message[, level])`")
    condition = eval_AST(args[1])
    message = try
        eval_AST(args[2])
    catch
        nothing  # e.g. a message built with String(...)
    end
    message isa AbstractString || (message = "(message could not be evaluated)")
    level = length(args) == 3 && args[3] isa BaseModelicaComponentReference &&
        args[3].ref_list[end].name == "warning" ? :warning : :error
    return condition, String(message), level
end

"""
    InitialAssertions

The `initialize` affect that checks the `assert` calls of the initial algorithm once the
model is initialized: a failed assertion of level error throws, one of level warning logs a
warning. The conditions are observed in order, `messages[i]` and `levels[i]` belong to the
i-th.
"""
struct InitialAssertions
    model::String
    messages::Vector{String}
    levels::Vector{Symbol}
end

function (check::InitialAssertions)(modified, observed, ctx, integ)
    for (holds, message, level) in zip(values(observed), check.messages, check.levels)
        Bool(holds) && continue
        text = "BaseModelica model '$(check.model)': assertion of the initial algorithm failed at initialization: $message"
        level === :error ? error(text) : @warn(text)
    end
    return (;)
end

# A discrete callback that never fires, whose `initialize` affect checks `assertions`.
# Assertions that hold at translation are dropped, ones that fail there throw or warn.
function initial_assertion_events(assertions, model_name)
    model_name isa BaseModelicaIdentifier && (model_name = model_name.name)
    pending = filter(assertions) do (condition, message, level)
        value = concrete_value(condition)
        isnothing(value) && return true
        value == true && return false
        text = "BaseModelica model '$model_name': assertion of the initial algorithm fails: $message"
        level === :error ? throw(ArgumentError(text)) : @warn(text)
        return false
    end
    isempty(pending) && return Any[]
    check = InitialAssertions(String(model_name), [a[2] for a in pending], [a[3] for a in pending])
    observed = NamedTuple{Tuple(Symbol(:c, i) for i in eachindex(pending))}(
        Tuple(Num(a[1]) for a in pending)
    )
    return Any[
        ModelingToolkitBase.SymbolicDiscreteCallback(
            Float64[], nothing;
            initialize = ModelingToolkitBase.ImperativeAffect(check; observed)
        ),
    ]
end

# The discrete variable or Boolean (see relation_booleans.jl) named by the left-hand side of
# an initial equation `pre(v) = ...` or `v = ...`, or nothing if the equation does not
# initialize one.
function discrete_initial_target(eq::BaseModelicaInitialEquation)
    inner = inner_equation(eq.equation)
    inner isa BaseModelicaSimpleEquation || return nothing
    lhs = inner.lhs
    if lhs isa BaseModelicaFunctionCall && function_call_name(lhs) == "pre"
        lhs = only(lhs.args.args)
    end
    lhs isa BaseModelicaComponentReference || return nothing
    name = scalar_element_name(lhs)
    isnothing(name) && return nothing
    return name in discrete_variable_names || haskey(relation_boolean_syms, name) ? name :
        nothing
end

# Initial structured equations and scalarized whole-array equations reach this point
# as element assignments. They must update the backend's starts, just like a direct
# `pre(v) = value`, rather than set defaults that backend initialization overwrites.
function set_discrete_initial!(starts, var, value)
    # Equation fields are unwrapped symbolic values; symbol_name expects Num.
    var = Symbolics.wrap(var)
    name = symbol_name(var)
    name in discrete_variable_names || return false
    value = something(concrete_value(value), Symbolics.wrap(value))
    if haskey(kept_array_dims, name)
        array = variable_map[name]
        if !isequal(var, array)
            index = findfirst(isequal(var), collect(array))
            isnothing(index) && return false
            values = Num.(collect(array_attribute(name, starts[name])))
            values[index] = value
            numbers = map(concrete_value, values)
            starts[name] = all(!isnothing, numbers) ? typed_numeric_array(numbers) : values
            return true
        end
    end
    starts[name] = value
    return true
end

function eval_AST(package::BaseModelicaPackage; kwargs...)
    empty!(enum_map)
    # Register built-in StateSelect enumeration so StateSelect.prefer etc. resolve correctly.
    enum_map["StateSelect"] = Dict(
        :never => Int(StateSelectNever),
        :avoid => Int(StateSelectAvoid),
        :default => Int(StateSelectDefault),
        :prefer => Int(StateSelectPrefer),
        :always => Int(StateSelectAlways),
    )
    for class_def in package.class_defs
        if class_def isa BaseModelicaClassDefinition && class_def.class isa BaseModelicaEnumeration
            enum = class_def.class
            enum_map[enum.name] = Dict(Symbol(v) => i for (i, v) in enumerate(enum.values))
        end
    end
    register_record_types!(package.class_defs)
    register_user_functions!(package.class_defs)
    model = package.model
    return eval_AST(model; kwargs...)
end

function eval_AST(function_args::BaseModelicaFunctionArgs)
    args = function_args.args
    return eval_AST.([args...])
end

function eval_AST(function_call::BaseModelicaFunctionCall)
    name = function_call_name(function_call)
    haskey(record_type_map, name) && return record_constructor(name, function_call.args.args)
    user_function = get(user_function_map, name, nothing)
    if !isnothing(user_function)
        return inline_user_function(user_function, function_call.args.args)
    end
    if function_call.func_name isa BaseModelicaComponentReference
        function_name = Symbol(function_call.func_name.ref_list[1].name)
    else
        function_name = Symbol(function_call.func_name.name)
    end

    # Skip assert calls - they are verification statements, not equations
    if function_name == :assert
        return nothing
    end

    if function_name == :pre
        arg = eval_AST(only(function_call.args.args))
        return is_array(arg) ? map(apply_pre, collect(arg)) : apply_pre(arg)
    end

    haskey(function_map, function_name) ||
        unsupported("function `$function_name` is not supported")
    # Constructor sizes are structural even when the array's elements are symbolic.
    args = if function_name in (:zeros, :ones, :fill, :identity)
        [
            function_name == :fill && i == 1 ? eval_AST(arg) : eval_dimension(arg)
                for (i, arg) in enumerate(function_call.args.args)
        ]
    else
        eval_AST(function_call.args)
    end
    if EVAL_MODE[] === :condition && function_name in (:floor, :integer, :ceil, :div, :mod, :rem) &&
            any(varies_continuously, args)
        unsupported("event-generating `$function_name(...)` with continuous arguments in a when-condition is not supported")
    end
    return call_builtin(function_name, args)
end

function eval_AST(comp_reference::BaseModelicaComponentReference)
    parts = comp_reference.ref_list
    first_sub = findfirst(x -> x isa BaseModelicaArraySubscripts, parts)
    n = isnothing(first_sub) ? length(parts) : first_sub - 1
    value = reference_value([String(x.name) for x in parts[1:n]])
    for part in parts[(n + 1):end]
        value = part isa BaseModelicaArraySubscripts ? apply_subscripts(value, part.subscripts) :
            record_field(value, Symbol(part.name))
    end
    return value
end

# Resolve the longest declared prefix first. A quoted flattened name (`'r.x'`) and a
# dotted reference (`r.x`) both find the same field, while function records stay values.
function reference_value(names)
    scope = LOCAL_SCOPE[]
    if !isnothing(scope) && haskey(scope, Symbol(first(names)))
        value = function_local_value(scope[Symbol(first(names))], first(names))
        for field in names[2:end]
            value = record_field(value, Symbol(field))
        end
        return value
    end
    for n in length(names):-1:1
        key = Symbol(join(names[1:n], "."))
        found = true
        value = if !isnothing(scope) && haskey(scope, key)
            function_local_value(scope[key], key)
        elseif haskey(record_components, key) || haskey(record_arrays, key)
            record_component_value(key)
        elseif haskey(array_components, key)
            element_array(key)
        elseif haskey(variable_map, key)
            variable_map[key]
        elseif n == 1 && key == :time
            t
        elseif n == 1 && key == :end
            end_size()
        else
            found = false
            nothing
        end
        if found
            for field in names[(n + 1):end]
                value = record_field(value, Symbol(field))
            end
            return value
        end
    end
    if length(names) == 2 && haskey(enum_map, names[1])
        values = enum_map[names[1]]
        key = Symbol(names[2])
        haskey(values, key) || unsupported("enumeration `$(names[1])` has no member `$key`")
        return values[key]
    end
    length(names) > 1 && unsupported("unknown record/component `$(join(names, "."))`")
    return nothing
end

"""
    baseModelica_to_ModelingToolkit(package; discrete_backend = :auto, simplify = true, arrays = :scalarize)

Convert a parsed `BaseModelicaPackage` into a ModelingToolkit `System`. See
[`parse_basemodelica`](@ref) for the keyword arguments.
"""
function baseModelica_to_ModelingToolkit(
        package::BaseModelicaPackage; discrete_backend = :auto, simplify = true, arrays = :scalarize
    )
    validate_array_mode(arrays)
    backend = select_backend(discrete_backend)
    return @lock CONVERSION_LOCK eval_AST(package; backend, simplify, arrays)
end

# The conversion keeps its state in module-level globals (`variable_map`, ...), so
# conversions running on several threads at once would overwrite each other's state.
const CONVERSION_LOCK = ReentrantLock()
