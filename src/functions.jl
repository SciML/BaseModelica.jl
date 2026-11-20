# User-defined functions (package-level `function` classes with an algorithm section) are
# inlined symbolically: a call binds the evaluated arguments to the inputs and runs the
# algorithm on symbolic values, so the call becomes an ordinary expression in the
# equations (differentiable, no registered function needed). `if` statements become
# `ifelse` (or are folded when the condition is a constant) and `for` loops over constant
# ranges are unrolled. Other statements throw `UnsupportedFeatureError`.

"""
A user function from a `function` class definition.
`inputs`/`outputs`/`locals` hold `(name, default_ast_or_nothing)` in declaration order.
`statements` is `nothing` when the function has no algorithm section (e.g. `external`).
"""
struct UserFunction
    name::String
    inputs::Vector{Tuple{Symbol, Any}}
    outputs::Vector{Tuple{Symbol, Any}}
    locals::Vector{Tuple{Symbol, Any}}
    statements::Union{Nothing, Vector{Any}}
    # array variable => subscripts of its declaration
    array_dims::Dict{Symbol, Vector{Any}}
    record_types::Dict{Symbol, String}
end

# function name => UserFunction, populated per package
const user_function_map = Dict{String, UserFunction}()

# Local variables of the function body (or for-loop indices) being evaluated
const LOCAL_SCOPE = Ref{Union{Nothing, Dict{Symbol, Any}}}(nothing)
const INLINE_DEPTH = Ref(0)
const MAX_INLINE_DEPTH = 32
const MAX_UNROLL = 10_000

# A declared function variable shadows model scope even before its first assignment.
# Keep this marker through symbolic branches: dead branch-local temporaries are fine,
# but reading one without a value must fail rather than resolve in the caller.
struct UnassignedFunctionLocal end
const UNASSIGNED_FUNCTION_LOCAL = UnassignedFunctionLocal()
function function_local_value(value, var)
    value isa UnassignedFunctionLocal && unsupported("function local `$var` is unassigned on some execution paths")
    return value
end

function with_local_scope(f, scope)
    old = LOCAL_SCOPE[]
    LOCAL_SCOPE[] = scope
    try
        return f()
    finally
        LOCAL_SCOPE[] = old
    end
end

# Class names are a String (:antlr) or a BaseModelicaIdentifier (:julia)
identifier_name(x::BaseModelicaIdentifier) = String(x.name)
identifier_name(x) = String(x)

# :antlr stores `nothing` or one BaseModelicaArraySubscripts; :julia a (possibly empty) list
function has_array_subscripts(decl)
    subs = decl.array_subs
    isnothing(subs) && return false
    return subs isa AbstractVector ? !isempty(subs) : true
end

function declaration_default(decl)
    (isnothing(decl.modification) || isempty(decl.modification)) && return nothing
    mod = decl.modification[1]
    (isnothing(mod.expr) || isempty(mod.expr)) && return nothing
    return mod.expr[end]
end

function UserFunction(name::String, class::BaseModelicaLongClass)
    inputs = Tuple{Symbol, Any}[]
    outputs = Tuple{Symbol, Any}[]
    locals = Tuple{Symbol, Any}[]
    array_dims = Dict{Symbol, Vector{Any}}()
    record_types = Dict{Symbol, String}()
    composition = class.composition
    for clause in composition.components
        clause isa BaseModelicaComponentClause || continue
        for comp_decl in clause.component_list
            decl = comp_decl.declaration
            var = Symbol(decl.ident[1].name)
            subscripts = declaration_subscripts(decl)
            isnothing(subscripts) || (array_dims[var] = subscripts)
            type = clause.type_specifier.type
            default = declaration_default(decl)
            if haskey(record_type_map, type)
                record_types[var] = type
                default = clause.type_prefix.io == "input" &&
                    (isnothing(decl.modification) || isempty(decl.modification)) ? nothing :
                    RecordDefault(type, decl.modification)
            end
            entry = (var, default)
            io = clause.type_prefix.io
            push!(io == "input" ? inputs : io == "output" ? outputs : locals, entry)
        end
    end
    sections = filter(eq -> eq isa BaseModelicaAlgorithmSection, composition.equations)
    statements = isempty(sections) ? nothing :
        reduce(vcat, [collect(section.statements) for section in sections])
    unsupported_sections = filter(x -> x isa BaseModelicaUnsupportedStatement, composition.equations)
    if !isempty(unsupported_sections)
        statements = isnothing(statements) ? collect(Any, unsupported_sections) : [statements; unsupported_sections]
    end
    return UserFunction(name, inputs, outputs, locals, statements, array_dims, record_types)
end

function register_user_functions!(class_defs)
    empty!(user_function_map)
    for class_def in class_defs
        class_def isa BaseModelicaClassDefinition || continue
        occursin("function", string(class_def.class_type)) || continue
        class = class_def.class
        class isa BaseModelicaLongClass || continue
        name = identifier_name(class.name)
        user_function_map[name] = UserFunction(name, class)
    end
    return user_function_map
end

"""
    inline_user_function(f, arg_asts)

Evaluate a call of user function `f` with argument expressions `arg_asts` (evaluated in the
caller's scope) and return the symbolic value of its first output.
"""
function inline_user_function(f::UserFunction, arg_asts)
    isnothing(f.statements) && !all(x -> has_record_binding(x[2]), f.outputs) &&
        unsupported("function `$(f.name)` has no algorithm section; external functions are not supported")
    isempty(f.outputs) && unsupported("function `$(f.name)` has no output")
    length(arg_asts) > length(f.inputs) &&
        error("function `$(f.name)` takes $(length(f.inputs)) inputs, got $(length(arg_asts))")
    INLINE_DEPTH[] >= MAX_INLINE_DEPTH &&
        unsupported("function `$(f.name)`: call depth exceeds $MAX_INLINE_DEPTH (recursive functions are not supported)")

    args = bind_call_arguments(first.(f.inputs), arg_asts, f.name)
    scope = Dict{Symbol, Any}(
        var => UNASSIGNED_FUNCTION_LOCAL
        for (var, _) in Iterators.flatten((f.inputs, f.outputs, f.locals))
    )
    INLINE_DEPTH[] += 1
    try
        with_local_scope(scope) do
            for (i, (var, default)) in enumerate(f.inputs)
                if haskey(args, var)
                    scope[var] = args[var].value
                elseif default isa RecordDefault && haskey(f.array_dims, var)
                    scope[var] = record_array_default(default, literal_record_size(String(var), f.array_dims[var]))
                elseif !isnothing(default)
                    scope[var] = eval_AST(default)
                else
                    error("function `$(f.name)`: missing value for input `$var`")
                end
                if haskey(f.record_types, var)
                    value = scope[var]
                    if haskey(f.array_dims, var)
                        dims = literal_record_size(String(var), f.array_dims[var])
                        is_array(value) && size(value) == dims ||
                            unsupported("function `$(f.name)`: record input `$var` requires array size $dims")
                        foreach(x -> check_record_value(f.record_types[var], x), value)
                    else
                        check_record_value(f.record_types[var], value)
                    end
                    require_assigned_record(value, "function `$(f.name)` input `$var`")
                end
            end
            for (var, default) in Iterators.flatten((f.outputs, f.locals))
                scope[var] = UNASSIGNED_FUNCTION_LOCAL
                if default isa RecordDefault && haskey(f.array_dims, var)
                    dims = literal_record_size(String(var), f.array_dims[var])
                    scope[var] = record_array_default(default, dims)
                    is_array(scope[var]) && size(scope[var]) == dims ||
                        unsupported("function `$(f.name)`: record output/local `$var` requires array size $dims")
                elseif !isnothing(default)
                    scope[var] = eval_AST(default)
                elseif haskey(f.array_dims, var)
                    allocate_array!(scope, var, f.array_dims[var])
                end
            end
            isnothing(f.statements) || run_statements!(scope, f.statements, f)
        end
    finally
        INLINE_DEPTH[] -= 1
    end
    output = f.outputs[1][1]
    haskey(scope, output) || error("function `$(f.name)` does not assign its output `$output`")
    value = function_local_value(scope[output], output)
    if haskey(f.record_types, output)
        require_assigned_record(value, "function `$(f.name)` output `$output`")
        with_local_scope(scope) do
            if is_array(value)
                foreach(x -> check_record_value(f.record_types[output], x), value)
            else
                check_record_value(f.record_types[output], value)
            end
        end
    end
    if is_array(value)
        any(isnothing, value) &&
            error("function `$(f.name)` does not assign every element of its output `$output`")
        value = typed_numeric_array(value)
    end
    return value
end

# An output or local array with constant sizes starts with unassigned (`nothing`) elements,
# so that elements can be assigned one by one. One declared with `:` is created by its
# first assignment.
function allocate_array!(scope, var, subscripts)
    any(sub -> sub isa BMColon, subscripts) && return scope
    dims = [to_dim(eval_dimension(sub)) for sub in subscripts]
    scope[var] = fill!(Array{Any}(undef, dims...), nothing)
    return scope
end

function run_statements!(scope, statements, f)
    for statement in statements
        run_statement!(scope, statement, f)
    end
    return scope
end

function run_statement!(scope, st::BaseModelicaAssignment, f)
    parts = st.target.ref_list
    var = Symbol(first(parts).name)
    any(entry -> entry[1] == var, Iterators.flatten((f.outputs, f.locals))) ||
        error("function `$(f.name)`: cannot assign to `$var`, which is not an output or local variable")
    value = eval_AST(st.expression)
    if length(parts) == 1
        scope[var] = value
    else
        haskey(scope, var) || unsupported("function `$(f.name)`: `$var` has no value for field/element assignment")
        scope[var] = assign_function_path(scope[var], parts[2:end], value, "function `$(f.name)`")
    end
    return scope
end

function run_statement!(scope, st::BaseModelicaIfStatement, f)
    has_else = length(st.branches) > length(st.conditions)
    for (i, cond_ast) in enumerate(st.conditions)
        cond = Symbolics.value(eval_AST(cond_ast))
        if cond === true
            return run_statements!(scope, st.branches[i], f)
        elseif cond === false
            continue
        end
        # Symbolic condition: evaluate both alternatives and merge with ifelse
        then_scope = copy(scope)
        with_local_scope(then_scope) do
            run_statements!(then_scope, st.branches[i], f)
        end
        rest = BaseModelicaIfStatement(st.conditions[(i + 1):end], st.branches[(i + 1):end])
        else_scope = copy(scope)
        with_local_scope(else_scope) do
            run_statement!(else_scope, rest, f)
        end
        for var in union(keys(then_scope), keys(else_scope))
            if haskey(then_scope, var) && haskey(else_scope, var)
                a, b = then_scope[var], else_scope[var]
                scope[var] = if a isa UnassignedFunctionLocal || b isa UnassignedFunctionLocal
                    UNASSIGNED_FUNCTION_LOCAL
                else
                    a === b ? a : modelica_ifelse(cond, a, b)
                end
            elseif any(entry -> entry[1] == var, f.outputs)
                unsupported("function `$(f.name)`: `$var` is assigned in only some branches of an if-statement")
            else
                scope[var] = UNASSIGNED_FUNCTION_LOCAL
            end
        end
        return scope
    end
    return has_else ? run_statements!(scope, st.branches[end], f) : scope
end

function run_statement!(scope, st::BaseModelicaForStatement, f)
    index = loop_index_name(st.index)
    for value in loop_range(st.index)
        scope[index] = value
        run_statements!(scope, st.statements, f)
    end
    delete!(scope, index)
    return scope
end

function run_statement!(scope, st::BaseModelicaFunctionCall, f)
    function_call_name(st) == "assert" && return scope
    return unsupported("function `$(f.name)`: call statement `$(function_call_name(st))(...)` is not supported")
end

run_statement!(scope, st::BaseModelicaUnsupportedStatement, f) =
    unsupported("function `$(f.name)`: $(st.description) is not supported")

run_statement!(scope, st, f) =
    unsupported("function `$(f.name)`: statement $(nameof(typeof(st))) is not supported")

# The values of a for-loop index, which must be a constant range or array.
function loop_range(index::BaseModelicaForIndex)
    range = eval_AST(index.expression)
    range isa Union{AbstractRange, AbstractVector} && all(x -> x isa Number, range) ||
        unsupported("for-loop range `$range` is not a constant range")
    length(range) <= MAX_UNROLL ||
        unsupported("for-loop with $(length(range)) iterations exceeds the unrolling limit $MAX_UNROLL")
    return range
end

# Scalar for-equations are unrolled with the loop index bound to each value.
function eval_AST(for_eq::BaseModelicaForEquation)
    vectorized = vectorize_for_equation(for_eq)
    isnothing(vectorized) || return vectorized
    index = Symbol(for_eq.index.ident isa BaseModelicaIdentifier ? for_eq.index.ident.name : for_eq.index.ident)
    result = Equation[]
    outer = LOCAL_SCOPE[]
    for value in loop_range(for_eq.index)
        scope = isnothing(outer) ? Dict{Symbol, Any}() : copy(outer)
        scope[index] = value
        with_local_scope(scope) do
            for eq in for_eq.equations
                eq_obj = eval_AST(eq)
                if eq_obj isa Equation
                    push!(result, eq_obj)
                elseif eq_obj isa AbstractVector
                    append!(result, eq_obj)
                end
            end
        end
    end
    return result
end

function eval_AST(range::BaseModelicaRange)
    # Bounds may be parameters, e.g. `for i in 1:n`: their values at load are used
    start, step, stop = map(x -> parameter_value(eval_AST(x)), (range.start, range.step, range.stop))
    all(x -> x isa Number, (start, step, stop)) ||
        unsupported("range with non-constant bounds")
    return start:step:stop
end


eval_AST(x::BaseModelicaUnsupportedExpression) = unsupported("$(x.description) is not supported")

eval_AST(::BaseModelicaAlgorithmSection) =
    unsupported("algorithm sections in models are not supported (only in functions)")
