using Automa

struct BaseModelicaPackage
    name
    models
end
struct BaseModelicaModel
    name
    description
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
    description = re"(\"([A-Za-z0-9._ ]|\n)*\")"
    model_header = re"model '[A-Za-z0-9._]+'" * opt(' ' * description)
    package_header = re"package '[A-Za-z0-9._]+'"
    end_marker = re"end '[A-Za-z0-9._]+'" * endexpr
    type = re"Real"
    name = re"'[A-Za-z0-9._]+'"
    value = re"= ?[0-9]+\.?[0-9]*"
  
    parameter = re"parameter" * ' ' * type * ' ' * name * re" ?" * opt(value) * opt(opt(' ') * opt(description)) * endexpr
    variable = type * ' ' * name * ' ' * description * endexpr
    #parameter Real '[A-Za-z0-9._]+' ?(=? ?[\d]+\.?[\d]*)? ?("([A-Za-z0-9._ ]|\n)*")?;
    equation_expr = re"[^Ripem;\n\t ][^!=;\"\t]+ ?= ?[^!=;\"\t]+" * opt(description) * endexpr
    equation_header = re"equation"
    initial_header = re"initial equation"


    onfinal!(model_header,:get_model_name) 

    onfinal!(package_header,:get_package_name)

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

    full_machine = package_header * newline * rep('\t') * rep(' ') * model_header * 
    newline * rep(rep(rep('\t') * rep(' ') * parameter * opt(newline)) * 
    rep(rep('\t') * rep(' ') * variable * opt(newline))) * opt(rep('\t') * 
    rep(' ') * initial_header * newline) * rep(rep('\t') * rep(' ') * equation_expr * 
    opt(newline)) * opt(rep('\t') * rep(' ') * equation_header * newline) * rep(rep('\t') * 
    rep(' ') * equation_expr  * opt(newline)) * rep('\t') * rep(' ') * end_marker * 
    newline * rep('\t') * rep(' ') * end_marker
    
    compile(full_machine)
end

display_machine(base_Modelica_machine)

base_Modelica_actions = Dict(
    :mark_pos => :(pos = p),
    :get_type => :(type = String(data[pos:p]); pos = 0;),
    :get_name => :(name = strip(String(data[pos:p]), ['\'', ' ', ';']); pos = 0), 
    :get_model_name => quote
           data_to_point = data[findfirst("model",data)[end]:p]
           ticks = findall("'",data_to_point)
           first_tick_index, last_tick_index = (only(ticks[1]),only(ticks[2]))
           model_name = strip(String(data_to_point[first_tick_index:last_tick_index]),'\'')
           model_description = description
           description = ""
    end,
    :get_package_name =>quote
        data_to_point = data[findfirst("package",data)[end]:p]
        ticks = findall("'",data_to_point)
        first_tick_index, last_tick_index = (only(ticks[1]),only(ticks[2]))
        package_name = strip(String(data_to_point[first_tick_index:last_tick_index]),'\'')
    end,
    :get_description => :(description = strip(String(data[pos:p]), '"'); pos = 0),
    :get_value => :(value = strip(String(data[pos:p]),['=',' ',';']); pos = 0), #get the value
    :create_equation => quote
        equal_index = findfirst("=",data[pos:p])[1]
        lhs = strip(String(data[pos:p][1:equal_index-1]),' ') #data[pos:p] is the whole equation expression
        rhs = strip(String(data[pos:p][equal_index+1:end-1]),' ') #minus one to not include the semicolon
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
    return BaseModelicaPackage(package_name, BaseModelicaModel(model_name,model_description, parameters,variables, equations, initial_equations))
    #parameters, variables, initial_equations, model_name, equations
end



parse_BaseModelica("""package 'Test'
  model 'Test'
    parameter Real 'slop.m';
    parameter Real 'doop.doo' \"sloopy sloopy slaw\";
    parameter Real 'wagon.m' = 100000.0525 \"Mass of the sliding mass\";
    parameter Real 'doody.doo' = 45;
    parameter Real 'diedeydiey' = 456.463;
    Real 'doop.f' "doopy doopy doo";
  initial equation
    'wagon.m' = 100000.0525;
    'deedee' = 'feefee';
  equation
    'locomotive.flange_b.f'+'wagon.flange_a.f' = 'jeepers_creepers' - 'doopers_deepers/2 + 500.00;
  end 'Test';
end 'Test';""")

parse_BaseModelica("""package 'Test'
  model 'Test' "Test for Julia BaseModelica Parser"
    parameter Real 'slop.m';
    parameter Real 'doop.doo' \"sloopy sloopy slaw\";
    parameter Real 'wagon.m' = 100000.0525 \"Mass of the sliding mass\";
    parameter Real 'doody.doo' = 45;
    parameter Real 'diedeydiey' = 456.463;
    Real 'doop.f' "doopy doopy doo";
  initial equation
    'wagon.m' = 100000.0525;
    'deedee' = 'feefee';
  equation
    'locomotive.flange_b.f'+'wagon.flange_a.f' = 'jeepers_creepers' - 'doopers_deepers/2 + 500.00;
  end 'Test';
end 'Test';""")

function display_machine(m::Automa.Machine)
    open("/tmp/machine.dot", "w") do io
        println(io, Automa.machine2dot(m))
    end
    run(pipeline(`dot -Tsvg /tmp/machine.dot`, stdout="/tmp/machine.svg"))
    run(`firefox /tmp/machine.svg`)
end