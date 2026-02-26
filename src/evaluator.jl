# function to convert "AST" to ModelingToolkit
using ModelingToolkit: t_nounits as t, D_nounits as D

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
            BaseModelicaFactor(base, exp) => (f(base))^f(exp)
            BaseModelicaSum(left, right) => (f(left)) + (f(right))
            BaseModelicaMinus(left, right) => f(left) - f(right)
            BaseModelicaUnaryMinus(operand) => -f(operand)
            BaseModelicaProd(left, right) => f(left) * f(right)
            BaseModelicaDivide(left, right) => f(left) / f(right)
            BaseModelicaNot(relation) => !(f(relation))
            BaseModelicaAnd(left, right) => f(left) && f(right)
            BaseModelicaOr(left, right) => f(left) || f(right)
            BaseModelicaLEQ(left, right) => f(left) <= f(right)
            BaseModelicaGEQ(left, right) => f(left) >= f(right)
            BaseModelicaLessThan(left, right) => f(left) < f(right)
            BaseModelicaGreaterThan(left, right) => f(left) > f(right)
            BaseModelicaEQ(left, right) => f(left) == f(right)
            BaseModelicaNEQ(left, right) => f(left) != f(right)
            _ => nothing
        end
    end
end

function eval_AST(if_expr::BaseModelicaIfExpression)
    # Convert if-expression to nested ifelse calls
    # Structure: conditions[i] with expressions[i] for if/elseif
    #           expressions[end] is the else value (no condition)

    # Build nested ifelse from right to left
    function build_nested_ifelse(idx = 1)
        if idx > length(if_expr.conditions)
            # We've gone past all conditions, return the else value
            return eval_AST(if_expr.expressions[end])
        end

        condition = eval_AST(if_expr.conditions[idx])
        then_value = eval_AST(if_expr.expressions[idx])
        else_value = build_nested_ifelse(idx + 1)
        return ifelse(condition, then_value, else_value)
    end

    return build_nested_ifelse()
end

include("maps.jl")

function eval_AST(eq::BaseModelicaInitialEquation)
    inner_eq = eq.equation.equation
    return Dict(eval_AST(inner_eq.lhs) => eval_AST(inner_eq.rhs))
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
    if eq.lhs isa BaseModelicaIfEquation
        return eval_AST(eq.lhs)
    end
    lhs = eval_AST(eq.lhs)
    rhs = eval_AST(eq.rhs)

    # If either side is nothing (e.g., from assert or other non-equation statements),
    # return nothing to filter out this equation
    if isnothing(lhs) || isnothing(rhs)
        return nothing
    end

    return lhs ~ rhs
end

function eval_AST(if_eq::BaseModelicaIfEquation)
    # Convert if-equation to nested ifelse calls
    # Structure: ifs[i] contains condition, thens[i] contains a list of equations for that branch
    # If length(thens) > length(ifs), thens[end] is the else branch (no condition)

    has_else = length(if_eq.thens) > length(if_eq.ifs)

    # Helper to extract RHS for a specific variable from a branch's equation list
    function get_rhs_for_var(var_lhs, branch_equations)
        equations_to_check = isa(branch_equations, AbstractArray) ? branch_equations :
            [branch_equations]
        for eq in equations_to_check
            eq_obj = isa(eq, BaseModelicaAnyEquation) ? eval_AST(eq.equation) : eval_AST(eq)
            if !isnothing(eq_obj) && isa(eq_obj, Equation) && isequal(eq_obj.lhs, var_lhs)
                return eq_obj.rhs
            end
        end
        return nothing
    end

    # Collect all unique LHS variables across all branches
    lhs_vars = Set()
    for eq_list in if_eq.thens
        equations_to_check = isa(eq_list, AbstractArray) ? eq_list : [eq_list]
        for eq in equations_to_check
            eq_obj = isa(eq, BaseModelicaAnyEquation) ? eval_AST(eq.equation) : eval_AST(eq)
            if !isnothing(eq_obj) && isa(eq_obj, Equation)
                push!(lhs_vars, eq_obj.lhs)
            end
        end
    end

    # Build nested ifelse for each variable
    function build_ifelse_for_var(var_lhs, idx = 1)
        if idx > length(if_eq.ifs)
            # Past all conditions
            if has_else
                rhs = get_rhs_for_var(var_lhs, if_eq.thens[end])
                if isnothing(rhs)
                    error("Variable $var_lhs not assigned in else branch")
                end
                return rhs
            else
                error("If-equation has no else branch and exhausted all conditions for $var_lhs")
            end
        end

        condition = eval_AST(if_eq.ifs[idx])
        rhs = get_rhs_for_var(var_lhs, if_eq.thens[idx])

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

function eval_AST(x::String)
    return x
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
        variable_map[name] = only(@parameters($name))

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

function eval_AST(model::BaseModelicaModel)
    empty!(variable_map)
    empty!(parameter_val_map)

    class_specifier = model.long_class_specifier
    model_name = class_specifier.name
    description = class_specifier.description

    composition = class_specifier.composition

    components = composition.components
    equations = composition.equations
    initial_equations = composition.initial_equations
    parameter_equations = composition.parameter_equations

    # Two-pass approach for components:
    # Pass 1: Create all symbols in variable_map (without evaluating parameter values)
    # Pass 2: Evaluate parameter values (now all symbols exist for cross-references)

    vars = Num[]
    pars = Num[]
    declaration_eqs = []

    # Pass 1: Create all variables and parameters in variable_map
    for comp in components
        name = Symbol(comp.component_list[1].declaration.ident[1].name)
        type_prefix = comp.type_prefix.dpc

        if type_prefix == "parameter"
            variable_map[name] = only(@parameters($name))
            push!(pars, variable_map[name])
        elseif type_prefix == "constant"
            variable_map[name] = only(@parameters($name))
            push!(pars, variable_map[name])
        elseif isnothing(type_prefix)
            variable_map[name] = only(@variables($name(t)))
            push!(vars, variable_map[name])
        end
    end

    # Pass 2: Evaluate parameter values and handle start/fixed for variables
    for comp in components
        type_prefix = comp.type_prefix.dpc
        name = Symbol(comp.component_list[1].declaration.ident[1].name)
        declaration = comp.component_list[1].declaration

        if type_prefix == "parameter" || type_prefix == "constant"
            # Collect into parameter_val_map; setdefault is applied in pass 3 below.
            # We cannot call setdefault here because setdefault returns a NEW symbol
            # object. A forward reference (e.g. V.signalSource.startTime = V.startTime
            # where V.startTime is declared later) would embed the OLD stale symbol in
            # the expression — MTK cannot resolve it. Pass 3 substitutes all references
            # to concrete values first, then setdefault is called once with clean values.
            if !isnothing(declaration.modification) && !isempty(declaration.modification)
                modification = declaration.modification[1]
                if !isnothing(modification.expr) && !isempty(modification.expr)
                    value_expr = modification.expr[end]
                    parameter_val_map[variable_map[name]] = eval_AST(value_expr)
                end
            end
        elseif isnothing(type_prefix)
            # This is a variable - check for start and fixed attributes
            start_value = get_class_modification_value(declaration.modification, "start")
            fixed_value = get_class_modification_value(declaration.modification, "fixed")

            if !isnothing(start_value)
                var = variable_map[name]
                # If fixed=true, use setdefault for initial condition
                # Otherwise use setguess for guess value
                is_fixed = !isnothing(fixed_value) &&
                    (fixed_value === true || fixed_value == true)
                if is_fixed
                    variable_map[name] = ModelingToolkit.setdefault(var, start_value)
                    idx = findfirst(v -> ModelingToolkit.getname(v) == name, vars)
                    vars[idx] = variable_map[name]
                else
                    variable_map[name] = ModelingToolkit.setguess(var, start_value)
                    idx = findfirst(v -> ModelingToolkit.getname(v) == name, vars)
                    vars[idx] = variable_map[name]
                end
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

    # Pass 3: Substitute parameter cross-references to get concrete values.
    # e.g. V.signalSource.startTime = V.startTime, V.startTime = 1.0
    # After substitution: V.signalSource.startTime = 1.0
    # TODO: this could probably be replaced with the bindings system?
    for (param, value) in parameter_val_map
        parameter_val_map[param] = substitute(value, parameter_val_map)
    end

    # Pass 3.5: Apply concrete parameter values via setdefault.
    # Done after pass 3 so we always call setdefault with a resolved concrete value,
    # never with an expression containing a stale pre-setdefault symbol reference.
    for name in collect(keys(variable_map))
        sym = variable_map[name]
        val = get(parameter_val_map, sym, nothing)
        if !isnothing(val)
            variable_map[name] = ModelingToolkit.setdefault(sym, val)
        end
    end

    # Flatten equations - some equations (like if-equations) return lists
    eqs_raw = [eval_AST(eq) for eq in equations]
    real_eqs_raw = [eq for eq in eqs_raw] # Weird type stuff
    eqs = []
    for eq in real_eqs_raw
        if eq !== nothing
            if isa(eq, Vector)
                # If-equations return a vector of equations
                append!(eqs, eq)
            else
                # Regular equations return a single equation
                push!(eqs, eq)
            end
        end
    end

    #vars_and_pars = merge(Dict(vars .=> vars), Dict(pars .=> pars))
    #println(vars_and_pars)
    #eqs = [substitute(x,vars_and_pars) for x in eqs]

    # Apply initial equations as setdefault on the respective variables.
    # The key in each dict is the symbolic variable, the value is the initial condition.
    # Might be able to use the bindings mechanism here in the future?
    for dictionary in [eval_AST(eq) for eq in initial_equations]
        for (var, value) in dictionary
            for (name, sym) in variable_map
                if isequal(sym, var)
                    new_sym = ModelingToolkit.setdefault(sym, value)
                    variable_map[name] = new_sym
                    idx = findfirst(v -> isequal(v, sym), vars)
                    !isnothing(idx) && (vars[idx] = new_sym)
                    break
                end
            end
        end
    end

    # Pass 4: Apply explicit guess values from parameter equations.
    for param_eq in parameter_equations
        name = Symbol(param_eq.component_reference.ref_list[1].name)
        var = variable_map[name]
        value = eval_AST(param_eq.expression)
        variable_map[name] = ModelingToolkit.setguess(var, value)
        idx = findfirst(v -> ModelingToolkit.getname(v) == name, vars)
        !isnothing(idx) && (vars[idx] = variable_map[name])
    end

    real_eqs = [declaration_eqs..., eqs...] # Weird type stuff
    @named sys = System(real_eqs, t)
    return mtkcompile(sys)
end

function eval_AST(package::BaseModelicaPackage)
    model = package.model
    return eval_AST(model)
end

function eval_AST(function_args::BaseModelicaFunctionArgs)
    args = function_args.args
    return eval_AST.([args...])
end

function eval_AST(function_call::BaseModelicaFunctionCall)
    if function_call.func_name isa BaseModelicaComponentReference
        function_name = Symbol(function_call.func_name.ref_list[1].name)
    else
        function_name = Symbol(function_call.func_name.name)
    end

    # Skip assert calls - they are verification statements, not equations
    if function_name == :assert
        return nothing
    end

    args = eval_AST(function_call.args)
    return function_map[function_name](args)
end

function eval_AST(comp_reference::BaseModelicaComponentReference)
    #will need to eventually account for array references and dot references...
    #for now only does direct references to variables
    ref_name = Symbol(comp_reference.ref_list[1].name)

    # Handle special built-in variables
    if ref_name == :time
        return t  # Map Modelica 'time' to ModelingToolkit 't'
    end
    if ref_name == :AssertionLevel
        return nothing
    else
        return variable_map[ref_name]
    end
end

function baseModelica_to_ModelingToolkit(package::BaseModelicaPackage)
    return eval_AST(package)
end
