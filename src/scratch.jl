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

parse_one("'x'*('z' + 'y')",arithmetic_expression)
parse_one("'x'*('z' + 'y')",expression)

parse_one("20.89", UNSIGNED_NUMBER)

eval_BaseModelicaArith(only(parse_one("1^5", arithmetic_expression)))

parse_one("5^5",arithmetic_expression)[1]

parse_one("4.0",arithmetic_expression)[1]

eval_BaseModelicaArith(BaseModelicaNumber(45))

eval_BaseModelicaArith(only(parse_one("5 + 6*(45 + 9^2)^2", arithmetic_expression)))

eval_BaseModelicaArith(only(parse_one("5 + 6*(32 + 100)", arithmetic_expression)))
eval_BaseModelicaArith(only(parse_one("5 + 6*(45 + 9^2)^2", arithmetic_expression)))

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