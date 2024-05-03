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

end

function eval_AST(package::BaseModelicaPackage)

end