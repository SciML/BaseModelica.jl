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
    let f = eval_AST
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
    Dict(eval_AST(inner_eq.lhs) => eval_AST(inner_eq.rhs))
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

    lhs ~ rhs
end

function eval_AST(if_eq::BaseModelicaIfEquation)
    # Convert if-equation to nested ifelse calls
    # Structure: ifs[i] contains condition, thens[i] contains a list of equations for that branch

    # Process all equations in all branches to get the lhs variables
    # We assume all branches assign to the same variables
    # thens is a list of lists: thens[i] is a list of equations for branch i
    all_equations = []
    for eq_list in if_eq.thens
        # Each element in thens is a list of equations
        if isa(eq_list, AbstractArray)
            for eq in eq_list
                if isa(eq, BaseModelicaAnyEquation)
                    push!(all_equations, eval_AST(eq.equation))
                else
                    push!(all_equations, eval_AST(eq))
                end
            end
        else
            # Fallback for single equation
            if isa(eq_list, BaseModelicaAnyEquation)
                push!(all_equations, eval_AST(eq_list.equation))
            else
                push!(all_equations, eval_AST(eq_list))
            end
        end
    end

    # Build result equations by nesting ifelse calls from right to left
    # For each unique lhs variable, build an ifelse expression
    result_equations = []

    # Helper function to build nested ifelse for a single variable across all branches
    function build_ifelse_for_var(var_lhs, branch_idx = 1)
        if branch_idx > length(if_eq.ifs)
            # This shouldn't happen if the model is well-formed
            error("If-equation branches exhausted without finding assignment")
        end

        # Get the RHS for this variable in this branch
        eq_list = if_eq.thens[branch_idx]
        rhs_expr = nothing

        # Handle list of equations
        equations_to_check = isa(eq_list, AbstractArray) ? eq_list : [eq_list]
        for eq in equations_to_check
            eq_obj = isa(eq, BaseModelicaAnyEquation) ? eval_AST(eq.equation) : eval_AST(eq)
            if !isnothing(eq_obj) && isa(eq_obj, Equation)
                eq_lhs = eq_obj.lhs
                if isequal(eq_lhs, var_lhs)
                    rhs_expr = eq_obj.rhs
                    break
                end
            end
        end

        if isnothing(rhs_expr)
            error("Variable $var_lhs not assigned in branch $branch_idx")
        end

        # Get condition
        condition = eval_AST(if_eq.ifs[branch_idx])

        # Check if this is the last branch (else branch or last elseif)
        if branch_idx == length(if_eq.ifs)
            # Last branch - check if it's an else (no condition) or final elseif
            # In Modelica, else branches still have a marker in ifs, but we need to detect them
            # For now, assume if it's the last branch, use it as the else value
            if branch_idx == length(if_eq.thens)
                # This is a final else or final elseif
                return rhs_expr
            else
                # Final elseif with no else - would need default
                return ifelse(condition, rhs_expr, 0)  # Default to 0 if no else
            end
        else
            # Recursive case: condition ? rhs : build_ifelse_for_var(branch_idx + 1)
            else_expr = build_ifelse_for_var(var_lhs, branch_idx + 1)
            return ifelse(condition, rhs_expr, else_expr)
        end
    end

    # Extract unique lhs variables from all equations
    lhs_vars = Set()
    for eq in all_equations
        if !isnothing(eq) && isa(eq, Equation)
            push!(lhs_vars, eq.lhs)
        end
    end

    # Build ifelse expression for each variable

    for var in lhs_vars
        ifelse_rhs = build_ifelse_for_var(var)
        push!(result_equations, var ~ ifelse_rhs)
    end

    return result_equations
end

function eval_AST(x::String)
    x
end

function eval_AST(::Nothing)
    nothing
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
    class_specifier = model.long_class_specifier
    model_name = class_specifier.name
    description = class_specifier.description

    composition = class_specifier.composition

    components = composition.components
    equations = composition.equations
    initial_equations = composition.initial_equations

    # Two-pass approach for components:
    # Pass 1: Create all symbols in variable_map (without evaluating parameter values)
    # Pass 2: Evaluate parameter values (now all symbols exist for cross-references)

    vars = Num[]
    pars = Num[]

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
            # Extract parameter value from modification
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
        end
    end

    # Pass 3: Substitute parameter values to resolve symbolic references
    # This ensures parameters that reference other parameters get concrete numeric values
    for (param, value) in parameter_val_map
        parameter_val_map[param] = substitute(value, parameter_val_map)
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

    init_eqs = [eval_AST(eq) for eq in initial_equations]
    init_eqs_dict = Dict()

    # quick and dumb kind of
    for dictionary in init_eqs
        for (key, value) in dictionary
            init_eqs_dict[key] = value
        end
    end
    for (key, value) in init_eqs_dict
        init_eqs_dict[key] = substitute(value, parameter_val_map)
    end

    #vars,pars,eqs, init_eqs_dict

    defs = merge(init_eqs_dict, parameter_val_map)
    real_eqs = [eq for eq in eqs] # Weird type stuff
    @named sys = System(real_eqs, t; __legacy_defaults__ = defs)
    mtkcompile(sys)
end

function eval_AST(package::BaseModelicaPackage)
    model = package.model
    eval_AST(model)
end

function eval_AST(function_args::BaseModelicaFunctionArgs)
    args = function_args.args
    eval_AST.([args...])
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
    function_map[function_name](args)
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
    eval_AST(package)
end
