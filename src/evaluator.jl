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
            BaseModelicaFactor(base, exp) => (f(base))^f(exp)
            BaseModelicaSum(left, right) => (f(left)) + (f(right))
            BaseModelicaMinus(left, right) => f(left) - f(right)
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

function eval_AST(eq::BaseModelicaSimpleEquation)
    lhs = eval_AST(eq.lhs)
    rhs = eval_AST(eq.rhs)
    lhs ~ rhs
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
        parameter_val_map[variable_map[name]] = declaration.modification[1].expr[1].val
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

    eqs = [eval_AST(eq) for eq in equations]

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

    defaults = merge(init_eqs_dict, parameter_val_map)
    @named model = ODESystem(eqs, t, vars, pars; defaults)
    structural_simplify(model)
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
    return variable_map[Symbol(comp_reference.ref_list[1].name)]
end

function baseModelica_to_ModelingToolkit(package::BaseModelicaPackage)
    eval_AST(package)
end
