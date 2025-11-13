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
            BaseModelicaBool(val) => val == "true"
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

function eval_AST(eq::BaseModelicaSimpleEquation)
    if eq.lhs isa BaseModelicaIfEquation
        return eval_AST(eq.lhs)
    end
    lhs = eval_AST(eq.lhs)
    rhs = eval_AST(eq.rhs)
    lhs ~ rhs
end

function eval_AST(if_eq::BaseModelicaIfEquation)
    # Convert if-equation to nested ifelse calls
    # Structure: ifs[i] contains condition, thens[i] contains equations for that branch

    # Process all equations in all branches to get the lhs variables
    # We assume all branches assign to the same variables
    all_equations = []
    
    for eq in if_eq.thens
        if isa(eq, BaseModelicaAnyEquation)
            push!(all_equations, eval_AST(eq.equation))
        else
            push!(all_equations, eval_AST(eq))
        end
    end

    # Build result equations by nesting ifelse calls from right to left
    # For each unique lhs variable, build an ifelse expression
    result_equations = []

    # Helper function to build nested ifelse for a single variable across all branches
    function build_ifelse_for_var(var_lhs, branch_idx=1)
        
        if branch_idx > length(if_eq.ifs)
            # This shouldn't happen if the model is well-formed
            error("If-equation branches exhausted without finding assignment")
        end

        # Get the RHS for this variable in this branch
        eq = if_eq.thens[branch_idx]
        rhs_expr = nothing
        eq_obj = isa(eq, BaseModelicaAnyEquation) ? eval_AST(eq.equation) : eval_AST(eq)
        if !isnothing(eq_obj) && isa(eq_obj, Equation)
            eq_lhs = eq_obj.lhs
            if isequal(eq_lhs, var_lhs)
                rhs_expr = eq_obj.rhs
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

    #vars = [eval_AST(comp) for comp in components if comp.type_prefix.dpc != "parameter"]
    #pars = [eval_AST(comp) for comp in components if comp.type_prefix.dpc == "parameter"]

    # this loop populates the variable_map
    vars = Num[]
    pars = Num[]
    for comp in components
        name = Symbol(comp.component_list[1].declaration.ident[1].name)

        eval_AST(comp)

        if comp.type_prefix.dpc == "parameter" || comp.type_prefix.dpc == "constant"
            push!(pars, variable_map[name])
        else
            push!(vars, variable_map[name])
        end
    end

    # Flatten equations - some equations (like if-equations) return lists
    eqs_raw = [eval_AST(eq) for eq in equations]
    eqs = []
    for eq in eqs_raw
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
    @named sys = System(real_eqs, t; defaults = defs)
    structural_simplify(sys)
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
    function_name = Symbol(function_call.func_name)
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

    return variable_map[ref_name]
end

function baseModelica_to_ModelingToolkit(package::BaseModelicaPackage)
    eval_AST(package)
end
