@data BaseModelicaASTNode begin
    BaseModelicaType(name, fields)
    BaseModelicaPackage(name, class_defs, model)
    BaseModelicaModel(long_class_specifier)
    BaseModelicaConstant(type, name, value, description, modification)
    BaseModelicaParameter(type, name, value, description, modification)
    BaseModelicaVariable(type, name, input_or_output, description, modification)
    BaseModelicaSimpleEquation(lhs, rhs)
    BaseModelicaInitialEquation(equation) # Just holds a BaseModelicaAnyEquation and denotes that it's an initial equation
    BaseModelicaArray(type, length)
    BaseModelicaString(string)
    BaseModelicaTypeSpecifier(type)
    BaseModelicaTypePrefix(final_flag, dpc, io)
    BaseModelicaDeclaration(ident, array_subs, modification)
    BaseModelicaComponentDeclaration(declaration, comment)
    BaseModelicaComponentClause(type_prefix, type_specifier, component_list)
    BaseModelicaComponentReference(ref_list)
    BaseModelicaParameterEquation(component_reference, expression, comment)
    BaseModelicaWhenEquation(whens, thens)
    BaseModelicaForEquation(index, equations)
    BaseModelicaIfEquation(ifs, thens)
    BaseModelicaAnyEquation(equation, description)
    BaseModelicaAnnotation(annotation_content)
    BaseModelicaForIndex(ident, expression)
    BaseModelicaComposition(components, equations, initial_equations)
    BaseModelicaLongClass(name, description, composition)
    BaseModelicaModification(expr)
    #Class types
    BaseModelicaClassDefinition(class_type, class)
end

@data BaseModelicaExpr<:BaseModelicaASTNode begin
    # these are basically just tokens...
    BMAdd()
    BMElementWiseAdd()
    BMSubtract()
    BMElementWiseSubtract()
    BMMult()
    BMElementWiseMult()
    BMDivide()
    BMElementWiseDivide()
    BMColon()
    BMIf()
    BMFor()
    BMWhen()
    BMThen()
    BMLoop()
    BMequation()

    # relational tokens
    BMLessThan()
    BMGreaterThan()
    BMLEQ()
    BMGEQ()
    BMEQ()
    BMNEQ()

    BMAND()
    BMOR()
    BMNOT()

    # nodes in the AST 
    BaseModelicaNumber(val)
    BaseModelicaIdentifier(name)
    BaseModelicaSum(left, right)
    BaseModelicaMinus(left, right)
    BaseModelicaUnaryMinus(operand)
    BaseModelicaProd(left, right)
    BaseModelicaFactor(base, exp)
    BaseModelicaElementWiseFactor(base, exp)
    BaseModelicaElementWiseProd(left, right)
    BaseModelicaElementWiseSum(left, right)
    BaseModelicaElementWiseMinus(top, bottom)
    BaseModelicaDivide(top, bottom)
    BaseModelicaElementWiseDivide(left, right)
    BaseModelicaParens(BaseModelicaExpr)
    BaseModelicaFunctionArgs(args)
    BaseModelicaFunctionCall(func_name, args)
    BaseModelicaRange(start, step, stop)
    BaseModelicaArraySubscripts(subscripts)

    # relational nodes
    BaseModelicaNot(relation)
    BaseModelicaAnd(left, right)
    BaseModelicaOr(left, right)
    BaseModelicaLessThan(left, right)
    BaseModelicaGreaterThan(left, right)
    BaseModelicaLEQ(left, right)
    BaseModelicaGEQ(left, right)
    BaseModelicaEQ(left, right)
    BaseModelicaNEQ(left, right)
    BaseModelicaIfExpression(conditions, expressions)
    BaseModelicaArrayReference(term, indexes)
end

#constructors 
function create_factor(input_list)
    elementwise_index = findfirst(x -> x == ".^", input_list)
    power_index = findfirst(x -> x == "^", input_list)

    if !isnothing(elementwise_index)
        base = only(input_list[begin:(elementwise_index - 1)])
        exp = only(input_list[(elementwise_index + 1):end])
        return BaseModelicaElementWiseFactor(base, exp)
    elseif !isnothing(power_index)
        base = only(input_list[begin:(power_index - 1)])
        exp = only(input_list[(power_index + 1):end])
        return BaseModelicaFactor(base, exp)
    elseif isnothing(elementwise_index) && isnothing(power_index)
        base = isempty(input_list) ? nothing : only(input_list)
        return base # return input if no exponent operator
    end
end

function create_term(input_list)
    left_el = input_list[1]
    for (i, element) in enumerate(input_list)
        left_el = @match element begin
            ::BMMult => BaseModelicaProd(left_el, input_list[i + 1]) #make a product between the previous item and next item
            ::BMElementWiseMult => BaseModelicaElementWiseProd(left_el, input_list[i + 1])
            ::BMDivide => BaseModelicaDivide(left_el, input_list[i + 1])
            ::BMElementWiseDivide => BaseModelicaElementWiseDivide(
                left_el, input_list[i + 1])
            _ => left_el
        end
    end
    left_el
end

function create_arithmetic_expression(input_list)
    # Handle unary minus case - if first element is a minus operator
    if length(input_list) >= 2 && input_list[1] isa BMSubtract
        return BaseModelicaUnaryMinus(input_list[2])
    end

    left_el = input_list[1]
    for (i, element) in enumerate(input_list)
        left_el = @match element begin
            ::BMAdd => BaseModelicaSum(left_el, input_list[i + 1]) #make a sum between the previous item and next item
            ::BMElementWiseAdd => BaseModelicaElementWiseSum(left_el, input_list[i + 1])
            ::BMSubtract => BaseModelicaMinus(left_el, input_list[i + 1])
            ::BMElementWiseSubtract => BaseModelicaElementWiseMinus(
                left_el, input_list[i + 1])
            _ => left_el
        end
    end
    left_el
end

function create_relation(input_list)
    not_flag = input_list[1] isa BMNOT
    left_el = input_list[2]
    for (i, element) in enumerate(input_list)
        left_el = @match element begin
            ::BMLessThan => BaseModelicaLessThan(left_el, input_list[i + 1])
            ::BMGreaterThan => BaseModelicaGreaterThan(left_el, input_list[i + 1])
            ::BMLEQ => BaseModelicaLEQ(left_el, input_list[i + 1])
            ::BMGEQ => BaseModelicaGEQ(left_el, input_list[i + 1])
            ::BMEQ => BaseModelicaEQ(left_el, input_list[i + 1])
            ::BMNEQ => BaseModelicaNEQ(left_el, input_list[i + 1])
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
        [start, ":", stop] => BaseModelicaRange(start, BaseModelicaNumber(1), stop)
        [start, ":", step, ":", stop] => BaseModelicaRange(start, step, stop)
        _ => only(input_list)
    end
end

function BaseModelicaIfExpression(input_list)
    condition_list = []
    expression_list = []

    for (i, el) in enumerate(input_list)
        @match el begin
            "if" => push!(condition_list, input_list[i + 1])
            "then" => push!(expression_list, input_list[i + 1])
            "elseif" => push!(condition_list, input_list[i + 1])
            "else" => push!(expression_list, input_list[i + 1])
            _ => nothing
        end
    end
    BaseModelicaIfExpression(condition_list, expression_list)
end

function create_component_clause(input_list)
    #empty
end

function BaseModelicaArraySubscripts(input::Vector{Any})
    BaseModelicaArraySubscripts(Tuple(input))
end

function BaseModelicaFunctionCall(input)
    BaseModelicaFunctionCall(input[1], input[2:end])
end

function BaseModelicaTypePrefix(input_list)
    final_flag = nothing
    dpc = nothing
    io = nothing
    for input in input_list
        if input == "final"
            final_flag = input
        elseif input == "parameter" || input == "discrete" || input == "constant"
            dpc = input
        elseif input == ("input") || input == ("output")
            io = input
        end
    end
    BaseModelicaTypePrefix(final_flag, dpc, io)
end

function BaseModelicaSimpleEquation(input_list)
    @match input_list begin
        [lhs] => BaseModelicaSimpleEquation(lhs, nothing)
        [lhs, rhs] => BaseModelicaSimpleEquation(lhs, rhs)
        _ => nothing
    end
end

function BaseModelicaString(input_list::Array{<:Any})
    if length(input_list) == 1
        return BaseModelicaString(input_list[1])
    end
    bmstring = foldl(*, input_list, init = "")
    return BaseModelicaString(bmstring)
end

function BaseModelicaWhenEquation(input_list)
    whens = []
    thens = []
    for (i, element) in enumerate(input_list)
        @match element begin
            ::BMWhen => push!(whens, input_list[i + 1])
            ::BMThen => push!(thens, input_list[i + 1])
            _ => nothing
        end
    end
    BaseModelicaWhenEquation(whens, thens)
end

function BaseModelicaIfEquation(input_list)
    ifs = []
    thens = []
    for (i, element) in enumerate(input_list)
        @match element begin
            ::BMIf => push!(ifs, input_list[i + 1])
            ::BMThen => push!(thens, input_list[i + 1])
            _ => nothing
        end
    end
    BaseModelicaIfEquation(ifs, thens)
end

function BaseModelicaForEquation(input_list)
    index = input_list[1]
    equations = input_list[2:end]
    BaseModelicaForEquation(index, equations)
end

function BaseModelicaComposition(input_list)
    equations = []
    initial_equations = []
    components = []

    for input in input_list
        if input isa BaseModelicaComponentClause
            push!(components, input)
        elseif input isa BaseModelicaInitialEquation
            push!(initial_equations, input)
        elseif input isa BaseModelicaAnyEquation
            push!(equations, input)
        elseif input isa BaseModelicaAnnotation
        end
    end
    BaseModelicaComposition(components, equations, initial_equations)
end

function BaseModelicaPackage(input_list)
    name = input_list[1]
    model = nothing
    class_defs = []
    for input in input_list[2:end]
        if input isa BaseModelicaClassDefinition
            push!(class_defs, input)
        elseif input isa BaseModelicaModel
            model = input
        end
    end
    BaseModelicaPackage(name, class_defs, model)
end

function component_reference_or_function_call(input_list)
    if length(input_list) >= 2 && input_list[2] isa BaseModelicaFunctionArgs
        return BaseModelicaFunctionCall(input_list[1], input_list[2])
    else
        return input_list[1]
    end
end

list2string(x) = isempty(x) ? x : reduce(*, x)
spc = Drop(Star(Space()))
# Base Modelica grammar
@with_names begin
    NL = p"\r\n" | p"\n" | p"\r"
    WS = p" " | p"\t" | NL
    LINE_COMMENT = p"//[^\r\n]*" + NL
    ML_COMMENT = p"/[*]([^*]|([*][^/]))*[*]/"

    #lexical units, not keywords
    NONDIGIT = p"_|[a-z]|[A-Z]"
    DIGIT = p"[0-9]"
    UNSIGNED_INTEGER = Plus(DIGIT)
    Q_CHAR = NONDIGIT | DIGIT | p"[-!#$%&()*>+,./:;<>=?>@\[\]{}|~ ^]"
    S_ESCAPE = p"\\['\"?\\abfnrtv]"
    S_CHAR = NL | p"[^\r\n\\\"]"
    Q_IDENT = (E"'" + (Q_CHAR | S_ESCAPE) + Star(Q_CHAR | S_ESCAPE | E"\"") + E"'") |>
              list2string
    IDENT = (((NONDIGIT + Star(DIGIT | NONDIGIT)) |> list2string) | Q_IDENT) >
            BaseModelicaIdentifier
    STRING = E"\"" + Star(S_CHAR | S_ESCAPE) + E"\"" |> list2string
    EXPONENT = (e"e" | e"E") + (e"+" | e"-")[0:1] + DIGIT[1:end]
    UNSIGNED_NUMBER = (DIGIT[1:end] + (e"." + Star(DIGIT))[0:1] + EXPONENT[0:1] |>
                       list2string) |> (x -> BaseModelicaNumber(parse(Float64, only(x))))

    #component clauses
    name = Not(Lookahead(e"end")) + Not(Lookahead(E"equation")) +
           Not(Lookahead(E"initial equation")) + (IDENT + Star(e"." + IDENT)) |> list2string # Not(Lookahead(foo)) tells it that names can't be foo
    type_specifier = E"."[0:1] + name > BaseModelicaTypeSpecifier
    type_prefix = ((e"final")[0:1] + spc + (e"discrete" | e"parameter" | e"constant")[0:1] +
                   spc +
                   (e"input" | e"output")[0:1]) |> BaseModelicaTypePrefix
    array_subscripts = Delayed()
    modification = Delayed()
    declaration = IDENT & array_subscripts[0:1] & modification[0:1] >
                  BaseModelicaDeclaration
    comment = Delayed()
    component_declaration = declaration + spc + comment > BaseModelicaComponentDeclaration
    global_constant = e"constant" + type_specifier + array_subscripts[0:1] + declaration +
                      comment
    component_list = (component_declaration + spc +
                      Star(E"," + spc + component_declaration))
    component_reference = E"."[0:1] + IDENT + array_subscripts[0:1] +
                          Star(E"." + IDENT + array_subscripts[0:1]) |>
                          BaseModelicaComponentReference
    component_clause = type_prefix + spc + type_specifier + spc + component_list[1:1, :&] >
                       BaseModelicaComponentClause
    #equations

    #modification
    string_comment = (STRING + spc + Star(spc + E"+" + spc + STRING))[0:1] |>
                     BaseModelicaString
    element_modification = name + modification[0:1] + string_comment
    element_modification_or_replaceable = element_modification
    decoration = E"@" + UNSIGNED_INTEGER
    argument = decoration[0:1] + element_modification_or_replaceable
    argument_list = argument + Star(E"," + spc + argument)
    class_modification = E"(" + argument_list[0:1] + E")"
    expression = Delayed()
    modification.matcher = (class_modification + (spc + E"=" + spc + expression)[0:1]) |
                           (spc + E"=" + spc + expression) | (E":=" + spc + expression) |>
                           BaseModelicaModification

    #expressions
    relational_operator = (E"<" > BMLessThan) | (E"<=" > BMLEQ) | (E">" > BMGreaterThan) |
                          (E">=" > BMGEQ) | (E"==" > BMEQ) | (E"<>" > BMNEQ)
    add_operator = (E"+" > BMAdd) | (E"-" > BMSubtract) | (E".+" > BMElementWiseAdd) |
                   (E".-" > BMElementWiseSubtract)
    mul_operator = (E"*" > BMMult) | (E"/" > BMDivide) | (E".*" > BMElementWiseMult) |
                   (E"./" > BMElementWiseDivide)
    named_arguments = Delayed()
    function_partial_application = E"function" + type_specifier + e"(" + named_arguments +
                                   e")"
    function_argument = function_partial_application | expression
    function_arguments_non_first = Delayed()
    function_arguments_non_first.matcher = (function_argument +
                                            (E"," + function_arguments_non_first)[0:1]) |
                                           named_arguments
    named_argument = IDENT + E"=" + function_argument
    named_arguments.matcher = named_argument + Star(E"," + named_argument)
    function_partial_applications = E"function" + type_specifier + E"(" +
                                    named_arguments[0:1] + E")"
    for_index = Delayed()
    function_arguments = (expression +
                          ((E"," + function_arguments_non_first) | (E"for" + for_index))[0:1]) |
                         (function_partial_application +
                          (E"," + function_arguments_non_first)[0:1]) |
                         named_arguments |> BaseModelicaFunctionArgs
    function_call_args = E"(" + function_arguments[0:1] + E")"
    output_expression_list = Delayed()
    expression_list = Delayed()
    array_arguments = expression + (Star(E"," + expression) | E"for" + for_index)
    primary = UNSIGNED_NUMBER | STRING | e"false" | e"true" |
              ((e"der" | e"initial" | e"pure") + function_call_args |>
               component_reference_or_function_call) |
              ((component_reference + function_call_args[0:1]) |>
               component_reference_or_function_call) |
              (E"(" + spc + output_expression_list + spc + E")" + array_subscripts[0:1]) |
              (e"[" + spc + expression_list + spc + Star(E";" + spc + expression_list) +
               spc + e"]") |
              (e"{" + spc + array_arguments + spc + e"}") |
              E"end"
    factor = primary + spc + ((e"^" | e".^") + spc + primary)[0:1] |> create_factor
    term = factor + spc + Star(mul_operator + spc + factor) |> create_term
    arithmetic_expression = add_operator[0:1] + spc + term + spc +
                            Star(add_operator + spc + term) |> create_arithmetic_expression

    subscript = (E":" > BMColon) | expression
    array_subscripts.matcher = E"[" + subscript + Star(E"," + subscript) + E"]" |>
                               BaseModelicaArraySubscripts
    annotation_comment = E"annotation" + class_modification |> BaseModelicaAnnotation
    comment.matcher = (string_comment + annotation_comment[0:1]) |>
                      (x -> length(x) == 1 ? x[1] :
                            BaseModelicaString(join([string(elem) for elem in x], " ")))

    enumeration_literal = IDENT + comment
    enum_list = enumeration_literal + Star(E"," + enumeration_literal)

    guess_value = E"guess" + E"(" + component_reference + E")"
    prioritize_expression = Delayed()
    parameter_equation = E"parameter equation" + spc + guess_value + spc + E"=" + spc +
                         (expression | prioritize_expression) + comment >
                         BaseModelicaParameterEquation

    normal_element = component_clause

    generic_element = normal_element | parameter_equation

    language_specification = STRING

    external_function_call = (component_reference + E"=")[0:1] + IDENT + E"(" +
                             expression_list[0:1] + E")"

    equation = Delayed()
    initial_equation = Delayed()
    statement = Delayed()
    base_partition = Delayed()
    composition = Star(decoration[0:1] + generic_element + E";" + spc) + spc +
                  Star((spc + e"equation" + spc +
                        Star(spc + (equation | annotation_comment) + E";" + spc)) |
                       (e"initial equation" + spc +
                        Star(spc + (initial_equation | annotation_comment) + E";" + spc)) |
                       (e"initial"[0:1] + e"algorithm" + Star(statement + E";"))) +
                  (decoration[0:1] + E"external" + language_specification[0:1] + external_function_call[0:1] + annotation_comment[0:1] + E";")[0:1] +
                  Star(base_partition) + (annotation_comment + E";")[0:1] |>
                  BaseModelicaComposition

    base_prefix = e"input" | e"output"
    long_class_specifier = IDENT + spc + string_comment + spc + composition + spc + E"end" +
                           spc + Drop(IDENT) > BaseModelicaLongClass
    short_class_specifier = IDENT + spc + E"=" + spc +
                            (base_prefix[0:1] + type_specifier + class_modification[0:1])
    (e"enumeration" + E"(" + (enum_list[0:1] | E":") + E")") + comment
    class_prefixes = e"type" | e"record" |
                     ((e"pure constant")[0:1] | ((e"impure")[0:1]) + e"function")
    der_class_specifier = IDENT + E"=" + E" "[0:1] + E"der" + E" " + E"(" + type_specifier +
                          E"," + IDENT + Star(E"," + IDENT) + E")" + comment
    class_specifier = long_class_specifier | short_class_specifier | der_class_specifier
    class_definition = class_prefixes + spc + class_specifier > BaseModelicaClassDefinition

    clock_clause = decoration[0:1] + E"Clock" + IDENT + E"=" + expression + comment
    sub_partition = E"subpartition" + E"(" + argument_list + E")" + string_comment +
                    (annotation_comment + E";")[0:1] +
                    (Star(E"equation" + ((equation + E";"))) | E"algorithm" +
                     Star(statement + E";"))
    base_partition.matcher = E"partition" + string_comment +
                             (annotation_comment + E";")[0:1] + (clock_clause + E";") +
                             sub_partition

    #equations 

    relation = arithmetic_expression + spc +
               (relational_operator + arithmetic_expression)[0:1]
    logical_factor = (e"not"[0:1] |> (x -> !isempty(x) ? BMNOT() : nothing)) + spc +
                     relation |> create_relation
    logical_term = logical_factor + spc + Star((E"and" > BMAND) + spc + logical_factor) |>
                   create_logical_term
    logical_expression = logical_term + spc + Star((E"or" > BMOR) + spc + logical_term) |>
                         create_logical_expression

    # can be expression or a range, the : are for ranges
    simple_expression = logical_expression + spc +
                        (e":" + spc + logical_expression + spc + (e":" + spc + logical_expression)[0:1])[0:1] |>
                        create_simple_expression

    priority = expression

    prioritize_equation = E"prioritize" + E"(" + component_reference + E"," + priority +
                          E")"
    prioritize_expression.matcher = E"prioritize" + E"(" + expression + E"," + priority +
                                    E")"

    initial_equation.matcher = (equation | prioritize_equation) >
                               BaseModelicaInitialEquation

    output_expression_list.matcher = expression[0:1] + Star(E"," + expression[0:1])
    expression_list.matcher = expression + Star(E"," + expression)

    # Simple if_expression supporting both "elseif" and "else if"
    if_expression = e"if" + simple_expression + e"then" +
                    simple_expression +
                    Star((e"elseif" | (e"else" + e"if")) + simple_expression + e"then" +
                         simple_expression) +
                    e"else" + simple_expression |> BaseModelicaIfExpression
    expression_no_decoration = simple_expression | if_expression

    expression.matcher = expression_no_decoration + decoration[0:1]

    if_equation = (E"if" > BMIf) + expression + (E"then" > BMThen) + spc +
                  Star(equation + E";") + spc +
                  Star((E"elseif" > BMIf) + spc + expression + (E"then" > BMThen) + spc +
                       Star(spc + equation + E";")
                  ) + spc +
                  ((E"else" > BMIf) + spc + Star(spc + equation + E";")
                  )[0:1] + spc +
                  E"end if" |> BaseModelicaIfEquation

    for_index.matcher = IDENT + spc + E"in" + spc + expression > BaseModelicaForIndex

    for_equation = E"for" + spc + for_index + spc + E"loop" + spc +
                   Star(spc + equation + E";") + spc +
                   E"end for" |> BaseModelicaForEquation

    for_statement = E"for" + for_index + E"loop" + NL +
                    Star(statement + E";") + NL +
                    E"end for"

    while_statement = E"while" + expression + E"loop" +
                      Star(statement + E";") + NL +
                      E"end while"

    when_equation = (E"when" > BMWhen) + spc + expression + spc + (E"then" > BMThen) + spc +
                    Star(equation + E";" + spc) + spc +
                    Star((E"elsewhen" > BMWhen) + spc + expression + spc +
                         (E"then" > BMThen) + spc +
                         Star(equation + E";")) + spc +
                    E"end when" |> BaseModelicaWhenEquation

    when_statement = E"when" + expression + E"then" + spc +
                     Star(statement + E";") + spc +
                     Star(E"elsewhen" + expression + E"then" + NL +
                          Star(statement + E";")) + NL +
                     E"end when"

    if_statement = E"if" + expression + E"then" + NL +
                   Star(statement + E";") + NL +
                   Star(E"elseif" + expression + E"then" + NL +
                        Star(statement + E";")) +
                   (E"else" + NL + Star(statement + E";"))[0:1] + NL +
                   E"end if"

    statement.matcher = decoration[0:1] +
                        (component_reference + (E":=" + expression | function_call_args) |
                         E"(" + output_expression_list + E")" + E":=" +
                         component_reference + function_call_args |
                         E"break" |
                         E"return" |
                         if_statement |
                         for_statement |
                         while_statement |
                         when_statement) + comment

    equation.matcher = decoration[0:1] +
                       (when_equation |
                        if_equation |
                        for_equation |
                        (simple_expression + decoration[0:1] +
                         (spc + E"=" + spc + expression)[0:1]) |>
                        BaseModelicaSimpleEquation) + comment > BaseModelicaAnyEquation

    base_modelica = (Star(LINE_COMMENT) + spc + E"package" + spc + IDENT + spc +
                     Star((decoration[0:1] + spc + class_definition + spc + E";") |
                          (decoration[0:1] + global_constant + E";")) +
                     spc + decoration[0:1] + spc +
                     ((E"model" + spc + long_class_specifier + E";") > BaseModelicaModel) +
                     spc + (annotation_comment + E";")[0:1] + spc +
                     E"end" + spc + Drop(IDENT) + spc + E";" + spc) |> BaseModelicaPackage
end;

"""
Helper function to get line and column information from a string position
"""
function get_position_info(source::String, position::Int)
    lines = split(source[1:min(position, length(source))], '\n')
    line_number = length(lines)
    column_number = length(lines[end]) + 1
    return line_number, column_number
end

"""
Helper function to format error context showing the problematic lines
"""
function format_error_context(source::String, position::Int; context_lines = 2)
    lines = split(source, '\n')
    line_num, col_num = get_position_info(source, position)

    start_line = max(1, line_num - context_lines)
    end_line = min(length(lines), line_num + context_lines)

    result = String[]
    for i in start_line:end_line
        if i == line_num
            push!(result, "→ $(lines[i])")
            # Add pointer to the error position
            pointer = " " ^ (col_num + 1) * "^" *
                      repeat("~", max(0, min(9, length(lines[i]) - col_num)))
            push!(result, pointer)
        else
            push!(result, "  $(lines[i])")
        end
    end

    return join(result, '\n')
end

"""
Parses a String in to a BaseModelicaPackage.
"""
function parse_str(data)
        debug, task = make(Debug, data, base_modelica; delegate = NoCache)

    try
        result = parse_one(data, base_modelica, debug = debug)

        if isempty(result)
            # Get error position and context
            error_pos = debug.max_iter
            line_num, col_num = get_position_info(data, error_pos)
            context = format_error_context(data, error_pos)

            error_msg = """
            Failed to parse BaseModelica at line $line_num, column $col_num.

            Error context:
            $context

            Parser stopped at position $error_pos of $(length(data))
            """

            throw(ParserCombinator.ParserException(error_msg))
        end

        return only(result)
    catch e
        if isa(e, ParserCombinator.ParserException) && e.msg == "cannot parse"
            # Generic error - enhance with location information
            error_pos = debug.max_iter
            line_num, col_num = get_position_info(data, error_pos)
            context = format_error_context(data, error_pos)

            error_msg = """
            Failed to parse BaseModelica at line $line_num, column $col_num.

            Error context:
            $context

            Parser stopped at position $error_pos of $(length(data))
            """

            throw(ParserCombinator.ParserException(error_msg))
        else
            rethrow(e)
        end
    end
end

"""
Takes a path to a file and parses the contents in to a BaseModelicaPackage
"""
function parse_file(file)
    content = read(file, String)
    try
        return parse_str(content)
    catch e
        if isa(e, ParserCombinator.ParserException)
            # Add filename to the error message
            error_msg = "Error in file: $file\n" * e.msg
            throw(ParserCombinator.ParserException(error_msg))
        else
            rethrow(e)
        end
    end
end

# Custom error display for ParserException to properly render newlines
function Base.showerror(io::IO, e::ParserCombinator.ParserException)
    print(io, "ParserException: ")
    # Print the message with proper newline rendering
    println(io, e.msg)
end
