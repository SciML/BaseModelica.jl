# function to convert "AST" to ModelingToolkit
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


eval_AST(expr::BaseModelicaExpr) = 
    let f = eval_AST
        @match expr begin
            BaseModelicaNumber(val) => :($val)
            BaseModelicaFactor(base,exp) => :($(f(base)) ^ $(f(exp)))
            BaseModelicaSum(left,right) => :($(f(left)) + $(f(right)))
            BaseModelicaMinus(left,right) => :($(f(left)) - $(f(right)))
            BaseModelicaProd(left,right) => :($(f(left)) * $(f(right)))
            BaseModelicaDivide(left,right) => :($(f(left)) / $(f(right)))
            BaseModelicaNot(relation) => :(!($(f(relation))))
            BaseModelicaAnd(left,right) => :($(f(left)) && $(f(right)))
            BaseModelicaOr(left,right) => :($(f(left)) || $(f(right)))
            BaseModelicaLEQ(left,right) => :($(f(left)) <= $(f(right)))
            BaseModelicaGEQ(left,right) => :($(f(left)) >= $(f(right)))
            BaseModelicaLessThan(left,right) => :($(f(left)) < $(f(right)))
            BaseModelicaGreaterThan(left,right) => :($(f(left)) > $(f(right)))
            BaseModelicaEQ(left,right) => :($(f(left)) == $(f(right)))
            BaseModelicaNEQ(left,right) => :($(f(left)) != $(f(right)))
            _ => nothing
        end
    end

function eval_AST(eq::BaseModelicaInitialEquation)
    inner_eq = eq.equation
    
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

function eval_AST(ref::BaseModelicaComponentReference)
    ref_list = ref.ref_list
    if length(ref_list) == 1 
        return :($(Symbol(ref_list[1].name)))
    end
end

function eval_AST(component::BaseModelicaComponentClause)
    #place holder to get simple equations working
    list = component.component_list
    type_prefix = component.type_prefix.dpc
    name = Symbol(list[1].name)
    if type_prefix == "parameter"
        return only(@parameters($name))
    elseif isnothing(type_prefix)
        return only(@variables($name))
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

    comps = [eval_AST(comp) for comp in components]
    eqs = [eval_AST(eq) for eq in equations]
    init_eqs = [eval_AST(eq) for eq in initial_equations]
end

function eval_AST(package::BaseModelicaPackage)
    model = package.model
    eval_AST(model)
end