# Array variables, scalarized at load.
#
# Base Modelica keeps arrays: `Real 'x'[3]`, `der('x') = -'x'`, `'A' * 'x'`, `'x'[2:3]`.
# Array sizes outside functions are constant, so every array component is expanded into
# scalar components named like the scalarized output of Modelica tools (`x[1]`, `A[1,2]`)
# before the model is translated, and the rest of the conversion only sees scalars:
#
# - `scalarize_components` replaces the clause of an array component by one clause per
#   element. Modifications are split per element with `BaseModelicaArrayElement`: the
#   element `x[i]` of `Real x[3](start = s)` gets the start value `s[i]` if `s` is an array,
#   and `s` itself if it is a scalar (an attribute modifier given as a scalar applies to
#   every element).
# - A reference to `x` evaluates to a Julia `Array` of the element symbols, so subscripts,
#   slices and the array operators are ordinary Julia array operations on symbolic scalars.
# - An equation between arrays becomes one equation per element.
#
# ModelingToolkit symbolic arrays (`@variables x(t)[1:3]`) were not used: `mtkcompile`
# scalarizes them anyway, and several of its passes (index reduction, alias elimination,
# observed-equation generation, events) handle array-valued unknowns less reliably than
# scalar ones.

# array component name => names of its scalar elements, with the array's shape
const array_components = Dict{Symbol, Array{Symbol}}()

# name of a scalarized element (`"x[1]"`) => name of its array (`"x"`)
const scalarized_from = Dict{String, String}()

# Values of the parameters and constants that array sizes can be computed from, see
# `structural_scope`
const structural_values = Dict{Symbol, Any}()

# Size of the array dimension being subscripted, the value of `end` in a subscript
const END_SIZE = Ref{Union{Nothing, Int}}(nothing)

# Values of array expressions shared by all elements of a scalarized component, see
# `eval_AST(::BaseModelicaArrayElement)`
const ELEMENT_CACHE = IdDict{Any, Any}()

# Only structural expressions may replace symbolic parameters by their load-time values.
const STRUCTURAL_EVAL = Ref(false)

function with_structural_eval(f)
    old = STRUCTURAL_EVAL[]
    STRUCTURAL_EVAL[] = true
    try
        return f()
    finally
        STRUCTURAL_EVAL[] = old
    end
end

eval_dimension(ast) = with_structural_eval(() -> eval_AST(ast))

is_array(x) = x isa AbstractArray

# The subscripts of a declaration, or `nothing`: :antlr stores `nothing` or one
# BaseModelicaArraySubscripts, :julia a (possibly empty) list of them.
function declaration_subscripts(decl)
    subs = decl.array_subs
    isnothing(subs) && return nothing
    if subs isa AbstractVector
        isempty(subs) && return nothing
        subs = only(subs)
    end
    return collect(Any, subs.subscripts)
end

"""
    reference_parts(ref)

The identifiers of component reference `ref` and the subscripts of its last part
(`nothing` without subscripts). Both parsers store the subscripts of a part right after its
identifier in `ref_list`.
"""
function reference_parts(ref::BaseModelicaComponentReference)
    names = String[]
    subscripts = nothing
    for part in ref.ref_list
        if part isa BaseModelicaArraySubscripts
            isnothing(subscripts) ||
                unsupported("component reference with several subscript lists")
            subscripts = collect(Any, part.subscripts)
        else
            isnothing(subscripts) ||
                unsupported("subscripts on a record component (`a[i].b`) are not supported")
            push!(names, String(part.name))
        end
    end
    return names, subscripts
end

reference_name(ref::BaseModelicaComponentReference) = Symbol(first(reference_parts(ref)[1]))

element_name(name, index) = string(name, "[", join(Tuple(index), ","), "]")

# A Modelica Integer value (parsed as Float64) as an Int
function to_int(x, what)
    value = parameter_value(x)
    if isnothing(value)
        # e.g. `fill(0.0, n)` for a parameter `n`, whose value is not collected yet
        name = symbol_name(x)
        value = isnothing(name) ? nothing : get(structural_values, name, nothing)
    end
    value isa Number && isinteger(value) ||
        unsupported("$what `$x` is not a constant integer")
    return Int(value)
end

function to_index(x)
    if x isa AbstractArray
        return [to_int(v, "array subscript") for v in x]
    end
    x isa Bool && unsupported("Boolean array subscripts are not supported")
    return to_int(x, "array subscript")
end

to_dim(x) = to_int(x, "array size")

# The number `x` is, or has with the values of the parameters it refers to, or `nothing`
function parameter_value(x)
    value = concrete_value(x)
    isnothing(value) || return value
    x isa Union{Num, SymbolicUtils.BasicSymbolic} || return nothing
    value = resolve_value(x, parameter_val_map)
    # Substitution alone can leave terms such as floor(3 / 2) unevaluated.
    value = SymbolicUtils.substitute(value, Dict(); fold = Val(true))
    concrete = concrete_value(value)
    isnothing(concrete) || return concrete
    # A function can be called from a binding before later parameters have been collected.
    # Their structural values are already available from the array-size pre-pass.
    bindings = Dict{Any, Any}()
    for var in Symbolics.get_variables(value)
        name = symbol_name(Num(var))
        haskey(structural_values, name) && (bindings[var] = structural_values[name])
    end
    return concrete_value(SymbolicUtils.substitute(value, bindings; fold = Val(true)))
end

function with_end_size(f, n)
    old = END_SIZE[]
    END_SIZE[] = n
    try
        return f()
    finally
        END_SIZE[] = old
    end
end

"""
    apply_subscripts(value, subscripts)

`value[subscripts...]` with Modelica semantics: `:` selects a whole dimension, `end` is the
size of the subscripted dimension, a vector subscript slices and omitted trailing subscripts
select whole dimensions.
"""
function apply_subscripts(value, subscripts)
    is_array(value) || unsupported("subscripted expression `$value` is not an array")
    length(subscripts) <= ndims(value) ||
        unsupported("$(length(subscripts)) subscripts for an array with $(ndims(value)) dimensions")
    indices = Any[Colon() for _ in 1:ndims(value)]
    for (k, sub) in enumerate(subscripts)
        sub isa BMColon && continue
        indices[k] = to_index(with_end_size(() -> eval_AST(sub), size(value, k)))
    end
    return value[indices...]
end

function eval_AST(x::BaseModelicaIdentifier)
    x.name == "end" && return end_size()
    return unsupported("identifier `$(x.name)` in an expression")
end

function end_size()
    isnothing(END_SIZE[]) && unsupported("`end` outside an array subscript")
    return END_SIZE[]
end

eval_AST(x::BaseModelicaArrayReference) = apply_subscripts(eval_AST(x.term), x.indexes.subscripts)

function eval_AST(x::BaseModelicaArrayElement)
    # Every element of a scalarized component evaluates the same modification; evaluate it
    # once. Only expressions outside function bodies and loops are cached: their value does
    # not depend on a local scope.
    cacheable = isnothing(LOCAL_SCOPE[]) && EVAL_MODE[] === :normal
    value = cacheable ? get!(() -> eval_AST(x.expression), ELEMENT_CACHE, x.expression) :
        eval_AST(x.expression)
    return is_array(value) ? value[x.index...] : value
end

# `{a, b, c}`: a vector of scalars, or an array of one more dimension whose first index
# selects the element
function stack_elements(elements)
    isempty(elements) && return Any[]
    any(is_array, elements) || return [el for el in elements]
    all(is_array, elements) || unsupported("array constructor mixes scalars and arrays")
    return stack(elements; dims = 1)
end

eval_AST(array::BaseModelicaArrayConstructor) = stack_elements([eval_AST(el) for el in array.elements])

loop_index_name(index::BaseModelicaForIndex) =
    Symbol(index.ident isa BaseModelicaIdentifier ? index.ident.name : index.ident)

function eval_AST(x::BaseModelicaArrayComprehension)
    name = loop_index_name(x.index)
    outer = LOCAL_SCOPE[]
    elements = map(loop_range(x.index)) do value
        scope = isnothing(outer) ? Dict{Symbol, Any}() : copy(outer)
        scope[name] = value
        with_local_scope(() -> eval_AST(x.expression), scope)
    end
    return stack_elements(elements)
end

# `[a, b; c, d]`: rows are concatenated along the second dimension, then stacked along the
# first; scalars are 1×1 matrices and vectors are columns
function as_matrix_block(x)
    is_array(x) || return fill(x, 1, 1)
    ndims(x) == 1 && return reshape(x, :, 1)
    return x
end

function eval_AST(x::BaseModelicaMatrixConstructor)
    rows = [reduce(hcat, [as_matrix_block(eval_AST(el)) for el in row]) for row in x.rows]
    return reduce(vcat, rows)
end

# ── Operators ────────────────────────────────────────────────────────────────

function check_same_size(a, b, op)
    size(a) == size(b) ||
        throw(DimensionMismatch("`$op` of arrays of sizes $(size(a)) and $(size(b))"))
    return nothing
end

function modelica_add(a, b)
    is_array(a) || is_array(b) || return a + b
    is_array(a) && is_array(b) && check_same_size(a, b, "+")
    return a .+ b
end

function modelica_sub(a, b)
    is_array(a) || is_array(b) || return a - b
    is_array(a) && is_array(b) && check_same_size(a, b, "-")
    return a .- b
end

# `*`: scalar times array, vector·vector (scalar product), matrix·vector, vector·matrix and
# matrix·matrix
function modelica_mul(a, b)
    (is_array(a) && is_array(b)) || return is_array(a) || is_array(b) ? a .* b : a * b
    if ndims(a) == 1 && ndims(b) == 1
        check_same_size(a, b, "*")
        return sum(a .* b)
    elseif ndims(a) == 1 && ndims(b) == 2
        return vec(permutedims(a) * b)
    end
    return a * b
end

function modelica_div(a, b)
    is_array(b) && unsupported("division by an array; use `./`")
    return is_array(a) ? a ./ b : a / b
end

function modelica_pow(a, b)
    is_array(a) || return a^b
    ndims(a) == 2 && size(a, 1) == size(a, 2) ||
        unsupported("`^` of a non-square array; use `.^`")
    n = to_int(b, "matrix power")
    n >= 0 || unsupported("negative matrix power")
    result = [i == j ? one(eltype(a)) : zero(eltype(a)) for i in axes(a, 1), j in axes(a, 2)]
    for _ in 1:n
        result = result * a
    end
    return result
end

function modelica_ifelse(c, a, b)
    (a isa NamedTuple || b isa NamedTuple) &&
        unsupported("if branches must return records with matching fields")
    return is_array(a) || is_array(b) ? broadcast((x, y) -> modelica_ifelse(c, x, y), a, b) : ifelse(c, a, b)
end

# An equation between two expressions, one equation per element for arrays
function equate(lhs, rhs)
    (lhs isa NamedTuple || rhs isa NamedTuple) &&
        unsupported("record equation requires records with the same fields on both sides")
    is_array(lhs) || is_array(rhs) || return lhs ~ rhs
    is_array(lhs) && is_array(rhs) && check_same_size(lhs, rhs, "=")
    left, right = broadcast_pair(lhs, rhs)
    if any(x -> x isa NamedTuple, left) || any(x -> x isa NamedTuple, right)
        return reduce(vcat, (vcat(equate(l, r)) for (l, r) in zip(left, right)); init = Equation[])
    end
    return vec(Equation[l ~ r for (l, r) in zip(left, right)])
end

broadcast_pair(a, b) = (is_array(a) ? a : fill(a, size(b)), is_array(b) ? b : fill(b, size(a)))

# ── Built-in functions on arrays ─────────────────────────────────────────────

# Built-in scalar functions that apply elementwise to array arguments (Spec 12.4.6)
const ELEMENTWISE_FUNCTIONS = Set(
    [
        :der, :sin, :cos, :tan, :asin, :acos, :atan, :atan2, :sinh, :cosh, :tanh, :exp, :log,
        :log10, :abs, :sign, :sqrt, :div, :mod, :rem, :ceil, :floor, :integer, :delay,
        :semiLinear,
    ]
)

function call_builtin(name::Symbol, args)
    f = function_map[name]
    if STRUCTURAL_EVAL[] && name in (:floor, :ceil, :integer, :div)
        args = map(args) do arg
            if is_array(arg)
                map(x -> something(parameter_value(x), x), arg)
            else
                something(parameter_value(arg), arg)
            end
        end
    end
    if name in ELEMENTWISE_FUNCTIONS && any(is_array, args)
        return broadcast((xs...) -> f(collect(Any, xs)), args...)
    end
    return f(args)
end

identity_matrix(n) = [i == j ? 1 : 0 for i in 1:to_dim(n), j in 1:to_dim(n)]

diagonal_matrix(v) = [i == j ? v[i] : zero(v[i]) for i in eachindex(v), j in eachindex(v)]

function cross_product(x, y)
    length(x) == 3 && length(y) == 3 || unsupported("cross expects two 3-vectors")
    return [x[2] * y[3] - x[3] * y[2], x[3] * y[1] - x[1] * y[3], x[1] * y[2] - x[2] * y[1]]
end

function skew_matrix(x)
    length(x) == 3 || unsupported("skew expects a 3-vector")
    z = zero(x[1])
    return [z -x[3] x[2]; x[3] z -x[1]; -x[2] x[1] z]
end

symmetric_matrix(A) = [i <= j ? A[i, j] : A[j, i] for i in axes(A, 1), j in axes(A, 2)]

function to_vector(x)
    is_array(x) || return [x]
    count(>(1), size(x)) <= 1 || unsupported("vector() of an array with more than one dimension of size > 1")
    return vec(x)
end

to_matrix(x) = is_array(x) ? (ndims(x) == 1 ? reshape(x, :, 1) : x) : fill(x, 1, 1)

reduce_or_scalar(f, reduction, x) = length(x) == 1 && is_array(x[1]) ? reduction(x[1]) : f(x...)

# ── Scalarization of array components ────────────────────────────────────────

# The kind of value an array size can be computed from: numbers and arrays of numbers
function structural_value(value)
    if is_array(value)
        values = map(structural_value, value)
        return any(isnothing, values) ? nothing : values
    end
    value isa Union{Number, AbstractString} && !(value isa Num) && return value
    return concrete_value(value)
end

"""
    structural_scope(components)

The values of the parameters and constants of `components` whose bindings are numbers, or
expressions of other such values, such as `n` in `parameter Integer n = 3; Real x[n];`.
Used to compute array sizes; the components are translated as usual afterwards.
"""
function structural_scope(components)
    bindings = Tuple{Symbol, Any}[]
    for comp in components
        comp.type_prefix.dpc in ("parameter", "constant") || continue
        declaration = comp.component_list[1].declaration
        expr = binding_expression(declaration)
        isnothing(expr) || push!(bindings, (Symbol(declaration.ident[1].name), expr))
    end
    scope = Dict{Symbol, Any}()
    n_tstops = length(tstops_collection)
    progress = true
    while progress
        progress = false
        for (name, expr) in bindings
            haskey(scope, name) && continue
            value = try
                structural_value(with_local_scope(() -> eval_dimension(expr), scope))
            catch
                nothing
            end
            isnothing(value) && continue
            scope[name] = value
            progress = true
        end
    end
    # Evaluating if-expressions records time events; these evaluations are not the model's
    resize!(tstops_collection, n_tstops)
    return scope
end

function array_size(name, subscripts, declaration, scope)
    dims = map(enumerate(subscripts)) do (k, sub)
        sub isa BMColon && return nothing
        value = try
            with_local_scope(() -> eval_dimension(sub), scope)
        catch e
            e isa UnsupportedFeatureError || rethrow()
            nothing
        end
        value = isnothing(value) ? nothing : concrete_value(value)
        value isa Number && isinteger(value) ||
            unsupported("size of array `$name` is not a constant integer: $(subscripts[k])")
        return Int(value)
    end
    any(isnothing, dims) || return Tuple(dims)
    # `x[:] = {1, 2, 3}`: the size comes from the binding
    value = get(scope, Symbol(name), nothing)
    if isnothing(value)
        expr = binding_expression(declaration)
        value = isnothing(expr) ? nothing :
            try
                with_local_scope(() -> eval_AST(expr), scope)
        catch
                nothing
        end
    end
    is_array(value) && ndims(value) == length(dims) ||
        unsupported("size of array `$name` declared with `:` cannot be determined from its binding")
    return Tuple(something(d, size(value, k)) for (k, d) in enumerate(dims))
end

function split_modification(mod::BaseModelicaModification, index)
    class_modifications = map(mod.class_modifications) do arg
        arg isa BaseModelicaClassModificationArg && !isnothing(arg.modification) || return arg
        # `each` applies this entire modifier to every component of the current array.
        # Consume the marker here; a field array can then split its own modifiers later.
        modification = arg.each ? arg.modification : split_modification(arg.modification, index)
        BaseModelicaClassModificationArg(arg.name, modification)
    end
    exprs = isnothing(mod.expr) || isempty(mod.expr) ? mod.expr :
        Any[BaseModelicaArrayElement(mod.expr[end], index)]
    return BaseModelicaModification(class_modifications, exprs)
end

function split_modification(mods::AbstractVector, index)
    isempty(mods) && return mods
    return Any[split_modification(only(mods), index)]
end

split_modification(::Nothing, index) = nothing

"""
    scalarize_components(components)

`components` with every array component replaced by one scalar component per element,
named like `x[1]` or `A[1,2]`, in column-major order. Fills `array_components` and
`scalarized_from`.
"""
function scalarize_components(components)
    empty!(array_components)
    empty!(scalarized_from)
    empty!(structural_values)
    empty!(ELEMENT_CACHE)
    any(comp -> has_array_subscripts(comp.component_list[1].declaration), components) ||
        return components
    scope = structural_scope(components)
    merge!(structural_values, scope)
    result = []
    for comp in components
        length(comp.component_list) == 1 ||
            unsupported("component clauses declaring several components are not supported")
        component = comp.component_list[1]
        declaration = component.declaration
        subscripts = declaration_subscripts(declaration)
        if isnothing(subscripts)
            push!(result, comp)
            continue
        end
        name = String(declaration.ident[1].name)
        dims = array_size(name, subscripts, declaration, scope)
        names = Array{Symbol}(undef, dims)
        for index in CartesianIndices(dims)
            element = element_name(name, Tuple(index))
            names[index] = Symbol(element)
            scalarized_from[element] = name
            element_declaration = BaseModelicaDeclaration(
                [BaseModelicaIdentifier(element)], nothing,
                split_modification(declaration.modification, Tuple(index))
            )
            push!(
                result, BaseModelicaComponentClause(
                    comp.type_prefix, comp.type_specifier,
                    [BaseModelicaComponentDeclaration(element_declaration, component.comment)]
                )
            )
        end
        array_components[Symbol(name)] = names
    end
    return result
end

# The current symbols (or inlined values) of the elements of array component `name`.
# Initial algorithms write scalarized names into their local scope; subsequent array
# references, including slices and reductions, must see those writes too.
function element_array(name::Symbol)
    scope = LOCAL_SCOPE[]
    return map(array_components[name]) do n
        if !isnothing(scope) && haskey(scope, n)
            return scope[n]
        end
        return get(variable_map, n, nothing)
    end
end

"""
    scalar_element_name(ref)

The name of the scalar variable that `ref` refers to: its name, or for `x[2]` with constant
subscripts the scalarized element name `x[2]`. `nothing` for a reference to several elements.
"""
function scalar_element_name(ref::BaseModelicaComponentReference)
    names, subscripts = reference_parts(ref)
    name = Symbol(first(names))
    haskey(array_components, name) || return name
    isnothing(subscripts) && return nothing
    selected = apply_subscripts(array_components[name], subscripts)
    return selected isa Symbol ? selected : nothing
end

# Names of the scalar variables that `ref` may refer to: an array reference with
# subscripts that are not constant may refer to any element.
function element_names(ref::BaseModelicaComponentReference)
    names, subscripts = reference_parts(ref)
    name = Symbol(first(names))
    haskey(array_components, name) || return [name]
    elements = array_components[name]
    isnothing(subscripts) && return vec(elements)
    # This pre-scan runs before the model's symbols are declared. Structural parameter
    # values can already resolve constant indices, ranges, slices and `end`.
    selected = try
        with_local_scope(() -> apply_subscripts(elements, subscripts), structural_values)
    catch err
        # A dynamic index may refer to any element. Its expression can fail evaluation
        # before symbols exist (e.g. `i + 1`), as well as fail conversion to an integer.
        err isa Union{UnsupportedFeatureError, MethodError} || rethrow()
        return vec(elements)
    end
    return selected isa Symbol ? [selected] : vec(selected)
end
