parse_one("'x'.^2",factor, debug = true)
parse_one("('stone'+'rock').^(5 + 5)",factor)
parse_one("2",UNSIGNED_NUMBER,debug = true)

parse_one("4*2*4 .*2",term)

parse_one("4.9",factor)
parse_one("'x'",factor)
parse_one("'juice'^'eeep'",factor)
parse_one("8*9*3*3",term)
parse_one("5*'x'+8*(3 + 'y')",arithmetic_expression)
parse_one("(3 * 5)",primary)

parse_one("x*(z + y)",arithmetic_expression)
parse_one("'x'*('z' + 'y')",expression)

parse_one("20.89", UNSIGNED_NUMBER)

eval_BaseModelicaArith(only(parse_one("1^5", arithmetic_expression)))

parse_one("5^5",arithmetic_expression)[1]

parse_one("4.0",arithmetic_expression)[1]

eval_BaseModelicaArith(BaseModelicaNumber(45))

eval_AST(only(parse_one("5 + 6*(45 + 9^2)^2", arithmetic_expression)))

eval_AST(only(parse_one("5 + 6*(32 + 100)", arithmetic_expression)))
eval_AST(only(parse_one("5 + 6*(45 + 9^2)^2", arithmetic_expression)))

parse_one("5 > 6",relation)
parse_one("4 < 5",relation)
parse_one("4 <> 5",relation)
parse_one("3 >= 3 ",relation)
parse_one("3 <= 5", relation)
parse_one("3 == 3",relation)

parse_one("(4 + 5) < (6 + 6)",logical_factor, debug = true)

parse_one("5 < 5", logical_factor)
parse_one("(5 + 9) > (7-2)", logical_factor)
parse_one("not (5*9) < (4+3)", logical_factor)

parse_one("4 and 9", logical_term)
parse_one("4 or 9", logical_expression)
parse_one("(4 > 9) and (4 < 6)",logical_expression)
parse_one("4 == 5", simple_expression)

parse_one("3:4:5", simple_expression)

parse_one("if 4>5 then 8 elseif 4<7 then 5 else 6",if_expression, debug = true)

parse_one("""'R'
Real 'x';
end 'R'""", long_class_specifier,debug = true)

parse_one("parameter input Real 'x' \"goop\";", component_clause)

parse_one("'x'[4,4,:]", declaration)

parse_one("\"string\"",string_comment)
parse_one("[3,4,6,:]", array_subscripts,debug = true)

parse_one("'z'[4,5,6] \"z3\"", component_declaration)

parse_one("'z', 'x'", component_list)

parse_one("parameter Real 'x','y','z'", component_clause)

parse_one("parameter Real 'x' = 43 \"the worst parameter\"",component_clause)
parse_one("parameter Real 'x'[3]", component_clause)

parse_one("'x'[1].'y'[4]", component_reference)

parse_one("parameter equation guess('x') = 4", parameter_equation,debug = true)

parse_one("1 + 4*3 = 100/2", equation)
parse_one("'y' = 5", equation,debug = true)

parse_one("""when 'x' == 5 then
'y' = 5;
elsewhen 'y' == 20 then
'x' = 30;
end when""",when_equation, debug = true)

parse_one("""if 'x' == 5 then
'y' = 4;
elseif 'x' == 21 then
'y' = 6;
end if""",if_equation, debug = true)

parse_one("\"string\" + \"otherstring\"",comment, debug = true)

parse_one("x in 1:3", for_index)

parse_one("""for x in 1:3 loop
 'y' = 21;
 'x' = 31 + x;
end for""", for_equation)

parse_one("""parameter Real 'wagon' = 1000 \"Mass\";
 Real 'other_wagon' \"other wagon\";
equation 
 'wagon' = 5;
 'y' = 6;
initial equation 
 'x' = 'wagon';
""",composition, debug = true)

parse_one("'x'", name)

parse_one("""package 'Train'
model 'Train' 
parameter Real 'wagon' = 1000 \"Mass\";
Real 'other_wagon' \"other wagon\";
equation 
'wagon' = 5;
'y' = 6;
initial equation 
'x' = 'wagon';
end 'Train';
end 'Train';""",base_modelica)

parse_one("'x' = 21", equation)

eval_AST(only(parse_one("(4 + 5) < (6 + 6)",logical_factor, debug = true)))

parse_one("5 < 5", logical_factor)
eval_AST(only(parse_one("(5 + 9) > (7-2)", logical_factor)))
eval_AST(only(parse_one("not (5*1) < (4+3)", logical_factor)))
eval_AST(only(parse_one("4 == 4", logical_factor)))
eval_AST(only(parse_one("4 <> 4", logical_factor)))
eval_AST(only(parse_one("4 == 6", logical_factor)))
eval_AST(only(parse_one("4 <> 6", logical_factor)))

parse_one("""record 'R'
    Real 'x';
end 'R';
""", class_definition)

parse_one("record",class_prefixes)

parse_one("""record 'R' "a record that is a record"
    Real 'x';
end 'R';
""", class_definition)

parse_one("""package 'Train'
record 'R'
    Real 'x';
end 'R';
model 'Train' 
parameter Real 'wagon' = 1000 \"Mass\";
Real 'other_wagon' \"other wagon\";
equation 
'wagon' = 5;
'y' = 6;
initial equation 
'x' = 'wagon';
end 'Train';
end 'Train';""",base_modelica)

parse_one("""'Train' 
parameter Real 'wagon' = 1000 \"Mass\";
Real 'other_wagon' \"other wagon\";
equation 
'wagon' = 5;
'y' = 6;
end 'Train'
""", long_class_specifier)