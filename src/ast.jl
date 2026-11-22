# Typed representation of Modelica's built-in StateSelect enumeration.
# Spec: Modelica Language Specification §8.2.1 (stateSelect attribute).
# Values are ordered by increasing preference for state selection:
#   never < avoid < default < prefer < always
@enum StateSelectValue begin
    StateSelectNever = -100
    StateSelectAvoid = -10
    StateSelectDefault = 0
    StateSelectPrefer = 10
    StateSelectAlways = 100
end

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
    BaseModelicaComposition(components, equations, initial_equations, parameter_equations, annotation)
    BaseModelicaLongClass(name, description, composition)
    BaseModelicaModification(class_modifications, expr)
    BaseModelicaClassModificationArg(name, modification, each)
    #Class types
    BaseModelicaClassDefinition(class_type, class)
    BaseModelicaEnumeration(name, values)  # name: String, values: Vector{String}
    # Algorithm sections and statements
    BaseModelicaAlgorithmSection(statements, initial) # initial::Bool for `initial algorithm`
    BaseModelicaAssignment(target, expression)  # target := expression
    BaseModelicaIfStatement(conditions, branches)  # branches[end] is the else branch if longer
    BaseModelicaForStatement(index, statements)
    BaseModelicaUnsupportedStatement(description)  # parsed but not convertible (while, when, ...)
end

# Keep the existing constructor for modifiers without `each`.
BaseModelicaClassModificationArg(name, modification) =
    BaseModelicaClassModificationArg(name, modification, false)

@data BaseModelicaExpr <: BaseModelicaASTNode begin
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
    BaseModelicaBool(val)
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
    BaseModelicaNamedArgument(name, expression)
    BaseModelicaFieldAccess(expression, field)
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
    BaseModelicaArrayReference(term, indexes)  # (expr)[subscripts]; indexes::BaseModelicaArraySubscripts
    BaseModelicaArrayConstructor(elements)  # {a, b, c}
    BaseModelicaArrayComprehension(expression, index)  # {expr for i in range}; index::BaseModelicaForIndex
    BaseModelicaMatrixConstructor(rows)  # [a, b; c, d]; rows::Vector of element lists
    # Element `index` (a tuple of Ints) of the value of `expression`, or the value itself if it
    # is a scalar. Created when array declarations are scalarized: the element `x[i]` of
    # `Real x[3](start = s)` gets start `BaseModelicaArrayElement(s, (i,))`.
    BaseModelicaArrayElement(expression, index)
    BaseModelicaArraySlice(expression, index) # leading indices of a record array modifier
    BaseModelicaArrayFieldBinding(expression, name) # array record fields cannot broadcast scalar bindings
    BaseModelicaUnsupportedExpression(description)  # parsed but not convertible
end
