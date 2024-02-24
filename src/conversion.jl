function baseModelica_to_ModelingToolkit(model::BaseModelicaModel)
    param_names = [Symbol(param.name) for param in model.parameters]
    param_descs = [param.description for param in model.parameters]
    parameters = [only(@parameters $name [description = "$desc"])
                  for (name, desc) in zip(param_names, param_descs)]

    var_names = [Symbol(var.name) for var in model.variables]
    var_descs = [var.description for var in model.variables]
    variables = [only(@variables $name [description = "$desc"])
                 for (name, desc) in zip(var_names, var_descs)]
    var_funcs = [only(@variables $name(t) [description = "$desc"])
                 for (name, desc) in zip(var_names, var_descs)]

    equ_lhses = [replace(equ.lhs, "\'" => "") for equ in model.equations]
    equ_rhses = [replace(equ.rhs, "\'" => "") for equ in model.equations]

    init_lhses = [replace(equ.lhs, "\'" => "") for equ in model.initialequations]
    init_rhses = [replace(equ.rhs, "\'" => "") for equ in model.initialequations]

    param_defaults = parameters .=>
        [param.value == "" ? nothing : parse(Float64, param.value)
         for param in model.parameters]

    init_subst_dict = Dict(vcat(param_defaults, variables .=> var_funcs))

    init_lhs_exprs = [substitute(Symbolics.parse_expr_to_symbolic(Meta.parse(lhs), Main),
                          init_subst_dict) for lhs in init_lhses]
    init_rhs_exprs = [substitute(Symbolics.parse_expr_to_symbolic(Meta.parse(lhs), Main),
                          init_subst_dict) for lhs in init_rhses]

    inits = init_lhs_exprs .=> substitute(init_rhs_exprs, init_subst_dict)

    defaults_and_inits = Dict(vcat(inits, param_defaults))

    subst_dict = Dict(vcat(parameters .=> parameters, variables .=> var_funcs))

    lhs_exprs = [substitute(
                     Symbolics.parse_expr_to_symbolic(Meta.parse(lhs), BaseModelica),
                     subst_dict) for lhs in equ_lhses]
    rhs_exprs = [substitute(
                     Symbolics.parse_expr_to_symbolic(Meta.parse(rhs), BaseModelica),
                     subst_dict) for rhs in equ_rhses]

    eqs = [lhs ~ rhs for (lhs, rhs) in zip(lhs_exprs, rhs_exprs)]

    model_name = Symbol(model.name)
    sys = structural_simplify(ODESystem(
        eqs, t, var_funcs, parameters; defaults = defaults_and_inits, name = model_name))
end
