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

parse_one("output Real 'juice'",component_clause)
parse_one("Real 'juice' \"the real juice\"",component_clause)
parse_one("parameter Real 'juice' = 45,'juicier' = 56;",Trace(component_clause))
parse_one("parameter output Real 'juice' = 49 \"description for juice 49\";",component_clause)
parse_dbg("parameter output Real 'juice' = 5;",Trace(component_clause))

parse_one("'locomotive' + 'doopers' = 'jeepers' \"holy creepers\";", equation)
parse_one("'locomotive' + 'loco'", equation)


parse_dbg("Real 'juicier' ;", component_clause)

parse_one("x*y",term)

parse_one("parameter", type_prefix)

parse_one("3+ 5 -3/ 4*5+787 -10", arithmetic_expression)

eeps = e"eeps" + e"peeps"
parse_one("abeepspeepseepspeeps", e"a" + e"b" + eeps[1:end,:&])