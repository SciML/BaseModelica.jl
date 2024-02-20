using ModelingToolkit

function base_Modelica_to_ModelingToolkit(model::BaseModelicaModel)
    equations = []

    @parameters t
    der = Differential(t)

    param_names = [Symbol(param.name) for param in model.parameters]
    param_descs = [param.description for param in model.parameters]
    parameters = [only(@parameters $name [description = "$desc"]) for (name,desc) in zip(param_names, param_descs)]

    var_names = [Symbol(var.name) for var in model.variables]
    var_descs = [var.description for var in model.variables]
    variables = [only(@variables $name [description = "$desc"]) for (name,desc) in zip(var_names,var_descs)]

    equ_lhses = [replace(equ.lhs, "\'" => "" ) for equ in model.equations]
    equ_rhses = [replace(equ.rhs, "\'" => "" ) for equ in model.equations]

    subst_dict = Dict(vcat(parameters .=> parameters, variables .=> variables))

    Symbolics.parse_expr_to_symbolic(Meta.parse(lhses),Main)

    lhs_exprs = [Symbolics.parse_expr_to_symbolic(Meta.parse(lhs),Main) for lhs in equ_lhses]
    rhs_exprs = [Symbolics.parse_expr_to_symbolic(Meta.parse(rhs),Main) for lhs in equ_rhses]

    equations = [   (lhs,rhs) in zip(lhs_exprs, rhs_exprs)]

    parameters, variables, equ_lhses, equ_rhses

end



base_Modelica_to_ModelingToolkit(test_model.models)[1]
base_Modelica_to_ModelingToolkit(test_model.models)[2]
base_Modelica_to_ModelingToolkit(test_model.models)[3]
base_Modelica_to_ModelingToolkit(test_model.models)[4]

pars = base_Modelica_to_ModelingToolkit(newton_test.models)[1]
vars = base_Modelica_to_ModelingToolkit(newton_test.models)[2]
lhses = base_Modelica_to_ModelingToolkit(newton_test.models)[3][1]
rhses = base_Modelica_to_ModelingToolkit(newton_test.models)[4]

lhs_Num = Symbolics.parse_expr_to_symbolic(Meta.parse(lhses),Main)

@parameters t

der = Differential(t)
pars .=> pars
vars .=> vars
Dict(vcat(pars .=> pars, vars .=> vars))
substitute(lhs_Num, Dict(vcat(pars .=> pars, vars .=> vars, der => der)))
