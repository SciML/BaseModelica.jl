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

end

struct BaseModelicaInitialEquation

end


base_Modelica_machine = let 
    type = re"Real"
    name = re"'[A-Za-z0-9._]+'"
    value = re"(= ?[0-9]+\.?[0-9]*)"
    description = re"(\"([A-Za-z0-9._ ]|\n)*\")"
    parameter = re"parameter" * ' ' * type * ' ' * name * re" ?" * opt(value) * re" " * opt(description) * ';'
    variable = type * name * description
    #parameter Real '[A-Za-z0-9._]+' ?(=? ?[\d]+\.?[\d]*)? ?("([A-Za-z0-9._ ]|\n)*")?;

    onenter!(type,:mark_pos)
    onexit!(type,:get_type)
    #precond!(name,:name_got, bool=false)
    onenter!(name, :mark_pos)
    onexit!(name,:get_name)

    #precond!(value, :name_got)
    onenter!(value,:mark_pos)
    onexit!(value, :get_value)

    #precond!(description,:name_got)
    onenter!(description,:mark_pos)
    onexit!(description,:get_description)

    compile(parameter)
end

base_Modelica_actions = Dict(
    :mark_pos => :(pos = p),
    :get_type => :(type = String(data[pos:p-1]); pos = 0;)
    :get_name => :(name = String(data[pos:p-1]); pos = 0; name_got = true), #get name, set name_got flag to true
    :get_description => :(description = String(data[pos:p-1]); pos = 0),
    :get_value => :(value = String(data[pos:p-1]); pos = 0; name_got = false) #get the value, reset the name_got flag
)


context = CodeGenContext()
@eval function parse_BaseModelica(data)
    # Initialize variables you use in the action code.
    pos = 0
    name_got = false



    name = ""
    description = ""
    value = ""
    
    # Generate code for initialization and main loop
    $(generate_code(context, base_Modelica_machine, base_Modelica_actions))

    # Finally, return records accumulated in the action code.
    return name, description, value
end

parse_BaseModelica("parameter Real 'wagon.m' = 100000.0525 \"Mass of the sliding mass\";")