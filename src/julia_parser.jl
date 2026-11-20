#constructors
# Helper to parse modification into (class_modifications, expr) structure
function parse_modification(parts)
    class_mods = []
    expr = []

    for part in parts
        if isa(part, Vector) && !isempty(part)
            # This is the argument_list from class_modification
            for item in part
                if isa(item, BaseModelicaClassModificationArg)
                    push!(class_mods, item)
                end
            end
        elseif isa(part, BaseModelicaClassModificationArg)
            push!(class_mods, part)
        elseif isa(part, BaseModelicaExpr) || isa(part, BaseModelicaASTNode)
            # This is an expression
            push!(expr, part)
        end
    end

    return BaseModelicaModification(class_mods, expr)
end

# Helper to wrap class_modification arguments in BaseModelicaModification for annotations
function wrap_annotation_content(args)
    if isnothing(args) || (isa(args, Vector) && isempty(args))
        return BaseModelicaModification([], [])
    elseif isa(args, Vector)
        return BaseModelicaModification(args, [])
    else
        return BaseModelicaModification([args], [])
    end
end

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
                left_el, input_list[i + 1]
            )
            _ => left_el
        end
    end
    return left_el
end

function create_arithmetic_expression(input_list)
    # A leading add operator is unary: it applies to the first term only, and the
    # remaining `op term` pairs are then folded left onto it as usual.
    start = 1
    left_el = input_list[1]
    if length(input_list) >= 2 && input_list[1] isa Union{BMAdd, BMElementWiseAdd}
        left_el = input_list[2]
        start = 2
    elseif length(input_list) >= 2 &&
            input_list[1] isa Union{BMSubtract, BMElementWiseSubtract}
        left_el = BaseModelicaUnaryMinus(input_list[2])
        start = 2
    end

    for i in start:length(input_list)
        element = input_list[i]
        left_el = @match element begin
            ::BMAdd => BaseModelicaSum(left_el, input_list[i + 1]) #make a sum between the previous item and next item
            ::BMElementWiseAdd => BaseModelicaElementWiseSum(left_el, input_list[i + 1])
            ::BMSubtract => BaseModelicaMinus(left_el, input_list[i + 1])
            ::BMElementWiseSubtract => BaseModelicaElementWiseMinus(
                left_el, input_list[i + 1]
            )
            _ => left_el
        end
    end
    return left_el
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
    return left_el
end

function create_logical_expression(input_list)
    left_el = input_list[1]
    for (i, element) in enumerate(input_list)
        left_el = @match element begin
            ::BMOR => BaseModelicaOr(left_el, input_list[i + 1]) #make a sum between the previous item and next item
            _ => left_el
        end
    end
    return left_el
end

function create_simple_expression(input_list)
    return @match input_list begin
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
    return BaseModelicaIfExpression(condition_list, expression_list)
end

function create_component_clause(input_list)
    #empty
end

function BaseModelicaArraySubscripts(input::Vector{Any})
    return BaseModelicaArraySubscripts(Tuple(input))
end

function BaseModelicaFunctionCall(input)
    return BaseModelicaFunctionCall(input[1], input[2:end])
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
    return BaseModelicaTypePrefix(final_flag, dpc, io)
end

function BaseModelicaSimpleEquation(input_list)
    return @match input_list begin
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
    # input_list: BMWhen, condition, BMThen, equations..., [BMWhen, condition, BMThen, ...]
    whens = []
    thens = []
    expect_condition = false
    for element in input_list
        if element isa BMWhen
            expect_condition = true
        elseif element isa BMThen
            push!(thens, [])
        elseif expect_condition
            push!(whens, element)
            expect_condition = false
        else
            push!(thens[end], element)
        end
    end
    return BaseModelicaWhenEquation(whens, thens)
end

function BaseModelicaIfEquation(input_list)
    ifs = []
    thens = []
    current_equations = []
    collecting_equations = false
    expecting_condition = false

    for element in input_list
        @match element begin
            ::BMIf => begin
                # Save accumulated equations for previous branch
                if collecting_equations
                    push!(thens, current_equations)
                    current_equations = []
                    collecting_equations = false
                end
                expecting_condition = true
            end
            ::BMThen => begin
                # Save accumulated equations for previous branch (if any)
                if collecting_equations
                    push!(thens, current_equations)
                    current_equations = []
                end
                collecting_equations = true
            end
            _ => begin
                if expecting_condition
                    push!(ifs, element)
                    expecting_condition = false
                elseif collecting_equations
                    push!(current_equations, element)
                end
            end
        end
    end

    # Save last branch's equations
    if collecting_equations && !isempty(current_equations)
        push!(thens, current_equations)
    end

    return BaseModelicaIfEquation(ifs, thens)
end

function BaseModelicaForEquation(input_list)
    index = input_list[1]
    equations = input_list[2:end]
    return BaseModelicaForEquation(index, equations)
end

function build_if_statement(input_list)
    conditions = []
    branches = []
    expect_condition = false
    for el in input_list
        if el isa BMIf
            expect_condition = true
        elseif el isa BMThen  # marks the else branch
            push!(branches, [])
        elseif expect_condition
            push!(conditions, el)
            push!(branches, [])
            expect_condition = false
        else
            push!(branches[end], el)
        end
    end
    return BaseModelicaIfStatement(conditions, branches)
end

function build_algorithm_section(input_list)
    initial = !isempty(input_list) && input_list[1] == "initial"
    statements = [x for x in input_list if !(x isa AbstractString)]
    return BaseModelicaAlgorithmSection(statements, initial)
end

function build_array_constructor(input_list)
    if any(x -> x isa BaseModelicaForIndex, input_list)
        expr, index = input_list
        return BaseModelicaArrayComprehension(expr, index)
    end
    return BaseModelicaArrayConstructor(collect(input_list))
end

# `f(expr for i in range)` is `f({expr for i in range})`
function build_function_args(input_list)
    if length(input_list) == 2 && input_list[2] isa BaseModelicaForIndex
        return BaseModelicaFunctionArgs(Any[BaseModelicaArrayComprehension(input_list...)])
    end
    return BaseModelicaFunctionArgs(input_list)
end

# The parse results of `(expr)`, `(expr)[subscripts]` or the tuple `(a, b)`
function build_parenthesized(input_list)
    if length(input_list) == 2 && input_list[2] isa BaseModelicaArraySubscripts
        return Any[BaseModelicaArrayReference(input_list...)]
    end
    return input_list
end

function BaseModelicaComposition(input_list)
    equations = []
    initial_equations = []
    components = []
    parameter_equations = []
    annotation = nothing

    for input in input_list
        if input isa BaseModelicaComponentClause
            push!(components, input)
        elseif input isa BaseModelicaParameterEquation
            push!(parameter_equations, input)
        elseif input isa BaseModelicaInitialEquation
            push!(initial_equations, input)
        elseif input isa BaseModelicaAnyEquation || input isa BaseModelicaAlgorithmSection
            push!(equations, input)
        elseif input isa BaseModelicaAnnotation
            annotation = input
        end
    end
    return BaseModelicaComposition(components, equations, initial_equations, parameter_equations, annotation)
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
    return BaseModelicaPackage(name, class_defs, model)
end

function component_reference_or_function_call(input_list)
    if length(input_list) >= 2 && input_list[2] isa BaseModelicaFunctionArgs
        return BaseModelicaFunctionCall(input_list[1], input_list[2])
    else
        return input_list[1]
    end
end

list2string(x) = isempty(x) ? x : reduce(*, x)
# Whitespace and comments between tokens. Comments must be skipped here: a comment the
# grammar cannot consume makes the parse fail, and with NoCache the parser then
# backtracks through every alternative, which takes minutes on larger models.
spc = Drop(Star(Space() | p"//[^\r\n]*" | p"/[*]([^*]|[*]+[^*/])*[*]+/"))
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
    EXPONENT = (e"e" | e"E") + p"[+-]"[0:1] + DIGIT[1:end]
    UNSIGNED_NUMBER = (
        DIGIT[1:end] + (e"." + Star(DIGIT))[0:1] + EXPONENT[0:1] |>
            list2string
    ) |> (x -> BaseModelicaNumber(parse(Float64, only(x))))

    #component clauses
    name = Not(Lookahead(e"end")) + Not(Lookahead(E"equation")) +
        Not(Lookahead(E"initial equation")) + Not(Lookahead(E"algorithm")) +
        Not(Lookahead(E"initial algorithm")) + (IDENT + Star(e"." + IDENT)) |> list2string # Not(Lookahead(foo)) tells it that names can't be foo
    type_specifier = E"."[0:1] + name |>
        function (input)
        n = last(input)  # name result, possibly after "."
        s = n isa BaseModelicaIdentifier ? n.name : string(n)
        return BaseModelicaTypeSpecifier(s)
    end
    type_prefix = (
        (e"final")[0:1] + spc + (e"discrete" | e"parameter" | e"constant")[0:1] +
            spc +
            (e"input" | e"output")[0:1]
    ) |> BaseModelicaTypePrefix
    array_subscripts = Delayed()
    modification = Delayed()
    declaration = IDENT & array_subscripts[0:1] & modification[0:1] >
        BaseModelicaDeclaration
    comment = Delayed()
    component_declaration = declaration + spc + comment > BaseModelicaComponentDeclaration
    global_constant = e"constant" + type_specifier + array_subscripts[0:1] + declaration +
        comment
    component_list = (
        component_declaration + spc +
            Star(E"," + spc + component_declaration)
    )
    component_reference = E"."[0:1] + IDENT + array_subscripts[0:1] +
        Star(E"." + IDENT + array_subscripts[0:1]) |>
        BaseModelicaComponentReference
    component_clause = type_prefix + spc + type_specifier + spc + component_list[1:1, :&] >
        BaseModelicaComponentClause
    #equations

    #modification
    string_comment = (STRING + spc + Star(spc + E"+" + spc + STRING))[0:1] |>
        BaseModelicaString
    element_modification = name + modification[0:1] + Drop(string_comment) |>
        (args -> BaseModelicaClassModificationArg(args[1], length(args) > 1 ? args[2] : nothing))
    element_modification_or_replaceable = element_modification
    decoration = E"@" + UNSIGNED_INTEGER
    argument = decoration[0:1] + element_modification_or_replaceable
    argument_list = argument + Star(E"," + spc + argument)
    class_modification = E"(" + argument_list[0:1] + E")"
    expression = Delayed()
    modification.matcher = (class_modification + (spc + E"=" + spc + expression)[0:1]) |
        (spc + E"=" + spc + expression) | (E":=" + spc + expression) |>
        parse_modification

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
    function_arguments_non_first.matcher = named_arguments | (
        function_argument +
            (E"," + function_arguments_non_first)[0:1]
    ) |
        named_arguments
    named_argument = spc + IDENT + spc + E"=" + function_argument > BaseModelicaNamedArgument
    named_arguments.matcher = named_argument + Star(E"," + named_argument)
    function_partial_applications = E"function" + type_specifier + E"(" +
        named_arguments[0:1] + E")"
    for_index = Delayed()
    function_arguments = named_arguments | (
        expression +
            ((E"," + function_arguments_non_first) | (E"for" + for_index))[0:1]
    ) |
        (
        function_partial_application +
            (E"," + function_arguments_non_first)[0:1]
    ) |
        named_arguments |> build_function_args
    function_call_args = E"(" + function_arguments[0:1] + E")"
    output_expression_list = Delayed()
    expression_list = Delayed()
    # `|` and `+` have the same precedence in Julia, so the `for` alternative needs its own
    # parentheses (without them every array constructor required a for-index).
    # One row of a matrix constructor, kept together as a single list
    matrix_row = expression_list |> (row -> collect(Any, row))
    array_arguments = expression + spc +
        (Star(E"," + expression + spc) | (E"for" + spc + for_index))
    primary = UNSIGNED_NUMBER | STRING | (e"false" > BaseModelicaBool) | (e"true" > BaseModelicaBool) |
        (
        ((e"der" | e"initial" | e"pure") > BaseModelicaIdentifier) + function_call_args |>
            component_reference_or_function_call
    ) |
        (
        (component_reference + function_call_args[0:1]) |>
            component_reference_or_function_call
    ) |
        ParserCombinator.Transform(
        E"(" + spc + output_expression_list + spc + E")" + array_subscripts[0:1],
        build_parenthesized
    ) |
        (
        E"[" + spc + matrix_row + spc + Star(E";" + spc + matrix_row) +
            spc + E"]" |> BaseModelicaMatrixConstructor
    ) |
        (E"{" + spc + array_arguments + spc + E"}" |> build_array_constructor) |
        E"end"
    factor = primary + spc + ((e"^" | e".^") + spc + primary)[0:1] |> create_factor
    term = factor + spc + Star(mul_operator + spc + factor) |> create_term
    arithmetic_expression = add_operator[0:1] + spc + term + spc +
        Star(add_operator + spc + term) |> create_arithmetic_expression

    subscript = (spc + E":" + spc > BMColon) | expression
    array_subscripts.matcher = E"[" + subscript + Star(E"," + subscript) + E"]" |>
        BaseModelicaArraySubscripts
    annotation_comment = E"annotation" + class_modification |>
        (args -> BaseModelicaAnnotation(wrap_annotation_content(args)))
    # A comment is its annotation if it has one (`annotation(Evaluate = true)` on a component
    # changes how it is translated), and its string comment otherwise.
    comment.matcher = (string_comment + annotation_comment[0:1]) |> (x -> x[end])

    enumeration_literal = IDENT + comment
    enum_list = enumeration_literal + Star(E"," + spc + enumeration_literal)

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
    statement_block = Star(spc + statement + spc + E";") + spc
    base_partition = Delayed()
    composition = Star(decoration[0:1] + generic_element + E";" + spc) + spc +
        Star(
        (
            spc + e"equation" + spc +
                Star(spc + (annotation_comment | equation) + E";" + spc)
        ) |
            (
            e"initial equation" + spc +
                Star(spc + (annotation_comment | initial_equation) + E";" + spc)
        ) |
            (
            spc + e"initial"[0:1] + spc + E"algorithm" + statement_block |>
                build_algorithm_section
        )
    ) +
        (decoration[0:1] + E"external" + language_specification[0:1] + external_function_call[0:1] + annotation_comment[0:1] + E";")[0:1] +
        Star(base_partition) + (annotation_comment + E";")[0:1] |>
        BaseModelicaComposition

    base_prefix = e"input" | e"output"
    long_class_specifier = IDENT + spc + string_comment + spc + composition + spc + E"end" +
        spc + Drop(IDENT) > BaseModelicaLongClass
    short_class_enum = IDENT + spc + E"=" + spc +
        e"enumeration" + E"(" + (enum_list[0:1] | E":") + E")" + comment |>
        function (input_list)
        name = input_list[1].name
        values = [x.name for x in input_list[2:end] if x isa BaseModelicaIdentifier]
        return BaseModelicaEnumeration(name, values)
    end
    short_class_specifier = short_class_enum |
        (
        IDENT + spc + E"=" + spc +
            (base_prefix[0:1] + type_specifier + class_modification[0:1]) + comment |>
            (
            input_list -> BaseModelicaLongClass(
                input_list[1].name, "", BaseModelicaComposition([], [], [], [], nothing)
            )
        )
    )
    class_prefixes = e"type" | e"record" |
        ((e"pure" | e"impure")[0:1] + spc + e"constant"[0:1] + spc + e"function" |>
            (x -> join(x, " ")))
    der_class_specifier = IDENT + E"=" + E" "[0:1] + E"der" + E" " + E"(" + type_specifier +
        E"," + IDENT + Star(E"," + IDENT) + E")" + comment
    class_specifier = long_class_specifier | short_class_specifier | der_class_specifier
    class_definition = class_prefixes + spc + class_specifier > BaseModelicaClassDefinition

    clock_clause = decoration[0:1] + E"Clock" + IDENT + E"=" + expression + comment
    sub_partition = E"subpartition" + E"(" + argument_list + E")" + string_comment +
        (annotation_comment + E";")[0:1] +
        (
        Star(E"equation" + ((equation + E";"))) | E"algorithm" +
            Star(statement + E";")
    )
    base_partition.matcher = E"partition" + string_comment +
        (annotation_comment + E";")[0:1] + (clock_clause + E";") +
        sub_partition

    #equations

    relation = arithmetic_expression + spc +
        (relational_operator + spc + arithmetic_expression)[0:1]
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

    # if_expression: then/else values use spc + expression to support nested
    # if-expressions as then-values (e.g. `if A then if B then C else D else E`)
    # spc before keywords handles whitespace when then-value is an if_expression
    # (which doesn't consume trailing whitespace unlike simple_expression)
    if_expression = e"if" + simple_expression + e"then" +
        spc + expression +
        Star(
        spc + e"elseif" + simple_expression + e"then" +
            spc + expression
    ) +
        spc + e"else" + spc + expression |> BaseModelicaIfExpression
    expression_no_decoration = if_expression | simple_expression

    expression.matcher = spc + expression_no_decoration + decoration[0:1]

    # Guarded equation for if-equation blocks: consume whitespace, then check
    # that we're not at a block-ending keyword before trying to match an equation.
    # This prevents exponential backtracking with NoCache.
    guarded_eq = spc + Not(Lookahead(e"elseif")) + Not(Lookahead(e"else")) +
        Not(Lookahead(E"end if")) + equation + E";"
    if_equation = (E"if" > BMIf) + expression + (E"then" > BMThen) +
        Star(guarded_eq) + spc +
        Star(
        spc + (E"elseif" > BMIf) + spc + expression + (E"then" > BMThen) +
            Star(guarded_eq)
    ) + spc +
        (
        spc + (E"else" > BMThen) + Star(guarded_eq)
    )[0:1] + spc +
        E"end if" |> BaseModelicaIfEquation

    for_index.matcher = IDENT + spc + E"in" + spc + expression > BaseModelicaForIndex

    for_equation = E"for" + spc + for_index + spc + E"loop" + spc +
        Star(spc + equation + E";") + spc +
        E"end for" |> BaseModelicaForEquation

    for_statement = E"for" + spc + for_index + spc + E"loop" + statement_block +
        E"end" + spc + E"for" |> (x -> BaseModelicaForStatement(x[1], x[2:end]))

    while_statement = E"while" + expression + spc + E"loop" + statement_block +
        E"end" + spc + E"while" |> (_ -> BaseModelicaUnsupportedStatement("while loop"))

    when_equation = (E"when" > BMWhen) + spc + expression + spc + (E"then" > BMThen) + spc +
        Star(equation + E";" + spc) + spc +
        Star(
        (E"elsewhen" > BMWhen) + spc + expression + spc +
            (E"then" > BMThen) + spc +
            Star(equation + E";")
    ) + spc +
        E"end when" |> BaseModelicaWhenEquation

    when_statement = E"when" + expression + spc + E"then" + statement_block +
        Star(E"elsewhen" + expression + spc + E"then" + statement_block) +
        E"end" + spc + E"when" |> (_ -> BaseModelicaUnsupportedStatement("when statement"))

    if_statement = (E"if" > BMIf) + expression + spc + E"then" + statement_block +
        Star((E"elseif" > BMIf) + expression + spc + E"then" + statement_block) +
        ((E"else" > BMThen) + statement_block)[0:1] +
        E"end" + spc + E"if" |> build_if_statement

    assignment_statement = component_reference + spc + E":=" + expression |>
        (x -> BaseModelicaAssignment(x[1], x[2]))
    call_statement = component_reference + function_call_args |>
        (x -> BaseModelicaFunctionCall(x[1].ref_list[1], length(x) > 1 ? x[2] : BaseModelicaFunctionArgs([])))
    multiple_output_statement = E"(" + output_expression_list + E")" + spc + E":=" + spc +
        component_reference + function_call_args |>
        (_ -> BaseModelicaUnsupportedStatement("multiple-output assignment"))

    statement.matcher = Drop(decoration[0:1]) +
        (
        if_statement |
            for_statement |
            while_statement |
            when_statement |
            (E"break" |> (_ -> BaseModelicaUnsupportedStatement("break"))) |
            (E"return" |> (_ -> BaseModelicaUnsupportedStatement("return"))) |
            multiple_output_statement |
            assignment_statement |
            call_statement
    ) + Drop(comment)

    equation.matcher = decoration[0:1] +
        (
        when_equation |
            if_equation |
            for_equation |
            (
            simple_expression + decoration[0:1] +
                (spc + E"=" + spc + expression)[0:1]
        ) |>
            BaseModelicaSimpleEquation
    ) + comment > BaseModelicaAnyEquation

    base_modelica = (
        Star(LINE_COMMENT) + spc + E"package" + spc + IDENT + spc +
            Star(
            (decoration[0:1] + spc + class_definition + spc + E";") |
                (decoration[0:1] + global_constant + E";")
        ) +
            spc + decoration[0:1] + spc +
            ((E"model" + spc + long_class_specifier + E";") > BaseModelicaModel) +
            spc + (annotation_comment + E";")[0:1] + spc +
            E"end" + spc + Drop(IDENT) + spc + E";" + spc
    ) |> BaseModelicaPackage
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
            pointer = " "^(col_num + 1) * "^" *
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
function julia_parse_str(data)
    debug, task = make(Debug, data, base_modelica; delegate = NoCache)

    try
        result = once(task)

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
function parse_file_julia(file)
    content = read(file, String)
    try
        return julia_parse_str(content)
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
