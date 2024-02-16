using Automa

struct BaseModelicaPackage

end
struct BaseModelicaModel
    name
    parameters
    variables
    equations
    initialequations
end

struct BaseModelicaParameter
    type
    name
    value
    description
end

struct BaseModelicaVariable
    type
    name
    description
end

struct BaseModelicaEquation
    lhs
    rhs
end

struct BaseModelicaInitialEquation
    lhs
    rhs
end


base_Modelica_machine = let 
    newline = re"\n"
    endexpr = re";"
    model_header = re"model '[A-Za-z0-9._]+'"
    end_marker = re"end '[A-Za-z0-9._]+'" * endexpr
    type = re"Real"
    name = re"'[A-Za-z0-9._]+'"
    value = re"(= ?[0-9]+\.?[0-9]*)"
    description = re"(\"([A-Za-z0-9._ ]|\n)*\")"
    parameter = re"parameter" * ' ' * type * ' ' * name * opt(re" ?" * opt(value) * ' ' * opt(description)) * endexpr
    variable = type * ' ' * name * ' ' * description * endexpr
    #parameter Real '[A-Za-z0-9._]+' ?(=? ?[\d]+\.?[\d]*)? ?("([A-Za-z0-9._ ]|\n)*")?;
    equation_expr = re"[^Ripem;\n][^!=;\"]+ ?= ?[^!=;\"]+" * endexpr
    equation_header = re"equation"
    initial_header = re"initial equation"

    onfinal!(model_header,:get_model_name)    

    onfinal!(equation_header,[:set_equation_flag, :clear_initial_flag])
    onfinal!(initial_header,[:set_initial_flag, :clear_equation_flag])
    
    precond!(type, :equation_or_initial_flag, bool = false)
    onenter!(type,:mark_pos)
    onfinal!(type,:get_type)

    precond!(name, :equation_or_initial_flag, bool = false)
    onenter!(name, :mark_pos)
    onexit!(name,:get_name)

    precond!(value, :equation_or_initial_flag, bool = false)
    onenter!(value, :mark_pos)
    onexit!(value, :get_value)

    precond!(description, :equation_or_initial_flag, bool = false)
    onenter!(description,:mark_pos)
    onfinal!(description,:get_description)

    precond!(parameter, :equation_or_initial_flag, bool = false)
    onfinal!(parameter, :create_parameter)


    precond!(variable, :equation_or_initial_flag, bool = false)
    onfinal!(variable, :create_variable)

    precond!(equation_expr, :equation_or_initial_flag)
    onenter!(equation_expr, :mark_pos)
    onfinal!(equation_expr, :create_equation)

    full_machine = opt(model_header * newline) * rep(rep(parameter * opt(newline)) * rep(variable * opt(newline))) * opt(initial_header * newline) * rep(equation_expr * opt(newline)) * opt(equation_header * newline) * rep(equation_expr  * opt(newline)) * opt(end_marker)
    compile(full_machine)
end

display_machine(base_Modelica_machine)

base_Modelica_actions = Dict(
    :mark_pos => :(pos = p),
    :get_type => :(type = String(data[pos:p]); pos = 0;),
    :get_name => :(name = String(data[pos:p]); pos = 0), 
    :get_model_name => :(name_index = findfirst("'", data)[1]; model_name = String(data[name_index:p]); pos = 0),
    :get_description => :(description = String(data[pos:p]); pos = 0),
    :get_value => :(value = String(data[pos:p]); pos = 0; name_got = false), #get the value, reset the name_got flag
    :create_equation => quote
        equal_index = findfirst("=",data[pos:p])[1]
        print(equal_index)
        lhs = String(data[pos:p][1:equal_index-1]) #data[pos:p] is the whole equation expression
        rhs = String(data[pos:p][equal_index:end-1]) #minus one to not include the semicolon
        initial_flag ? push!(initial_equations,BaseModelicaInitialEquation(lhs,rhs)) : push!(equations,BaseModelicaEquation(lhs,rhs))
        pos = 0
        rhs = ""
        hs = ""
    end,
    :create_parameter => :(push!(parameters,BaseModelicaParameter(type,name,value,description));type = ""; name = ""; value = ""; description = ""),
    :create_variable => :(push!(variables,BaseModelicaVariable(type,name,description)); type = ""; name = ""; description = ""),
    :set_equation_flag => :(equation_flag = true),
    :clear_equation_flag => :(equation_flag = false),
    :set_initial_flag => :(initial_flag = true),
    :clear_initial_flag => :(initial_flag = false),
    :equation_or_initial_flag => :(equation_flag || initial_flag)
)


context = CodeGenContext(generator = :goto)
@eval function parse_BaseModelica(data)
    # Initialize variables you use in the action code.
    pos = 0
    name_got = false
    equation_flag = false
    initial_flag = false
    done_flag = true # flag to mark whether it's done reading a parameter, variable or equation yet

    model_name = ""
    name = ""
    description = ""
    value = ""
    type = ""
    lhs = ""
    rhs = ""
    parameters = BaseModelicaParameter[]
    variables = BaseModelicaVariable[]
    equations = BaseModelicaEquation[]
    initial_equations = BaseModelicaInitialEquation[]
    
    # Generate code for initialization and main loop
    $(generate_code(context, base_Modelica_machine, base_Modelica_actions))
    # Finally, return records accumulated in the action code.
    return BaseModelicaModel(model_name, parameters,variables, equations, initial_equations)
    #parameters, variables, initial_equations, model_name
    equations
end

parse_BaseModelica("parameter Real 'wagon.m' = 100000.0525 \"Mass of the sliding mass\";")
parse_BaseModelica("parameter Real 'slop.m';")
parse_BaseModelica("Real 'wagon.flange_b.f' \"Cut force directed into flange\";")
parse_BaseModelica("""parameter Real 'slop.m';\nReal 'wagon.flange_b.f' \"Cut force directed into flange\";""")
parse_BaseModelica("""parameter Real 'sloop.m';\nReal 'wagon.flange_b.f' \"Cut force directed into flange\";\nparameter Real 'wagon.m' = 100000.0525 \"Mass of the sliding mass\";\nparameter Real 'slop.m';""")
parse_BaseModelica("""Real 'doop.f' "doopy doopy doo";\nReal 'deep.doop' "deepy doopy dah";""")
parse_BaseModelica("equation\n 'wagon.flange_a.s'='doop';")
parse_BaseModelica("equation\n 'locomotive.flange_b.f'+'wagon.flange_a.f' = 0.0;")
parse_BaseModelica("equation\n 'locomotive.flange_b.f'+'wagon.flange_a.f' = 'jeepers_creepers' - 'doopers_deepers/2;")
parse_BaseModelica("initial equation\n 'locomotive.flange' = 'doopy_doo';")
parse_BaseModelica("""
parameter Real 'wagon.m' = 100000.0525 \"Mass of the sliding mass\";
parameter Real 'slop.m';
Real 'wagon.flange_b.f' \"Cut force directed into flange\";
equation
'locomotive.flange_b.f'+'wagon.flange_a.f' = 'jeepers_creepers' - 'doopers_deepers/2;
""")
parse_BaseModelica("""model 'dopper'
end 'dopper';""")

test_result = parse_BaseModelica("""model 'Test'
parameter Real 'wagon.m' = 100000.0525 \"Mass of the sliding mass\";
parameter Real 'slop.m';
Real 'doop.f' "doopy doopy doo";
initial equation
'locamotive.mass.m' = 10000.0';
equation
'wagon.flange_a.s' = 'locomotive.m'/30 + 5;
end 'Test';""")


function display_machine(m::Automa.Machine)
    open("/tmp/machine.dot", "w") do io
        println(io, Automa.machine2dot(m))
    end
    run(pipeline(`dot -Tsvg /tmp/machine.dot`, stdout="/tmp/machine.svg"))
    run(`firefox /tmp/machine.svg`)
end

