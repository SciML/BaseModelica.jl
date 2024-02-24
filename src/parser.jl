base_Modelica_machine = let
    newline = re"\n" | re"\r" | re"\r\n"
    endexpr = re";"
    description = re"(\"([A-Za-z0-9._ ']|(\n|\r|\r\n))*\")"
    model_header = re"model '[A-Za-z0-9._]+'" * opt(' ' * description)
    package_header = re"package '[A-Za-z0-9._]+'"
    end_marker = re"end '[A-Za-z0-9._]+'" * endexpr
    type = re"Real"
    name = re"'[A-Za-z0-9._]+'"
    value = re"= ?[0-9]+\.?[0-9]*"

    parameter = re"parameter" * ' ' * type * ' ' * name * opt(' ') * opt(value) *
                opt(opt(' ') * opt(description)) * endexpr
    variable = type * ' ' * name * ' ' * description * endexpr
    #parameter Real '[A-Za-z0-9._]+' ?(=? ?[\d]+\.?[\d]*)? ?("([A-Za-z0-9._ ]|\n)*")?;
    equation_expr = re"[^Ripem;(\n|\r|\r\n)\t ][^!=;\"\t]+ ?= ?[^!=;\"\t]+" *
                    opt(' ' * description) *
                    endexpr
    equation_header = re"equation"
    initial_header = re"initial equation"

    onfinal!(model_header, :get_model_name)

    onfinal!(package_header, :get_package_name)

    onfinal!(equation_header, [:set_equation_flag, :clear_initial_flag])
    onfinal!(initial_header, [:set_initial_flag, :clear_equation_flag])

    precond!(type, :equation_or_initial_flag, bool = false)
    onenter!(type, :mark_pos)
    onfinal!(type, :get_type)

    precond!(name, :equation_or_initial_flag, bool = false)
    onenter!(name, :mark_pos)
    onexit!(name, :get_name)

    precond!(value, :equation_or_initial_flag, bool = false)
    onenter!(value, :mark_pos)
    onexit!(value, :get_value)

    #precond!(description, :equation_or_initial_flag, bool = false)
    onenter!(description, :mark_pos)
    onfinal!(description, :get_description)

    precond!(parameter, :equation_or_initial_flag, bool = false)
    onfinal!(parameter, :create_parameter)

    precond!(variable, :equation_or_initial_flag, bool = false)
    onfinal!(variable, :create_variable)

    precond!(equation_expr, :equation_or_initial_flag)
    onenter!(equation_expr, :mark_equ_pos)
    onfinal!(equation_expr, :create_equation)

    full_machine = package_header * newline * rep('\t') * rep(' ') *
                   model_header * newline *
                   rep(rep(rep('\t') * rep(' ') * parameter *
                           opt(newline)) *
                       rep(rep('\t') * rep(' ') * variable * opt(newline))) *
                   opt(rep('\t') * rep(' ') * initial_header * newline) *
                   rep(rep('\t') *
                       rep(' ') * equation_expr * opt(newline)) *
                   opt(rep('\t') * rep(' ') *
                       equation_header * newline) *
                   rep(rep('\t') * rep(' ') * equation_expr *
                       opt(newline)) * rep('\t') * rep(' ') * end_marker * newline *
                   rep('\t') *
                   rep(' ') * end_marker * opt(newline)

    compile(full_machine)
end

base_Modelica_actions = Dict(
    :mark_pos => :(pos = p),
    :mark_equ_pos => :(equ_pos = p),
    :get_type => :(type = String(data[pos:p]); pos = 0),
    :get_name => :(name = Symbol(strip(String(data[pos:p]), ['\'', ' ', ';'])); pos = 0),
    :get_model_name => quote
        data_to_point = data[findfirst("model", data)[end]:p]
        ticks = findall("'", data_to_point)
        first_tick_index, last_tick_index = (only(ticks[1]), only(ticks[2]))
        model_name = strip(String(data_to_point[first_tick_index:last_tick_index]), '\'')
        model_description = description
        description = ""
    end,
    :get_package_name => quote
        data_to_point = data[findfirst("package", data)[end]:p]
        ticks = findall("'", data_to_point)
        first_tick_index, last_tick_index = (only(ticks[1]), only(ticks[2]))
        package_name = strip(String(data_to_point[first_tick_index:last_tick_index]), '\'')
    end,
    :get_description => :(description = strip(String(data[pos:p]), '"'); pos = 0),
    :get_value => :(value = strip(String(data[pos:p]), ['=', ' ', ';']); pos = 0), #get the value
    :create_equation => quote
        equal_index = findfirst("=", data[equ_pos:p])[1]
        description_start = findfirst("\"", data[equ_pos:p])
        lhs = strip(String(data[equ_pos:p][1:(equal_index - 1)]), ' ') #data[pos:p] is the whole equation expression
        rhs = strip(
            isnothing(description_start) ? String(data[equ_pos:p][(equal_index + 1):end]) :
            String(data[equ_pos:p][(equal_index + 1):description_start[1]]),
            [' ', ';', '"'])
        equation_description = description
        initial_flag ?
        push!(initial_equations,
            BaseModelicaInitialEquation(lhs, rhs, equation_description)) :
        push!(equations, BaseModelicaEquation(lhs, rhs, equation_description))
        pos = 0
        equ_pos = 0
        rhs = ""
        lhs = ""
        description = ""
    end,
    :create_parameter => :(push!(
        parameters, BaseModelicaParameter(type, name, value, description));
    type = "";
    name = "";
    value = "";
    description = ""),
    :create_variable => :(push!(variables, BaseModelicaVariable(type, name, description)); type = ""; name = ""; description = ""),
    :set_equation_flag => :(equation_flag = true),
    :clear_equation_flag => :(equation_flag = false),
    :set_initial_flag => :(initial_flag = true),
    :clear_initial_flag => :(initial_flag = false),
    :equation_or_initial_flag => :(equation_flag || initial_flag)
)

context = CodeGenContext(generator = :goto)
@eval function parse_package_str(data)
    # Initialize variables you use in the action code.
    pos = 0
    equ_pos = 0
    other_pos = 0
    equation_flag = false
    initial_flag = false

    model_name = ""
    model_description = ""
    package_name = ""
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
    return BaseModelicaPackage(package_name,
        BaseModelicaModel(model_name, model_description, parameters,
            variables, equations, initial_equations))
    #parameters, variables, initial_equations, model_name, equations
end

"""
Parses a string in to a BaseModelicaPackage.
"""
function parse_str(data)
    parse_package_str(data)
end

"""
Takes a path to a file and parses the contents in to a BaseModelicaPackage.
"""
function parse_file(file)
    parse_str(read(file, String))
end

function display_machine(m::Automa.Machine)
    open("/tmp/machine.dot", "w") do io
        println(io, Automa.machine2dot(m))
    end
    run(pipeline(`dot -Tsvg /tmp/machine.dot`, stdout = "/tmp/machine.svg"))
    run(`firefox /tmp/machine.svg`)
end
