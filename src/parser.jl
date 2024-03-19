@data BaseModelicaPart begin
    BaseModelicaRecord(name)
    BaseModelicaType(name)
    BaseModelicaPackage(name,model)
    BaseModelicaModel(name,description,parameters,variables,equations,initial_equations)
    BaseModelicaParameter(type,name,value,description)
    BaseModelicaVariable(type,name,input_or_output,description)
    BaseModelicaEquation(lhs,rhs,description)
    BaseModelicaInitialEquation(lhs,rhs,description)
    BaseModelicaFunction(name)
    BaseModelicaArray(type,length)
end

@data BaseModelicaExpr <: BaseModelicaPart begin

    # these are basically just tokens...
    BMAdd() 
    BMElementWiseAdd()
    BMSubtract()
    BMElementWiseSubtract()
    BMMult()
    BMElementWiseMult()
    BMDivide()
    BMElementWiseDivide()

    # relational tokens
    BMLessThan()
    BMGreaterThan()
    BMLEQ()
    BMGEQ()
    BMNEQ()
    BMEQ()
    BMNEQ()

    BMAND()
    BMOR()
    BMNOT()

    # nodes in the AST 
    BaseModelicaNumber(val)
    BaseModelicaIdentifier(name)
    BaseModelicaSum(left,right)
    BaseModelicaMinus(left,right)
    BaseModelicaProd(left,right)
    BaseModelicaFactor(base,exp)
    BaseModelicaElementWiseFactor(base,exp)
    BaseModelicaElementWiseProd(left,right) 
    BaseModelicaElementWiseSum(left,right) 
    BaseModelicaElementWiseMinus(top,bottom)
    BaseModelicaDivide(top,bottom)
    BaseModelicaElementWiseDivide(left,right)
    BaseModelicaParens(BaseModelicaExpr)
    BaseModelicaFunctionCall(BaseModelicaExpr)
    BaseModelicaRange(start,step,stop)

    # relational nodes
    BaseModelicaNot(relation)
    BaseModelicaAnd(left,right)
    BaseModelicaOr(left,right)
    BaseModelicaLessThan(left,right)
    BaseModelicaGreaterThan(left,right)
    BaseModelicaLEQ(left,right)
    BaseModelicaGEQ(left,right)
    BaseModelicaEQ(left,right)
    BaseModelicaNEQ(left,right)
end

#constructors 
function create_factor(input_list)
    elementwise_index = findfirst(x->  x == ".^", input_list)
    power_index = findfirst(x -> x == "^", input_list)

    if !isnothing(elementwise_index)
        base = only(input_list[begin:elementwise_index-1])
        exp = only(input_list[elementwise_index + 1 : end])
        return BaseModelicaElementWiseFactor(base,exp)
    elseif !isnothing(power_index)
        base = only(input_list[begin:power_index-1])
        exp = only(input_list[power_index + 1 : end])
        return BaseModelicaFactor(base,exp)
    elseif isnothing(elementwise_index) && isnothing(power_index)
        base = only(input_list)
        return base # return a BaseModelicaNumber or BaseModelicaIdentifier if no exp
    end
end

function create_term(input_list)
    left_el = input_list[1]
    for (i, element) in enumerate(input_list)
        left_el = @match element begin
            ::BMMult => BaseModelicaProd(left_el, input_list[i + 1]) #make a product between the previous item and next item
            ::BMElementWiseMult => BaseModelicaElementWiseProd(left_el, input_list[i + 1])
            ::BMDivide => BaseModelicaDivide(left_el, input_list[i + 1])
            ::BMElementWiseDivide =>  BaseModelicaElementWiseDivide(left_el, input_list[i + 1])
            _ => left_el
        end
    end
    left_el
end

function create_arithmetic_expression(input_list)
    left_el = input_list[1]
    for (i, element) in enumerate(input_list)
        left_el = @match element begin
            ::BMAdd => BaseModelicaSum(left_el, input_list[i + 1]) #make a sum between the previous item and next item
            ::BMElementWiseAdd => BaseModelicaElementWiseSum(left_el, input_list[i + 1])
            ::BMSubtract => BaseModelicaMinus(left_el, input_list[i + 1])
            ::BMElementWiseSubtract =>  BaseModelicaElementWiseMinus(left_el, input_list[i + 1])
            _ => left_el
        end
    end
    left_el
end

function create_relation(input_list)
    not_flag = typeof(input_list[1]) == BMNOT
    left_el = input_list[2]
    for (i, element) in enumerate(input_list)
        left_el = @match element begin
            ::BMLessThan => BaseModelicaLessThan(left_el, input_list[i+1])
            ::BMGreaterThan => BaseModelicaGreaterThan(left_el, input_list[i+1])
            ::BMLEQ => BaseModelicaLEQ(left_el,input_list[i+1])
            ::BMGEQ => BaseModelicaGEQ(left_el,input_list[i+1])
            ::BMEQ => BaseModelicaEQ(left_el,input_list[i+1])
            ::BMNEQ => BaseModelicaNEQ(left_el,input_list[i+1])
            _ => left_el
        end
    end
    if not_flag
        return BaseModelicaNot(left_el)
    else
        return left_el
    end
end

function create_logical_term(input_list)
    left_el = input_list[1]
    for (i, element) in enumerate(input_list)
        left_el = @match element begin
            ::BMAND => BaseModelicaAnd(left_el, input_list[i + 1]) #make a sum between the previous item and next item
            _ => left_el
        end
    end
    left_el
end

function create_logical_expression(input_list)
    left_el = input_list[1]
    for (i, element) in enumerate(input_list)
        left_el = @match element begin
            ::BMOR => BaseModelicaOr(left_el, input_list[i + 1]) #make a sum between the previous item and next item
            _ => left_el
        end
    end
    left_el
end

function create_simple_expression(input_list)
    @match input_list begin
        [start,":",stop] => BaseModelicaRange(start, BaseModelicaNumber(1), stop)
        [start,":",step,":",stop] => BaseModelicaRange(start, step, stop)
        _ => only(input_list)
    end
end


# function to convert "AST" to ModelingToolkit
eval_BaseModelicaArith(expr::BaseModelicaExpr) = 
    let ! = eval_BaseModelicaArith
        @match expr begin
            BaseModelicaNumber(val) => val
            BaseModelicaFactor(base,exp) => (!base) ^ (!exp)
            BaseModelicaSum(left,right) => !left + !right
            BaseModelicaMinus(left,right) => !left - !right
            BaseModelicaProd(left,right) => !left * !right
            BaseModelicaDivide(left,right) => !left / !right
            _ => nothing
        end
    end




function create_component(prefix, type, components)
    #only do parameters and Reals for now
    #eventually will need to do arbitrary base modelica types
    comp = components[1] #for now only supports one parameter/variable per statement, no "component-list"s
    if isempty(prefix)
        type = type
        name = comp[1]
        length(comp) == 2 ? description = comp[2] : description = nothing
        return BaseModelicaVariable(type,name,nothing,description)
    elseif prefix[1] == "parameter" # only do parameters and Reals for now 
        type = type
        name = comp[1]
        length(comp) > 1 ? value = comp[2] : value = nothing
        length(comp) == 3 ? description = comp[3] : description = nothing 
        return BaseModelicaParameter(type,name,value,description)
    elseif prefix[1] == "input" || prefix[1] == "output"
        type = type
        name = comp[1]
        length(comp) == 2 ? description = comp[2] : description = nothing
        return BaseModelicaVariable(type,name,prefix[1],description)
    end
end

function create_equation(equation_list)
    #so far only handles normal equations, no if, whens, or anything like that 
    #println(equation_list)
    eq = equation_list[1]
    equal_index = findfirst(x -> x == "=", eq)
    if !isnothing(equal_index)
        lhs = only(eq[begin:(equal_index-1)])
        rhs = only(eq[(equal_index+1):end]) #
    else 
        lhs = eq # hack because equations don't need to be equations in base modelica for some reason
        rhs = ""
    end
    !isempty(equation_list[2]) ? description = only(equation_list[2]) : description = ""
    BaseModelicaEquation(lhs,rhs,description)
end

function create_initial_equation(equation)
    #so far only handles normal equations, no if, whens, or anything like that 
    eq = equation[1]
    lhs = eq.lhs
    rhs = eq.rhs
    BaseModelicaInitialEquation(lhs,rhs,nothing)
end

function construct_package(input)
    name = input[1]
    input[4] isa String ? description = input[4] : description = nothing
    variables = []
    parameters = []
    equations = []
    initial_equations = []
    for thing in input
        typeof(thing) == BaseModelicaVariable ? push!(variables, thing) :
        typeof(thing) == BaseModelicaParameter ? push!(parameters, thing) :
        typeof(thing) == BaseModelicaEquation ? push!(equations, thing) :
        typeof(thing) == BaseModelicaInitialEquation ? push!(initial_equations,thing) :
        nothing
    end
    
    model = BaseModelicaModel(name,description,parameters,variables,equations,initial_equations)
    BaseModelicaPackage(name, model)
end

list2string(x) = isempty(x) ? x : reduce(*,x)
spc = Drop(Star(Space()))
# Base Modelica grammar
@with_names begin
NL = p"\r\n" | p"\n" | p"\r";
WS = p" " | p"\t" | NL;
LINE_COMMENT = p"//[^\r\n]*" + NL;
ML_COMMENT = p"/[*]([^*]|([*][^/]))*[*]/";

#lexical units, not keywords
NONDIGIT = p"_|[a-z]|[A-Z]";
DIGIT = p"[0-9]";
UNSIGNED_INTEGER = Plus(DIGIT);
Q_CHAR = NONDIGIT | DIGIT | p"[-!#$%&()*>+,./:;<>=?>@\[\]{}|~ ^]";
S_ESCAPE = p"\\['\"?\\abfnrtv]";
S_CHAR = NL | p"[^\r\n\\\"]";
Q_IDENT = (E"'" + (Q_CHAR | S_ESCAPE ) + Star(Q_CHAR | S_ESCAPE | E"\"" ) + E"'") |> list2string;
IDENT = (((NONDIGIT + Star( DIGIT | NONDIGIT )) |> list2string) | Q_IDENT) > BaseModelicaIdentifier;
STRING = E"\"" + Star( S_CHAR | S_ESCAPE ) + E"\"" |> list2string;
EXPONENT = ( e"e" | e"E" ) + ( e"+" | e"-" )[0:1] + DIGIT[1:end];
UNSIGNED_NUMBER = (DIGIT[1:end] + ( e"." + Star(DIGIT) )[0:1] + EXPONENT[0:1] |> list2string) |> (x -> BaseModelicaNumber(parse(Float64,only(x))));

#component clauses
name = (IDENT + Star(e"." + IDENT)) |> list2string;
type_specifier = E"."[0:1] + name;
type_prefix = (( e"discrete" | e"parameter" | e"constant" )[0:1] + spc + ( e"input" | e"output" )[0:1]);
array_subscripts = Delayed()
modification = Delayed()
declaration = IDENT + array_subscripts[0:1] + modification[0:1];
comment = Delayed()
component_declaration = declaration + spc + comment;
global_constant = e"constant" + type_specifier + array_subscripts[0:1] + declaration + comment;
component_list = (component_declaration & spc & Star(E"," + component_declaration));
component_reference = E"."[0:1] + IDENT + array_subscripts[0:1] + Star(E"." + IDENT + array_subscripts[0:1]);
component_clause = type_prefix[1:1,:&] + spc + type_specifier + spc + component_list[1:1,:&];
#equations

#modification
string_comment = (STRING + Star(E"+" + STRING))[0:1];
element_modification = name + modification[0:1] + string_comment;
element_modification_or_replaceable = element_modification;
decoration = E"@" + UNSIGNED_INTEGER;
argument = decoration[0:1] + element_modification_or_replaceable;
argument_list = argument + Star(E"," + argument);
class_modification = E"(" + argument_list[0:1] + E")";
expression = Delayed()
modification.matcher = (class_modification + (spc + E"=" + spc + expression)[0:1]) | (spc + E"=" + spc + expression) | (E":=" + spc + expression);

#expressions
relational_operator = (E"<" > BMLessThan) | (E"<=" > BMLEQ) | (E">" > BMGreaterThan)| (E">=" > BMGEQ)| (E"==" > BMEQ)| (E"<>" > BMNEQ);
add_operator = (E"+" > BMAdd)| (E"-" > BMSubtract) | (E".+" > BMElementWiseAdd) | (E".-" > BMElementWiseSubtract);
mul_operator = (E"*" > BMMult) | (E"/" > BMDivide) | (E".*" > BMElementWiseMult) | (E"./" > BMElementWiseDivide);

for_index = IDENT + E"in" + expression;

named_arguments = Delayed()
function_partial_application = E"function" + type_specifier + e"(" + named_arguments + e")";
function_argument = function_partial_application | expression;
function_arguments_non_first = Delayed()
function_arguments_non_first.matcher = (function_argument + (E"," + function_arguments_non_first)[0:1]) | named_arguments;
named_argument = IDENT + E"=" + function_argument;
named_arguments.matcher = named_argument + Star(E"," + named_argument);
function_partial_applications = E"function" + type_specifier + E"(" + named_arguments[0:1] + E")";
function_arguments = (expression + ((E"," + function_arguments_non_first) | (E"for" + for_index))[0:1]) |
    (function_partial_application + (E"," + function_arguments_non_first)[0:1]) |
    named_arguments;
function_call_args = e"(" + function_arguments[0:1] + e")";
output_expression_list = Delayed()
expression_list = Delayed()
array_arguments = expression + (Star(E"," + expression) | E"for" + for_index);
primary = UNSIGNED_NUMBER | STRING | e"false" | e"true" | 
    ((e"der" | e"initial" | e"pure") + function_call_args) |
    (component_reference + function_call_args[0:1]) |
    (E"(" + spc + output_expression_list + spc + E")" + array_subscripts[0:1]) |
    (e"[" + spc + expression_list + spc + Star(E";" + spc + expression_list) + spc + e"]") |
    (e"{" + spc + array_arguments + spc + e"}") |
    E"end";
factor = primary + spc + ((e"^" | e".^") + spc + primary)[0:1] |> create_factor;
term = factor + spc + Star(mul_operator + spc + factor) |> create_term; 
arithmetic_expression = add_operator[0:1] + spc + term + spc + Star(add_operator + spc + term) |> create_arithmetic_expression;

subscript = e":" | expression;
array_subscripts.matcher = E"[" + subscript + Star(E"," + subscript);
annotation_comment = E"annotation" + class_modification;
comment.matcher = string_comment + annotation_comment[0:1];

enumeration_literal = IDENT + comment;
enum_list = enumeration_literal + Star(E"," + enumeration_literal);

guess_value = E"guess" + E"(" + component_reference + E")" ;
prioritize_expression = Delayed()
parameter_equation = E"parameter equation" + guess_value + E"=" + (expression | prioritize_expression) + comment;

normal_element = component_clause;


generic_element = normal_element | parameter_equation;

language_specification = STRING;

external_function_call = (component_reference + E"=")[0:1] + IDENT + E"(" + expression_list[0:1] + E")";

equation = Delayed()
initial_equation = Delayed()
statement = Delayed()
base_partition = Delayed()
composition = Star(decoration[0:1] + generic_element + E";" + spc) + 
              Star((spc + e"equation" + spc + Star(spc + equation + E";" + spc)) |
              (e"initial equation" + spc + Star(spc + initial_equation + E";" + spc)) |
              (e"initial"[0:1] + e"algorithm" + Star(statement + E";"))) + (decoration[0:1] + E"external" + language_specification[0:1] + external_function_call[0:1] + annotation_comment[0:1] + E";")[0:1] +
              Star(base_partition) + (annotation_comment + E";")[0:1];


base_prefix = e"input" | e"output"
long_class_specifier = IDENT + spc + string_comment + spc + composition + spc + e"end" + spc + IDENT;
short_class_specifier = IDENT + E"=" + (base_prefix[0:1] + type_specifier + class_modification[0:1]) |
    (e"enumeration" + E"(" + (enum_list[0:1] | E":" ) + E")") + comment;
class_prefixes = e"type" | e"record" | ((e"pure constant")[0:1] | (e"impure")[0:1]) + e"function";
der_class_specifier = IDENT + E"=" + E" "[0:1] + E"der" + E" " + E"(" + type_specifier + E"," + IDENT + Star(E"," + IDENT) + E")" + comment;
class_specifier = long_class_specifier | short_class_specifier | der_class_specifier;
class_definition = class_prefixes + class_specifier;

clock_clause = decoration[0:1] + E"Clock" + IDENT + E"=" + expression + comment;
sub_partition = E"subpartition" + E"(" + argument_list + E")" + string_comment + (annotation_comment + E";")[0:1] + (Star(E"equation" + ((equation + E";"))) | E"algorithm" + Star(statement + E";"));
base_partition.matcher = E"partition" + string_comment + (annotation_comment + E";")[0:1] + (clock_clause + E";") + sub_partition;



#equations 

relation = arithmetic_expression + spc + (relational_operator + arithmetic_expression)[0:1];
logical_factor = (e"not"[0:1] |> (x -> !isempty(x) ? BMNOT() : nothing)) + spc + relation |> create_relation;
logical_term = logical_factor + spc + Star((E"and" > BMAND)  + spc + logical_factor) |> create_logical_term;
logical_expression = logical_term + spc + Star((E"or"> BMOR) + spc + logical_term) |> create_logical_expression;

# can be expression or a range, the : : are for ranges
simple_expression = logical_expression + spc + (e":" + spc + logical_expression + spc + (e":" + spc + logical_expression)[0:1])[0:1] |> create_simple_expression;

priority = expression;


prioritize_equation = E"prioritize" + E"(" + component_reference + E"," + priority + E")";
prioritize_expression.matcher = E"prioritize" + E"(" + expression + E"," + priority + E")";


initial_equation.matcher = (equation | prioritize_equation);

output_expression_list.matcher = expression[0:1] + Star(E"," + expression[0:1]);
expression_list.matcher = expression + Star(E"," + expression);

if_expression = Delayed()
expression_no_decoration = simple_expression | if_expression;
if_expression.matcher = 
    E"if" + expression_no_decoration +  E"then" + expression_no_decoration +
    Star(E"elseif" + expression_no_decoration + E"then" + expression_no_decoration) +
    E"else" + expression_no_decoration;

expression.matcher = expression_no_decoration + decoration[0:1];

if_equation = 
    E"if" + expression + E"then" + NL +
        Star(equation + E";") +
        Star(E"elseif" + expression + E"then" + NL +
            Star(equation + E";")
        ) +
        (E"else" + NL +
            Star(equation + E";")
        )[0:1] + NL +
        E"end if";

for_index = IDENT + E"in" + expression;

for_equation = 
    E"for" + for_index + E"loop" + NL +
        Star(equation + E";") + NL +
    E"end for";

for_statement = 
    E"for" + for_index + E"loop" + NL +
        Star(statement + E";") + NL +
    E"end for";

while_statement = 
    E"while" + expression + E"loop" + 
        Star(statement + E";") + NL +
    E"end while";

when_equation =
    E"when" + expression + E"then" + NL +
        Star(statement + E";") + NL +
    E"end when";

when_statement = 
    E"when" + expression + E"then" + NL +
        Star(statement + E";") + NL +
    Star(E"elsewhen" + expression + E"then" + NL +
        Star(statement + E";")) + NL +
    E"end when";

if_statement = 
    E"if" + expression + E"then" + NL +
       Star(statement + E";") + NL +
       Star(E"elseif" + expression + E"then" + NL +
        Star(statement + E";")) +
        (E"else" + NL +
            Star(statement + E";"))[0:1] + NL +
        E"end if";

statement.matcher = decoration[0:1] + (component_reference + (E":=" + expression | function_call_args) |
    E"(" + output_expression_list + E")" + E":=" + component_reference + function_call_args |
    E"break" |
    E"return" |
    if_statement |
    for_statement |
    while_statement |
    when_statement) + comment;

equation.matcher = ((decoration[0:1] + (simple_expression + decoration[0:1] + (spc + e"=" + spc + expression)[0:1]) |
    if_equation |
    for_equation |
    when_equation) & comment);

base_modelica = 
     (spc + E"package" + spc + IDENT + spc +
     Star((decoration[0:1] + spc + class_definition + spc + E";") |
     (decoration[0:1] + global_constant + E";")) +
     spc + decoration[0:1] + spc + e"model" + spc + long_class_specifier + E";" + 
    spc + (annotation_comment + E";")[0:1] + spc +
    e"end" + spc + IDENT + spc + E";" + spc)
end;

"""
Parses a String in to a BaseModelicaPackage.
"""
function parse_str(data)
    only(parse_one(data,base_modelica))
end

"""
Takes a path to a file and parses the contents in to a BaseModelicaPackage
"""
function parse_file(file)
    parse_str(read(file,String))
end
