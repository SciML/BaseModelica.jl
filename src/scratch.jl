parse_one("\n", NL)
parse_one("h", NONDIGIT)
parse_one("4",DIGIT)
parse_one("342534",UNSIGNED_INTEGER)
parse_one("8",Q_CHAR)
parse_one("'eepers_jeepers'",Q_IDENT)
parse_one("oopsers",IDENT)
parse_one("'eepers_jeepers'",IDENT)
parse_one("28342.532842e45",UNSIGNED_NUMBER)
parse_one("\" eepers jeepers peeper \"", STRING)
parse_one("joop.jeep",name)

parse_one("parameter input", type_prefix)
parse_one("parameter",type_prefix)
parse_one("parameter Real 'juice' \"juice\";", component_clause)

parse_one("output Real 'juice' \"juicy\";",component_clause)
parse_one("Real 'juice' \"the real juice\";",component_clause)
parse_one("parameter Real 'juice' = 45,'juicier' = 56;",Trace(component_clause))
parse_one("parameter output Real 'juice' = 49 \"description for juice 49\";",component_clause)
parse_dbg("parameter output Real 'juice' = 5;",Trace(component_clause))

parse_one("'locomotive' + 'doopers' = 'jeepers' \"holy creepers\";", equation)
parse_one("'locomotive' + 'loco'", equation)

parse_one("parameter Real 'juice' = 34;", generic_element)
parse_one("Real 'juice' \"juicy\";",generic_element)
parse_one("parameter Real 'dop' = 6; Real 'juice' \"juicy\"; \n Real 'fruit' \"fruity\"; \n parameter Real 'doop' = 60;",composition)
parse_one("parameter Real 'juice' = 34;", component_clause)

parse_one("x*y",term)

parse_one("parameter", type_prefix)

parse_one("3+ 5 -3/ 4*5+787 -10", arithmetic_expression)

eeps = e"eeps" + e"peeps"
parse_one("abeepspeepseepspeeps", e"a" + e"b" + eeps[1:end,:&])

parse_one("3+ ( 4 - 32 ) / 2 = 3", equation)

parse_one("""
Real 'juice.juice' \"juicy\"; 
Real 'fruit' \"fruity\";
output Real 'output_fruit';
parameter Real 'doop' = 60;
equation
('juice'+'fruit')*'blade' = 'puree';
'juicy' * 'fruit' = 'juicyfruit';
""", composition)

parse_one("""JuiceModel
Real 'juice.juice' \"juicy\"; 
Real 'fruit' \"fruity\";
output Real 'output_fruit';
parameter Real 'doop' = 60;
equation
('juice'+'fruit')*'blade' = 'puree';
'juicy' * 'fruit' = 'juicyfruit';
end JuiceModel;
""", long_class_specifier, debug = true)

parse_dbg("""
package JuiceModel
    model JuiceModel
    Real 'juice.juice' \"juicy\"; 
    Real 'fruit' \"fruity\";
    output Real 'output_fruit';
    parameter Real 'doop' = 60;
    equation
    ('juice'+'fruit' + 100.0)*'blade' = 'puree';
    'juicy' * 'fruit' = 'juicyfruit';
    initial equation
    'juicy' = 1000;
    end JuiceModel;
end JuiceModel;
end JuiceModel;"""
,Trace(base_modelica))

parse_one("""
package JuiceModel
    model JuiceModel
    end JuiceModel;
end JuiceModel;""",base_modelica)


parse_one("juice 
end juice;", long_class_specifier)

parse_one("('juice' + 'juice2')/2", relation)

parse_one("'juice'= 4;",composition)

parse_one("""initial equation
'juice' = 4;""",composition)

parse_lines("""equation
'juice' = 'juice_right';
'drink' = 'drink';""",composition)

parse_one("'juice.juice'",name)

parse_one(".",Q_CHAR)
