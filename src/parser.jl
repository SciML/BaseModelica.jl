using Automa

struct BaseModelicaModel

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

end


base_Modelica_machine = let 
    newline = re"\n"
    endexpr = re";"
    type = re"Real"
    name = re"'[A-Za-z0-9._]+'"
    value = re"(= ?[0-9]+\.?[0-9]*)"
    description = re"(\"([A-Za-z0-9._ ]|\n)*\")"
    parameter = re"parameter" * ' ' * type * ' ' * name * opt(endexpr) * opt(re" ?" * opt(value) * ' ' * opt(description))
    variable = type * ' ' * name * ' ' * description
    #parameter Real '[A-Za-z0-9._]+' ?(=? ?[\d]+\.?[\d]*)? ?("([A-Za-z0-9._ ]|\n)*")?;
    equation = re"[^!=;\"]+ ?= ?[^!=;\"]+"
    equation_header = re"equation"

  
    precond!(equation_header, :done_flag)
    precond!(equation_header, :equation_flag, bool = false)
    onexit!(equation_header,:set_equation_flag )
    
    precond!(type, :equation_flag, bool = false)
    onenter!(type,:mark_pos)
    onexit!(type,:get_type)

    precond!(name, :equation_flag, bool = false)
    onenter!(name, :mark_pos)
    onexit!(name,:get_name)

    precond!(value, :equation_flag, bool = false)
    onenter!(value,:mark_pos)
    onexit!(value, :get_value)


    precond!(description, :equation_flag, bool = false)
    onenter!(description,:mark_pos)
    onexit!(description,:get_description)

    onexit!(endexpr,:set_done_flag)


    precond!(parameter, :equation_flag, bool = false)
    onenter!(parameter,:unset_done_flag)
    onexit!(parameter, :create_parameter)

    precond!(variable, :equation_flag, bool = false)
    onenter!(variable,:unset_done_flag)
    onexit!(variable, :create_variable)

    precond!(equation, :equation_flag, bool = true)
    precond!(equation, :done_flag)
    onenter!(equation, [:mark_pos, :unset_done_flag])
    onexit!(equation, :create_equation)

    full_machine = rep(parameter * endexpr * opt(newline)) * rep(variable * endexpr * opt(newline)) * opt(equation_header * newline) * rep(equation * endexpr * opt(newline)) 
    compile(full_machine,unambiguous = false)
end

display_machine(base_Modelica_machine)

base_Modelica_actions = Dict(
    :mark_pos => :(pos = p),
    :get_type => :(type = String(data[pos:p-1]); pos = 0;),
    :get_name => :(name = String(data[pos:p-1]); pos = 0; name_got = true), #get name, set name_got flag to true
    :get_description => :(description = String(data[pos:p-1]); pos = 0),
    :get_value => :(value = String(data[pos:p-1]); pos = 0; name_got = false), #get the value, reset the name_got flag
    :create_equation => :(equal_index = findfirst("=",data)[1]; lhs = String(data[pos:equal_index-1]); rhs = String(data[equal_index+1:p-1]); push!(equations,BaseModelicaEquation(lhs,rhs))),
    :create_parameter => :(push!(parameters,BaseModelicaParameter(type,name,value,description));type = ""; name = ""; value = ""; description = ""),
    :create_variable => :(push!(variables,BaseModelicaVariable(type,name,description)); type = ""; name = ""; description = ""),
    :set_done_flag =>:(done_flag = true),
    :unset_done_flag =>:(done_flag = false),
    :set_equation_flag => :(equation_flag = true),
    :equation_flag => :(equation_flag == true),
    :done_flag => :(done_flag == true)
)


context = CodeGenContext(generator = :goto)
@eval function parse_BaseModelica(data)
    # Initialize variables you use in the action code.
    pos = 0
    name_got = false
    equation_flag = false
    done_flag = true # flag to mark whether it's done reading a parameter, variable or equation yet

    name = ""
    description = ""
    value = ""
    type = ""
    lhs = ""
    rhs = ""
    parameters = BaseModelicaParameter[]
    variables = BaseModelicaVariable[]
    equations = BaseModelicaEquation[]
    
    # Generate code for initialization and main loop
    $(generate_code(context, base_Modelica_machine, base_Modelica_actions))
    # Finally, return records accumulated in the action code.
    return parameters, variables, equations
end

parse_BaseModelica("parameter Real 'wagon.m' = 100000.0525 \"Mass of the sliding mass\";")
parse_BaseModelica("parameter Real 'slop.m';")
parse_BaseModelica("Real 'wagon.flange_b.f' \"Cut force directed into flange\";")
parse_BaseModelica("""parameter Real 'slop.m';\nReal 'wagon.flange_b.f' \"Cut force directed into flange\";""")
parse_BaseModelica("""parameter Real 'sloop.m';\nReal 'wagon.flange_b.f' \"Cut force directed into flange\";\nparameter Real 'wagon.m' = 100000.0525 \"Mass of the sliding mass\";\nparameter Real 'slop.m';""")
parse_BaseModelica("""Real 'doop.f' "doopy doopy doo";\nReal 'deep.doop' "deepy doopy dah";""")
parse_BaseModelica("equation\n 'wagon.flange_a.s'='doop';")
parse_BaseModelica("equation\n 'locomotive.flange_b.f'+'wagon.flange_a.f' = 0.0;")
function display_machine(m::Automa.Machine)
    open("/tmp/machine.dot", "w") do io
        println(io, Automa.machine2dot(m))
    end
    run(pipeline(`dot -Tsvg /tmp/machine.dot`, stdout="/tmp/machine.svg"))
    run(`firefox /tmp/machine.svg`)
end