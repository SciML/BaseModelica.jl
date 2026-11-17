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

function modelica_type_to_julia(type_str::String)
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
    inner_eq = eq.equation.equation
    # Skip tuple-return assignments like (a, b, , ) = func(...) — not supported
    inner_eq.lhs isa Vector && return Dict()
    lhs = eval_AST(inner_eq.lhs)
    isnothing(lhs) && return Dict()
    rhs = eval_AST(inner_eq.rhs)
    isnothing(rhs) && return Dict()
    return Dict(eq.lhs => eq.rhs for eq in vcat(equate(lhs, rhs)))
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
        eq_obj = isa(eq, BaseModelicaAnyEquation) ? eval_AST(eq.equation) : eval_AST(eq)
        if eq_obj isa Equation
            push!(result, eq_obj)
        elseif eq_obj isa AbstractVector
            append!(result, eq_obj)
        end
    end
    return result
end

function eval_AST(if_eq::BaseModelicaIfEquation)
    # Convert if-equation to nested ifelse calls
    # Structure: ifs[i] contains condition, thens[i] contains a list of equations for that branch
    # If length(thens) > length(ifs), thens[end] is the else branch (no condition)

    has_else = length(if_eq.thens) > length(if_eq.ifs)

    # Time events of the conditions (e.g. `time < 1e-5`), see collect_time_events!
    foreach(cond -> collect_time_events!(eval_AST(cond)), if_eq.ifs)

    branches = [branch_equations(branch) for branch in if_eq.thens]

    # Helper to extract RHS for a specific variable from a branch's equation list
    function get_rhs_for_var(var_lhs, branch)
        idx = findfirst(eq -> isequal(eq.lhs, var_lhs), branch)
        return isnothing(idx) ? nothing : branch[idx].rhs
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
            if has_else
                rhs = get_rhs_for_var(var_lhs, branches[end])
                if isnothing(rhs)
                    error("Variable $var_lhs not assigned in else branch")
                end
                return rhs
            else
                error("If-equation has no else branch and exhausted all conditions for $var_lhs")
            end
        end

        condition = logical_operand(eval_AST(if_eq.ifs[idx]))
        rhs = get_rhs_for_var(var_lhs, branches[idx])

        if isnothing(rhs)
            error("Variable $var_lhs not assigned in branch $idx")
        end

        if idx == length(if_eq.ifs) && !has_else
            # Last conditional branch with no else clause
            # In well-formed Modelica, this should be elseif true (always true)
            return ifelse(condition, rhs, zero(rhs))
        else
            else_expr = build_ifelse_for_var(var_lhs, idx + 1)
            return ifelse(condition, rhs, else_expr)
        end
    end

    result_equations = []
    for var in lhs_vars
        ifelse_rhs = build_ifelse_for_var(var)
        push!(result_equations, var ~ ifelse_rhs)
    end

    return result_equations
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
        simplify = true
    )
    empty!(variable_map)
    empty!(parameter_val_map)
    empty!(discrete_variable_names)
    empty!(integer_variable_names)
    empty!(free_parameter_names)
    empty!(evaluated_parameter_names)
    empty!(tstops_collection)
    empty!(bool_comparison_names)
    empty!(relation_boolean_syms)
    empty!(relation_boolean_history)
    empty!(relation_boolean_starts)

    class_specifier = model.long_class_specifier

    composition = class_specifier.composition

    # Array components become one scalar component per element, see arrays.jl
    components = scalarize_components(composition.components)
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

    vars = Num[]
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
            discrete_starts[name] = something(
                start_value, comp.type_specifier.type == "Boolean" ? false : 0.0
            )
            continue
        elseif name in bool_comparison_names
            # Every parameter symbol now exists, including forward references. Keep the
            # start symbolic so initialization (and remake) uses the current parameters.
            start_value = get_class_modification_value(declaration.modification, "start")
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
                variable_map[name] = ModelingToolkitBase.setguess(var, 0.0)
            end
            idx = findfirst(v -> SymbolicIndexingInterface.getname(v) == name, vars)
            !isnothing(idx) && (vars[idx] = variable_map[name])

            # stateSelect attribute: StateSelect.never/avoid/default/prefer/always → Int 1–5
            ss_value = get_class_modification_value(declaration.modification, "stateSelect")
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
        name = discrete_initial_target(eq)
        isnothing(name) && return true
        value = with_eval_mode(:initial) do
            eval_AST(eq.equation.equation.rhs)
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
    for dictionary in initial_values
        for (var, value) in dictionary
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
    booleans = lower_relation_booleans(Equation[declaration_eqs..., eqs...], class_specifier.name)
    real_eqs = booleans.equations

    # Collect all parameters from variable_map after all passes have applied defaults.
    # Both regular @parameters and @discretes symbols have PARAMETER type, so this
    # captures them all — including discrete variables that only appear in callbacks
    # and would be missed by auto-detection from equations.
    all_pars = Num[
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
    discrete_model = DiscreteModel(
        real_eqs, copy(vars), differentiated_variables(real_eqs),
        Pair{Any, Any}[variable_map[name] => discrete_starts[name] for name in sort!(collect(keys(discrete_starts)))],
        when_blocks(when_clause_list)
    )
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
        continuous_events = vcat(lowered.continuous_events, booleans.continuous_events),
        discrete_events = event_callbacks,
        initialization_eqs = vcat(
            initialization_eqs, lowered.initialization_eqs, booleans.initialization_eqs
        ),
        initial_conditions = Dict(lowered.initial_conditions),
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
    inner = eq.equation.equation
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
    register_user_functions!(package.class_defs)
    for class_def in package.class_defs
        if class_def isa BaseModelicaClassDefinition && class_def.class isa BaseModelicaEnumeration
            enum = class_def.class
            enum_map[enum.name] = Dict(Symbol(v) => i for (i, v) in enumerate(enum.values))
        end
    end
    model = package.model
    return eval_AST(model; kwargs...)
end

function eval_AST(function_args::BaseModelicaFunctionArgs)
    args = function_args.args
    return eval_AST.([args...])
end

function eval_AST(function_call::BaseModelicaFunctionCall)
    user_function = get(user_function_map, function_call_name(function_call), nothing)
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
        return is_array(arg) ? map(apply_pre, arg) : apply_pre(arg)
    end

    haskey(function_map, function_name) ||
        unsupported("function `$function_name` is not supported")
    args = eval_AST(function_call.args)
    if EVAL_MODE[] === :condition && function_name in (:floor, :integer, :ceil, :div, :mod, :rem) &&
            any(varies_continuously, args)
        unsupported("event-generating `$function_name(...)` with continuous arguments in a when-condition is not supported")
    end
    return call_builtin(function_name, args)
end

function eval_AST(comp_reference::BaseModelicaComponentReference)
    names, subscripts = reference_parts(comp_reference)
    value = reference_value(names)
    isnothing(subscripts) && return value
    isnothing(value) && unsupported("unknown variable `$(names[1])` in `$(names[1])[...]`")
    return apply_subscripts(value, subscripts)
end

# The value of the reference to `names` (`a.b` is `["a", "b"]`), before subscripts
function reference_value(names)
    ref_name = Symbol(names[1])

    # Function-local variables and for-loop indices
    scope = LOCAL_SCOPE[]
    if !isnothing(scope) && length(names) == 1 && haskey(scope, ref_name)
        return scope[ref_name]
    end

    # Handle special built-in variables
    if ref_name == :time
        return t  # Map Modelica 'time' to ModelingToolkit 't'
    end
    if ref_name == :AssertionLevel
        return nothing
    end
    # `end` inside a subscript (the :julia parser reads it as a component reference)
    if ref_name == :end && length(names) == 1 && !haskey(variable_map, :end)
        return end_size()
    end

    # Handle enum value references: EnumType.ValueName → integer
    if length(names) >= 2
        type_name = names[1]
        value_name = Symbol(names[2])
        if haskey(enum_map, type_name) && haskey(enum_map[type_name], value_name)
            return enum_map[type_name][value_name]
        end
    end

    # Array components evaluate to an array of their scalarized elements
    if length(names) == 1 && haskey(array_components, ref_name)
        return element_array(ref_name)
    end

    return get(variable_map, ref_name, nothing)
end

"""
    baseModelica_to_ModelingToolkit(package; discrete_backend = :auto, simplify = true)

Convert a parsed `BaseModelicaPackage` into a ModelingToolkit `System`. See
[`parse_basemodelica`](@ref) for the keyword arguments.
"""
function baseModelica_to_ModelingToolkit(
        package::BaseModelicaPackage; discrete_backend = :auto, simplify = true
    )
    backend = select_backend(discrete_backend)
    return @lock CONVERSION_LOCK eval_AST(package; backend, simplify)
end

# The conversion keeps its state in module-level globals (`variable_map`, ...), so
# conversions running on several threads at once would overwrite each other's state.
const CONVERSION_LOCK = ReentrantLock()
