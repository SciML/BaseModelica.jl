# ANTLR4 Parser Integration for BaseModelica
# This module uses PythonCall to interface with the ANTLR-generated Python parser

# Flag to track if ANTLR parser is initialized
const ANTLR_INITIALIZED = Ref(false)

# Python module references (will be populated during initialization)
const antlr4 = Ref{Py}()
const BaseModelicaLexer = Ref{Py}()
const BaseModelicaParser = Ref{Py}()
const BaseModelicaVisitor = Ref{Py}()

"""
    init_antlr_parser()

Initialize the ANTLR4 parser by loading the necessary Python modules.

**Note**: You typically don't need to call this explicitly - the parser
automatically initializes itself on first use (lazy initialization).
This function is exported mainly for pre-loading or troubleshooting.

# Example
```julia
using BaseModelica

# Option 1: Lazy initialization (recommended)
parse_file_with_antlr("model.mo")  # Initializes automatically

# Option 2: Explicit initialization
BaseModelica.init_antlr_parser()   # Pre-load the parser
parse_file_with_antlr("model.mo")
```
"""
function init_antlr_parser()
    if ANTLR_INITIALIZED[]
        @info "ANTLR parser already initialized"
        return
    end

    try
        # Get the path to the generated parser directory
        base_dir = dirname(dirname(@__FILE__))
        parser_dir = joinpath(base_dir, "src", "antlr_generated")

        # Check if generated parser exists
        if !isdir(parser_dir)
            error("Generated parser not found at: $parser_dir\n" *
                  "Please run: ./build_parser.sh")
        end

        # Import ANTLR4 runtime
        antlr4[] = pyimport("antlr4")

        # Add parser directory to Python's sys.path so we can import the modules
        # The generated files are in the grammar subdirectory
        grammar_dir = joinpath(parser_dir, "grammar")
        py_sys = pyimport("sys")
        sys_path_list = py_sys.path

        # Check if grammar_dir is already in sys.path, if not add it
        if pyconvert(Bool, grammar_dir ∉ sys_path_list)
            sys_path_list.insert(0, grammar_dir)
        end

        # Import generated parser modules by module name
        BaseModelicaLexer[] = pyimport("BaseModelicaLexer").BaseModelicaLexer
        BaseModelicaParser[] = pyimport("BaseModelicaParser").BaseModelicaParser
        BaseModelicaVisitor[] = pyimport("BaseModelicaVisitor").BaseModelicaVisitor

        @info "ANTLR parser initialized successfully"
        ANTLR_INITIALIZED[] = true

    catch e
        @error "Failed to initialize ANTLR parser" exception = e
        @info """
        The ANTLR parser requires:
        1. Generated parser files (run: cd grammar && ./build_parser.sh)
        2. Python dependencies (managed automatically by CondaPkg.jl)

        If you're seeing import errors, the Python dependencies should be installed
        automatically. Try restarting Julia to trigger CondaPkg installation.
        """
        rethrow(e)
    end
end

"""
    parse_with_antlr(input::String) -> Py

Parse BaseModelica source code using the ANTLR4 parser.
Returns the ANTLR parse tree as a Python object.

The parser is automatically initialized on first use (lazy initialization),
so you don't need to call `init_antlr_parser()` explicitly.

# Arguments
- `input::String`: The BaseModelica source code to parse

# Returns
- A Python object representing the ANTLR parse tree

# Example
```julia
source = read("model.mo", String)
parse_tree = parse_with_antlr(source)  # Automatically initializes parser on first call
```
"""
function parse_with_antlr(input::String)
    # Lazy initialization - automatically initialize on first use
    if !ANTLR_INITIALIZED[]
        init_antlr_parser()
    end

    try
        # Create an input stream from the string
        input_stream = antlr4[].InputStream(input)

        # Create lexer
        lexer = BaseModelicaLexer[](input_stream)

        # Create token stream
        token_stream = antlr4[].CommonTokenStream(lexer)

        # Create parser
        parser = BaseModelicaParser[](token_stream)

        # Parse starting from the root rule (baseModelica)
        parse_tree = parser.baseModelica()

        return parse_tree

    catch e
        @error "Parsing failed" exception = e
        rethrow(e)
    end
end

"""
    antlr_tree_to_ast(parse_tree::Py) -> BaseModelicaPackage

Convert an ANTLR parse tree to BaseModelica AST types.
This is where the bridge between ANTLR and BaseModelica AST happens.

# Arguments
- `parse_tree::Py`: The ANTLR parse tree from `parse_with_antlr`

# Returns
- A `BaseModelicaPackage` instance (BaseModelica AST)

# Example
```julia
source = read("model.mo", String)
parse_tree = parse_with_antlr(source)
ast = antlr_tree_to_ast(parse_tree)
```
"""
function antlr_tree_to_ast(parse_tree::Py)
    visitor = ASTBuilderVisitor()
    return visit_baseModelica(visitor, parse_tree)
end

"""
    ASTBuilderVisitor

Visitor implementation that traverses ANTLR parse tree and constructs BaseModelica AST nodes.
This struct holds any state needed during tree traversal.
"""
struct ASTBuilderVisitor end

# Helper function to get text from a terminal node or context
function get_text(ctx::Py)
    text = pyconvert(String, ctx.getText())
    # Strip surrounding single quotes for quoted identifiers (Q_IDENT)
    if startswith(text, "'") && endswith(text, "'") && length(text) > 2
        return text[2:end-1]
    end
    return text
end

# Helper function to check if a context is nothing/null
function is_null(ctx::Py)
    return pyconvert(Bool, ctx == pybuiltins.None)
end

# Root rule visitor
function visit_baseModelica(visitor::ASTBuilderVisitor, ctx::Py)
    # baseModelica: versionHeader 'package' IDENT
    #   (decoration? classDefinition ';' | decoration? globalConstant ';')*
    #   decoration? 'model' longClassSpecifier ';'
    #   (annotationComment ';')?
    #   'end' IDENT ';'

    package_name = get_text(ctx.IDENT(0))  # First IDENT is package name

    # Collect class definitions and global constants
    class_defs = []

    # Get classDefinition contexts
    class_def_ctxs = ctx.classDefinition()
    if !is_null(class_def_ctxs)
        for class_def_ctx in class_def_ctxs
            push!(class_defs, visit_classDefinition(visitor, class_def_ctx))
        end
    end

    # Get globalConstant contexts
    global_const_ctxs = ctx.globalConstant()
    if !is_null(global_const_ctxs)
        for const_ctx in global_const_ctxs
            push!(class_defs, visit_globalConstant(visitor, const_ctx))
        end
    end

    # Get the main model
    model = visit_longClassSpecifier(visitor, ctx.longClassSpecifier())
    model_ast = BaseModelicaModel(model)

    return BaseModelicaPackage(package_name, class_defs, model_ast)
end

# Class Definition visitors
function visit_classDefinition(visitor::ASTBuilderVisitor, ctx::Py)
    # classDefinition: classPrefixes classSpecifier
    class_type = get_text(ctx.classPrefixes())
    class_spec = visit_classSpecifier(visitor, ctx.classSpecifier())
    return BaseModelicaClassDefinition(class_type, class_spec)
end

function visit_classSpecifier(visitor::ASTBuilderVisitor, ctx::Py)
    if !is_null(ctx.longClassSpecifier())
        return visit_longClassSpecifier(visitor, ctx.longClassSpecifier())
    elseif !is_null(ctx.shortClassSpecifier())
        return visit_shortClassSpecifier(visitor, ctx.shortClassSpecifier())
    elseif !is_null(ctx.derClassSpecifier())
        return visit_derClassSpecifier(visitor, ctx.derClassSpecifier())
    end
end

function visit_longClassSpecifier(visitor::ASTBuilderVisitor, ctx::Py)
    # longClassSpecifier: IDENT stringComment composition 'end' IDENT
    name = get_text(ctx.IDENT(0))
    description = visit_stringComment(visitor, ctx.stringComment())
    composition = visit_composition(visitor, ctx.composition())

    return BaseModelicaLongClass(name, description, composition)
end

function visit_shortClassSpecifier(visitor::ASTBuilderVisitor, ctx::Py)
    # For now, return a placeholder - can be expanded later
    name = get_text(ctx.IDENT())
    return BaseModelicaLongClass(name, "", BaseModelicaComposition([], [], []))
end

function visit_derClassSpecifier(visitor::ASTBuilderVisitor, ctx::Py)
    # For now, return a placeholder - can be expanded later
    name = get_text(ctx.IDENT(0))
    return BaseModelicaLongClass(name, "", BaseModelicaComposition([], [], []))
end

function visit_globalConstant(visitor::ASTBuilderVisitor, ctx::Py)
    # globalConstant: 'constant' typeSpecifier arraySubscripts? declaration comment
    type_spec = visit_typeSpecifier(visitor, ctx.typeSpecifier())
    decl = visit_declaration(visitor, ctx.declaration())
    comment_text = visit_comment(visitor, ctx.comment())

    # Extract name and modification from declaration
    name = decl.ident
    modification = decl.modification

    # Get value from modification if present
    value = nothing
    if !isnothing(modification)
        value = modification.expr
    end

    return BaseModelicaConstant(type_spec, name, value, comment_text, modification)
end

# Composition visitor
function visit_composition(visitor::ASTBuilderVisitor, ctx::Py)
    # composition: (decoration? genericElement ';')*
    #   ('equation' (equation ';')*
    #   | 'initial' 'equation' (initialEquation ';')*
    #   | 'initial'? 'algorithm' (statement ';')*)*
    #   ...

    components = []
    equations = []
    initial_equations = []

    # Get generic elements (components)
    generic_elems = ctx.genericElement()
    if !is_null(generic_elems)
        for elem_ctx in generic_elems
            push!(components, visit_genericElement(visitor, elem_ctx))
        end
    end

    # Get equations
    equation_ctxs = ctx.equation()
    if !is_null(equation_ctxs)
        for eq_ctx in equation_ctxs
            eq = visit_equation(visitor, eq_ctx)
            if !isnothing(eq)
                push!(equations, eq)
            end
        end
    end

    # Get initial equations
    initial_eq_ctxs = ctx.initialEquation()
    if !is_null(initial_eq_ctxs)
        for init_eq_ctx in initial_eq_ctxs
            eq = visit_initialEquation(visitor, init_eq_ctx)
            if !isnothing(eq)
                push!(initial_equations, eq)
            end
        end
    end

    return BaseModelicaComposition(components, equations, initial_equations)
end

function visit_genericElement(visitor::ASTBuilderVisitor, ctx::Py)
    if !is_null(ctx.normalElement())
        return visit_normalElement(visitor, ctx.normalElement())
    elseif !is_null(ctx.parameterEquation())
        return visit_parameterEquation(visitor, ctx.parameterEquation())
    end
end

function visit_normalElement(visitor::ASTBuilderVisitor, ctx::Py)
    # normalElement: componentClause
    return visit_componentClause(visitor, ctx.componentClause())
end

function visit_componentClause(visitor::ASTBuilderVisitor, ctx::Py)
    # componentClause: typePrefix typeSpecifier componentList
    type_prefix = visit_typePrefix(visitor, ctx.typePrefix())
    type_spec = visit_typeSpecifier(visitor, ctx.typeSpecifier())
    component_list = visit_componentList(visitor, ctx.componentList())

    return BaseModelicaComponentClause(type_prefix, type_spec, component_list)
end

function visit_typePrefix(visitor::ASTBuilderVisitor, ctx::Py)
    # typePrefix: ('discrete' | 'parameter' | 'constant')? ('input' | 'output')?
    prefix_text = get_text(ctx)

    # Parse the prefix to extract discrete/parameter/constant and input/output
    dpc = nothing  # discrete/parameter/constant
    io = nothing   # input/output

    if occursin("discrete", prefix_text)
        dpc = "discrete"
    elseif occursin("parameter", prefix_text)
        dpc = "parameter"
    elseif occursin("constant", prefix_text)
        dpc = "constant"
    end

    if occursin("input", prefix_text)
        io = "input"
    elseif occursin("output", prefix_text)
        io = "output"
    end

    return BaseModelicaTypePrefix(false, dpc, io)  # final_flag is always false for now
end

function visit_typeSpecifier(visitor::ASTBuilderVisitor, ctx::Py)
    # typeSpecifier: '.'? name
    name = visit_name(visitor, ctx.name())
    return BaseModelicaTypeSpecifier(name)
end

function visit_name(visitor::ASTBuilderVisitor, ctx::Py)
    # name: IDENT ('.' IDENT)*
    return get_text(ctx)
end

function visit_componentList(visitor::ASTBuilderVisitor, ctx::Py)
    # componentList: componentDeclaration (',' componentDeclaration)*
    components = []
    comp_decls = ctx.componentDeclaration()

    for comp_decl in comp_decls
        push!(components, visit_componentDeclaration(visitor, comp_decl))
    end

    return components
end

function visit_componentDeclaration(visitor::ASTBuilderVisitor, ctx::Py)
    # componentDeclaration: declaration comment
    decl = visit_declaration(visitor, ctx.declaration())
    comment_text = visit_comment(visitor, ctx.comment())

    return BaseModelicaComponentDeclaration(decl, comment_text)
end

function visit_declaration(visitor::ASTBuilderVisitor, ctx::Py)
    # declaration: IDENT arraySubscripts? modification?
    # Note: ident should be a list of BaseModelicaIdentifier objects to match parser.jl
    # Note: modification should be a list to match parser.jl
    ident = [BaseModelicaIdentifier(get_text(ctx.IDENT()))]

    array_subs = nothing
    if !is_null(ctx.arraySubscripts())
        array_subs = visit_arraySubscripts(visitor, ctx.arraySubscripts())
    end

    modification = nothing
    if !is_null(ctx.modification())
        mod = visit_modification(visitor, ctx.modification())
        if !isnothing(mod)
            modification = [mod]
        end
    end

    return BaseModelicaDeclaration(ident, array_subs, modification)
end

function visit_modification(visitor::ASTBuilderVisitor, ctx::Py)
    # modification: classModification ('=' expression)?
    #   | '=' expression
    #   | ':=' expression
    # Note: modification.expr should be a list to match parser.jl

    # Get all expressions - ctx.expression() returns a list or single element
    expr_ctxs = ctx.expression()
    if is_null(expr_ctxs)
        return nothing
    end

    # Collect all expressions into a list
    expr_list = []
    if pyconvert(Bool, pybuiltins.hasattr(expr_ctxs, "__iter__"))
        # It's a list
        for expr_ctx in expr_ctxs
            push!(expr_list, visit_expression(visitor, expr_ctx))
        end
    else
        # It's a single element
        push!(expr_list, visit_expression(visitor, expr_ctxs))
    end

    if !isempty(expr_list)
        return BaseModelicaModification(expr_list)
    end

    return nothing
end

function visit_arraySubscripts(visitor::ASTBuilderVisitor, ctx::Py)
    # arraySubscripts: '[' subscript (',' subscript)* ']'
    subscripts = []

    subscript_ctxs = ctx.subscript()
    for sub_ctx in subscript_ctxs
        push!(subscripts, visit_subscript(visitor, sub_ctx))
    end

    return BaseModelicaArraySubscripts(subscripts)
end

function visit_subscript(visitor::ASTBuilderVisitor, ctx::Py)
    # subscript: ':' | expression
    text = get_text(ctx)

    if text == ":"
        return BMColon()
    else
        return visit_expression(visitor, ctx.expression())
    end
end

function visit_parameterEquation(visitor::ASTBuilderVisitor, ctx::Py)
    # parameterEquation: 'parameter' 'equation' guessValue '=' (expression | prioritizeExpression) comment
    comp_ref = visit_guessValue(visitor, ctx.guessValue())

    if !is_null(ctx.expression())
        expr = visit_expression(visitor, ctx.expression())
    else
        expr = visit_prioritizeExpression(visitor, ctx.prioritizeExpression())
    end

    comment_text = visit_comment(visitor, ctx.comment())

    return BaseModelicaParameterEquation(comp_ref, expr, comment_text)
end

function visit_guessValue(visitor::ASTBuilderVisitor, ctx::Py)
    # guessValue: 'guess' '(' componentReference ')'
    return visit_componentReference(visitor, ctx.componentReference())
end

function visit_prioritizeExpression(visitor::ASTBuilderVisitor, ctx::Py)
    # For now, just return the expression part
    expr_ctxs = ctx.expression()
    if pyconvert(Bool, pybuiltins.hasattr(expr_ctxs, "__iter__"))
        return visit_expression(visitor, expr_ctxs[0])
    else
        return visit_expression(visitor, expr_ctxs)
    end
end

# Equation visitors
function visit_equation(visitor::ASTBuilderVisitor, ctx::Py)
    # equation: decoration? (simpleExpression decoration? ('=' expression)?
    #   | ifEquation | forEquation | whenEquation) comment

    if !is_null(ctx.ifEquation())
        return visit_ifEquation(visitor, ctx.ifEquation())
    elseif !is_null(ctx.forEquation())
        return visit_forEquation(visitor, ctx.forEquation())
    elseif !is_null(ctx.whenEquation())
        return visit_whenEquation(visitor, ctx.whenEquation())
    else
        # Simple equation
        simple_expr = visit_simpleExpression(visitor, ctx.simpleExpression())

        # Check if there's an '=' expression
        expr_ctxs = ctx.expression()
        if !is_null(expr_ctxs)
            # Get the first expression after '='
            first_expr = pyconvert(Bool, pybuiltins.hasattr(expr_ctxs, "__iter__")) ? expr_ctxs[0] : expr_ctxs
            rhs = visit_expression(visitor, first_expr)

            comment_text = visit_comment(visitor, ctx.comment())
            return BaseModelicaAnyEquation(
                BaseModelicaSimpleEquation(simple_expr, rhs),
                comment_text
            )
        else
            # Just an expression (no '='), could be a function call
            return nothing
        end
    end
end

function visit_initialEquation(visitor::ASTBuilderVisitor, ctx::Py)
    # initialEquation: equation | prioritizeEquation
    if !is_null(ctx.equation())
        eq = visit_equation(visitor, ctx.equation())
        return isnothing(eq) ? nothing : BaseModelicaInitialEquation(eq)
    else
        # prioritizeEquation - skip for now
        return nothing
    end
end

function visit_ifEquation(visitor::ASTBuilderVisitor, ctx::Py)
    # ifEquation: 'if' expression 'then' (equation ';')*
    #   ('elseif' expression 'then' (equation ';')*)*
    #   ('else' (equation ';')*)?
    #   'end' 'if'

    # Collect all condition expressions
    conditions = []
    equation_lists = []

    # Get all expressions (conditions)
    expr_ctxs = ctx.expression()
    for expr_ctx in expr_ctxs
        push!(conditions, visit_expression(visitor, expr_ctx))
    end

    # Get all equation lists
    eq_ctxs = ctx.equation()
    current_idx = 1

    # Count equations per branch by parsing the structure
    # This is simplified - in a full implementation, we'd need to track
    # which equations belong to which branch
    for expr_ctx in expr_ctxs
        branch_equations = []
        # Collect equations for this branch
        # (simplified - actual implementation would need more sophisticated tracking)
        push!(equation_lists, branch_equations)
    end

    # Add else branch if present
    # (simplified)

    return BaseModelicaIfEquation(conditions, equation_lists)
end

function visit_forEquation(visitor::ASTBuilderVisitor, ctx::Py)
    # forEquation: 'for' forIndex 'loop' (equation ';')* 'end' 'for'
    for_index = visit_forIndex(visitor, ctx.forIndex())

    equations = []
    eq_ctxs = ctx.equation()
    for eq_ctx in eq_ctxs
        eq = visit_equation(visitor, eq_ctx)
        if !isnothing(eq)
            push!(equations, eq)
        end
    end

    return BaseModelicaForEquation(for_index, equations)
end

function visit_forIndex(visitor::ASTBuilderVisitor, ctx::Py)
    # forIndex: IDENT 'in' expression
    ident = get_text(ctx.IDENT())
    expr = visit_expression(visitor, ctx.expression())

    return BaseModelicaForIndex(ident, expr)
end

function visit_whenEquation(visitor::ASTBuilderVisitor, ctx::Py)
    # whenEquation: 'when' expression 'then' (equation ';')*
    #   ('elsewhen' expression 'then' (equation ';')*)*
    #   'end' 'when'

    whens = []
    thens = []

    # Get all condition expressions
    expr_ctxs = ctx.expression()
    for expr_ctx in expr_ctxs
        push!(whens, visit_expression(visitor, expr_ctx))
    end

    # Get all equation lists (simplified)
    eq_ctxs = ctx.equation()
    for expr_ctx in expr_ctxs
        branch_equations = []
        push!(thens, branch_equations)
    end

    return BaseModelicaWhenEquation(whens, thens)
end

# Expression visitors
function visit_expression(visitor::ASTBuilderVisitor, ctx::Py)
    # expression: expressionNoDecoration decoration?
    return visit_expressionNoDecoration(visitor, ctx.expressionNoDecoration())
end

function visit_expressionNoDecoration(visitor::ASTBuilderVisitor, ctx::Py)
    # expressionNoDecoration: simpleExpression | ifExpression
    if !is_null(ctx.ifExpression())
        return visit_ifExpression(visitor, ctx.ifExpression())
    else
        return visit_simpleExpression(visitor, ctx.simpleExpression())
    end
end

function visit_ifExpression(visitor::ASTBuilderVisitor, ctx::Py)
    # ifExpression: 'if' expressionNoDecoration 'then' expressionNoDecoration
    #   ('elseif' expressionNoDecoration 'then' expressionNoDecoration)*
    #   'else' expressionNoDecoration

    conditions = []
    expressions = []

    # Get all expressionNoDecoration contexts
    expr_ctxs = ctx.expressionNoDecoration()

    # First is condition, second is then-expression
    push!(conditions, visit_expressionNoDecoration(visitor, expr_ctxs[0]))
    push!(expressions, visit_expressionNoDecoration(visitor, expr_ctxs[1]))

    # Handle elseif branches (pairs of condition and expression)
    idx = 2
    while idx < pyconvert(Int, length(expr_ctxs)) - 1
        push!(conditions, visit_expressionNoDecoration(visitor, expr_ctxs[idx]))
        push!(expressions, visit_expressionNoDecoration(visitor, expr_ctxs[idx + 1]))
        idx += 2
    end

    # Last expression is the else branch
    push!(expressions, visit_expressionNoDecoration(visitor, expr_ctxs[-1]))

    return BaseModelicaIfExpression(conditions, expressions)
end

function visit_simpleExpression(visitor::ASTBuilderVisitor, ctx::Py)
    # simpleExpression: logicalExpression (':' logicalExpression (':' logicalExpression)?)?
    logical_exprs = ctx.logicalExpression()

    if pyconvert(Int, length(logical_exprs)) == 1
        return visit_logicalExpression(visitor, logical_exprs[0])
    elseif pyconvert(Int, length(logical_exprs)) == 2
        # start:stop (default step is 1)
        start_expr = visit_logicalExpression(visitor, logical_exprs[0])
        stop_expr = visit_logicalExpression(visitor, logical_exprs[1])
        return BaseModelicaRange(start_expr, BaseModelicaNumber(1), stop_expr)
    else
        # start:step:stop
        start_expr = visit_logicalExpression(visitor, logical_exprs[0])
        step_expr = visit_logicalExpression(visitor, logical_exprs[1])
        stop_expr = visit_logicalExpression(visitor, logical_exprs[2])
        return BaseModelicaRange(start_expr, step_expr, stop_expr)
    end
end

function visit_logicalExpression(visitor::ASTBuilderVisitor, ctx::Py)
    # logicalExpression: logicalTerm ('or' logicalTerm)*
    terms = ctx.logicalTerm()

    if pyconvert(Int, length(terms)) == 1
        return visit_logicalTerm(visitor, terms[0])
    else
        result = visit_logicalTerm(visitor, terms[0])
        for i in 1:(pyconvert(Int, length(terms)) - 1)
            right = visit_logicalTerm(visitor, terms[i])
            result = BaseModelicaOr(result, right)
        end
        return result
    end
end

function visit_logicalTerm(visitor::ASTBuilderVisitor, ctx::Py)
    # logicalTerm: logicalFactor ('and' logicalFactor)*
    factors = ctx.logicalFactor()

    if pyconvert(Int, length(factors)) == 1
        return visit_logicalFactor(visitor, factors[0])
    else
        result = visit_logicalFactor(visitor, factors[0])
        for i in 1:(pyconvert(Int, length(factors)) - 1)
            right = visit_logicalFactor(visitor, factors[i])
            result = BaseModelicaAnd(result, right)
        end
        return result
    end
end

function visit_logicalFactor(visitor::ASTBuilderVisitor, ctx::Py)
    # logicalFactor: 'not'? relation
    # Check if 'not' keyword is present by examining the parse tree text
    has_not = false
    if pyconvert(Int, ctx.getChildCount()) > 1
        # If there's more than one child, check if first child is 'not'
        first_child = ctx.getChild(0)
        if !is_null(first_child)
            child_text = pyconvert(String, first_child.getText())
            has_not = (child_text == "not")
        end
    end

    relation = visit_relation(visitor, ctx.relation())

    if has_not
        return BaseModelicaNot(relation)
    else
        return relation
    end
end

function visit_relation(visitor::ASTBuilderVisitor, ctx::Py)
    # relation: arithmeticExpression (relationalOperator arithmeticExpression)?
    arith_exprs = ctx.arithmeticExpression()

    if pyconvert(Int, length(arith_exprs)) == 1
        return visit_arithmeticExpression(visitor, arith_exprs[0])
    else
        left = visit_arithmeticExpression(visitor, arith_exprs[0])
        right = visit_arithmeticExpression(visitor, arith_exprs[1])
        op_ctx = ctx.relationalOperator()
        op_text = get_text(op_ctx)

        if op_text == "<"
            return BaseModelicaLessThan(left, right)
        elseif op_text == "<="
            return BaseModelicaLEQ(left, right)
        elseif op_text == ">"
            return BaseModelicaGreaterThan(left, right)
        elseif op_text == ">="
            return BaseModelicaGEQ(left, right)
        elseif op_text == "=="
            return BaseModelicaEQ(left, right)
        elseif op_text == "<>"
            return BaseModelicaNEQ(left, right)
        end
    end
end

function visit_arithmeticExpression(visitor::ASTBuilderVisitor, ctx::Py)
    # arithmeticExpression: addOperator? term (addOperator term)*
    terms = ctx.term()
    add_ops = ctx.addOperator()

    # Check for leading unary minus
    has_leading_op = !is_null(add_ops) && pyconvert(Int, length(add_ops)) == pyconvert(Int, length(terms))

    if pyconvert(Int, length(terms)) == 1 && pyconvert(Int, length(add_ops)) == 0
        return visit_term(visitor, terms[0])
    else
        result = nothing
        term_idx = 0
        op_idx = 0

        # Handle leading operator
        if has_leading_op
            op_text = get_text(add_ops[0])
            first_term = visit_term(visitor, terms[0])
            if op_text == "-" || op_text == ".-"
                result = BaseModelicaUnaryMinus(first_term)
            else
                result = first_term
            end
            term_idx = 1
            op_idx = 1
        else
            result = visit_term(visitor, terms[0])
            term_idx = 1
        end

        # Process remaining terms
        while term_idx < pyconvert(Int, length(terms))
            op_text = get_text(add_ops[op_idx])
            right_term = visit_term(visitor, terms[term_idx])

            if op_text == "+"
                result = BaseModelicaSum(result, right_term)
            elseif op_text == "-"
                result = BaseModelicaMinus(result, right_term)
            elseif op_text == ".+"
                result = BaseModelicaElementWiseSum(result, right_term)
            elseif op_text == ".-"
                result = BaseModelicaElementWiseMinus(result, right_term)
            end

            term_idx += 1
            op_idx += 1
        end

        return result
    end
end

function visit_term(visitor::ASTBuilderVisitor, ctx::Py)
    # term: factor (mulOperator factor)*
    factors = ctx.factor()
    mul_ops = ctx.mulOperator()

    if pyconvert(Int, length(factors)) == 1
        return visit_factor(visitor, factors[0])
    else
        result = visit_factor(visitor, factors[0])
        for i in 1:(pyconvert(Int, length(factors)) - 1)
            op_text = get_text(mul_ops[i - 1])
            right_factor = visit_factor(visitor, factors[i])

            if op_text == "*"
                result = BaseModelicaProd(result, right_factor)
            elseif op_text == "/"
                result = BaseModelicaDivide(result, right_factor)
            elseif op_text == ".*"
                result = BaseModelicaElementWiseProd(result, right_factor)
            elseif op_text == "./"
                result = BaseModelicaElementWiseDivide(result, right_factor)
            end
        end
        return result
    end
end

function visit_factor(visitor::ASTBuilderVisitor, ctx::Py)
    # factor: primary (('^' | '.^') primary)?
    primaries = ctx.primary()

    if pyconvert(Int, length(primaries)) == 1
        return visit_primary(visitor, primaries[0])
    else
        base = visit_primary(visitor, primaries[0])
        exp = visit_primary(visitor, primaries[1])

        # Check which operator was used
        text = get_text(ctx)
        if occursin(".^", text)
            return BaseModelicaElementWiseFactor(base, exp)
        else
            return BaseModelicaFactor(base, exp)
        end
    end
end

function visit_primary(visitor::ASTBuilderVisitor, ctx::Py)
    # primary: UNSIGNED_NUMBER | STRING | 'false' | 'true'
    #   | ('der' | 'initial' | 'pure') functionCallArgs
    #   | componentReference functionCallArgs?
    #   | '(' outputExpressionList ')' arraySubscripts?
    #   | '[' expressionList (';' expressionList)* ']'
    #   | '{' arrayArguments '}'
    #   | 'end'

    if !is_null(ctx.UNSIGNED_NUMBER())
        num_text = get_text(ctx.UNSIGNED_NUMBER())
        return BaseModelicaNumber(parse(Float64, num_text))
    elseif !is_null(ctx.STRING())
        str_text = get_text(ctx.STRING())
        # Remove quotes
        str_val = str_text[2:end-1]
        return BaseModelicaString(str_val)
    elseif get_text(ctx) == "false"
        return BaseModelicaBool(false)
    elseif get_text(ctx) == "true"
        return BaseModelicaBool(true)
    elseif get_text(ctx) == "end"
        return BaseModelicaIdentifier("end")
    elseif !is_null(ctx.functionCallArgs())
        # Check for der, initial, or pure function calls
        # These appear as: ('der' | 'initial' | 'pure') functionCallArgs
        full_text = get_text(ctx)
        if startswith(full_text, "der") || startswith(full_text, "initial") || startswith(full_text, "pure")
            # Determine which function it is
            func_name_str = if startswith(full_text, "der")
                "der"
            elseif startswith(full_text, "initial")
                "initial"
            else
                "pure"
            end

            func_name = BaseModelicaIdentifier(func_name_str)
            args = visit_functionCallArgs(visitor, ctx.functionCallArgs())
            return BaseModelicaFunctionCall(func_name, args)
        end
    elseif !is_null(ctx.componentReference())
        comp_ref = visit_componentReference(visitor, ctx.componentReference())

        if !is_null(ctx.functionCallArgs())
            args = visit_functionCallArgs(visitor, ctx.functionCallArgs())
            # Extract function name from component reference
            func_name = comp_ref.ref_list[1]  # Simplified - assumes simple name
            return BaseModelicaFunctionCall(func_name, args)
        else
            return comp_ref
        end
    elseif !is_null(ctx.outputExpressionList())
        expr_list = visit_outputExpressionList(visitor, ctx.outputExpressionList())
        if length(expr_list) == 1
            return expr_list[1]
        else
            # Tuple
            return expr_list
        end
    else
        # Array or other constructs
        return BaseModelicaNumber(0.0)  # Placeholder
    end
end

function visit_componentReference(visitor::ASTBuilderVisitor, ctx::Py)
    # componentReference: '.'? IDENT arraySubscripts? ('.' IDENT arraySubscripts?)*
    ref_list = []

    idents = ctx.IDENT()
    for ident_ctx in idents
        # Create BaseModelicaIdentifier objects, not raw strings
        push!(ref_list, BaseModelicaIdentifier(get_text(ident_ctx)))
    end

    return BaseModelicaComponentReference(ref_list)
end

function visit_functionCallArgs(visitor::ASTBuilderVisitor, ctx::Py)
    # functionCallArgs: '(' functionArguments? ')'
    if is_null(ctx.functionArguments())
        return BaseModelicaFunctionArgs([])
    else
        return visit_functionArguments(visitor, ctx.functionArguments())
    end
end

function visit_functionArguments(visitor::ASTBuilderVisitor, ctx::Py)
    # functionArguments: expression (',' functionArgumentsNonFirst | 'for' forIndex)?
    #   | functionPartialApplication (',' functionArgumentsNonFirst)?
    #   | namedArguments

    args = []

    # Get all expressions
    expr_ctxs = ctx.expression()
    if !is_null(expr_ctxs)
        if pyconvert(Bool, pybuiltins.hasattr(expr_ctxs, "__iter__"))
            # It's a list
            for expr_ctx in expr_ctxs
                push!(args, visit_expression(visitor, expr_ctx))
            end
        else
            # Single expression
            push!(args, visit_expression(visitor, expr_ctxs))
        end
    end

    return BaseModelicaFunctionArgs(args)
end

function visit_outputExpressionList(visitor::ASTBuilderVisitor, ctx::Py)
    # outputExpressionList: expression? (',' expression?)*
    exprs = []

    expr_ctxs = ctx.expression()
    if !is_null(expr_ctxs)
        for expr_ctx in expr_ctxs
            push!(exprs, visit_expression(visitor, expr_ctx))
        end
    end

    return exprs
end

# Comment visitors
function visit_comment(visitor::ASTBuilderVisitor, ctx::Py)
    # comment: stringComment annotationComment?
    return visit_stringComment(visitor, ctx.stringComment())
end

function visit_stringComment(visitor::ASTBuilderVisitor, ctx::Py)
    # stringComment: (STRING ('+' STRING)*)?
    if is_null(ctx)
        return ""
    end

    # Try to get first STRING token to check if any exist
    first_string = ctx.STRING(0)
    if is_null(first_string)
        return ""
    end

    # Collect all STRING tokens using indexed access
    result = []
    idx = 0
    while true
        string_token = ctx.STRING(idx)
        if is_null(string_token)
            break
        end
        str_text = get_text(string_token)
        push!(result, str_text[2:end-1])  # Remove quotes
        idx += 1
    end

    return join(result, "")
end

"""
    parse_file_with_antlr(file_path::String) -> BaseModelicaPackage

Parse a BaseModelica file using ANTLR4 and convert to BaseModelica AST.

# Arguments
- `file_path::String`: Path to the BaseModelica file

# Returns
- A `BaseModelicaPackage` instance

# Example
```julia
ast = parse_file_with_antlr("model.mo")
sys = baseModelica_to_ModelingToolkit(ast)
```
"""
function parse_file_with_antlr(file_path::String)
    if !isfile(file_path)
        error("File not found: $file_path")
    end

    source = read(file_path, String)
    parse_tree = parse_with_antlr(source)
    return antlr_tree_to_ast(parse_tree)
end
