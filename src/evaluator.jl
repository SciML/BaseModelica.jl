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
            BaseModelicaNumber(val) => val
            BaseModelicaFactor(base,exp) => (f(base)) ^ (f(exp))
            BaseModelicaSum(left,right) => f(left) + f(right)
            BaseModelicaMinus(left,right) => f(left) - f(right)
            BaseModelicaProd(left,right) => f(left) * f(right)
            BaseModelicaDivide(left,right) => f(left) / f(right)
            BaseModelicaSimpleEquation(lhs, rhs) => (f(lhs) ~ f(rhs))
            BaseModelicaNot(relation) => !f(relation)
            BaseModelicaAnd(left,right) => f(left) && f(right)
            BaseModelicaOr(left,right) => f(left) || f(right)
            BaseModelicaLEQ(left,right) => f(left) <= f(right)
            BaseModelicaGEQ(left,right) => f(left) >= f(right)
            BaseModelicaLessThan(left,right) => f(left) < f(right)
            BaseModelicaGreaterThan(left,right) => f(left) > f(right)
            BaseModelicaEQ(left,right) => f(left) == f(right)
            BaseModelicaNEQ(left,right) => f(left) != f(right)
            _ => nothing
        end
    end

function eval_AST(eq::BaseModelicaAnyEquation)
    equation = eval_AST(eq.equation)
    description = eq.description
    return equation
end
