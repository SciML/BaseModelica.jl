# Records are values made of fields, independent of the representation of numeric arrays.
# Function values use NamedTuples; model components are expanded into field declarations
# before the chosen array lowering. No record objects are handed to ModelingToolkit.
struct RecordType
    name::String
    fields::Vector{Any}
end

const record_type_map = Dict{String, RecordType}()
const record_components = Dict{Symbol, Vector{Pair{Symbol, Symbol}}}()
const record_arrays = Dict{Symbol, Array{Symbol}}()

function register_record_types!(class_defs)
    empty!(record_type_map)
    for cd in class_defs
        cd isa BaseModelicaClassDefinition && string(cd.class_type) == "record" || continue
        class = cd.class
        class isa BaseModelicaLongClass || unsupported("short record definitions")
        name = identifier_name(class.name)
        c = class.composition
        isempty(c.equations) && isempty(c.initial_equations) && isempty(c.parameter_equations) ||
            unsupported("record `$name` with equations or algorithms")
        fields = Any[]
        names = Set{String}()
        for clause in c.components, component in clause.component_list
            field = String(component.declaration.ident[1].name)
            field in names && unsupported("record `$name` has duplicate field `$field`")
            push!(names, field)
            push!(fields, BaseModelicaComponentClause(clause.type_prefix, clause.type_specifier, [component]))
        end
        isempty(fields) && unsupported("record `$name` has no fields (short record definitions are not supported)")
        record_type_map[name] = RecordType(name, fields)
    end
    for name in keys(record_type_map)
        validate_record_type(name, String[])
    end
    return record_type_map
end

function validate_record_type(name, ancestors)
    name in ancestors && unsupported("recursive record type `$name`")
    for field in record_type_map[name].fields
        type = field.type_specifier.type
        if haskey(record_type_map, type)
            validate_record_type(type, [ancestors; name])
        elseif !(type in ("Real", "Integer", "Boolean", "String") || haskey(enum_map, type))
            unsupported("record `$name` has unsupported field type `$type`")
        end
    end
    return nothing
end

modification_value(mods) = isnothing(mods) || isempty(mods) ? BaseModelicaModification([], []) : only(mods)
modification_name(arg) = identifier_name(arg.name)

function merge_record_modification(base, override)
    a, b = modification_value(base), modification_value(override)
    args = collect(Any, something(a.class_modifications, []))
    for arg in something(b.class_modifications, [])
        i = findfirst(x -> modification_name(x) == modification_name(arg), args)
        if isnothing(i)
            push!(args, arg)
        else
            old = args[i]
            merged = merge_record_modification(
                isnothing(old.modification) ? nothing : [old.modification],
                isnothing(arg.modification) ? nothing : [arg.modification]
            )
            args[i] = BaseModelicaClassModificationArg(arg.name, only(merged))
        end
    end
    expr = isnothing(b.expr) || isempty(b.expr) ? a.expr : b.expr
    return [BaseModelicaModification(args, expr)]
end

# A field projection in a binding/start stays an AST expression: it is evaluated after all
# model symbols exist, and field arrays stay whole until array lowering handles them.
eval_AST(x::BaseModelicaFieldAccess) = record_field(eval_AST(x.expression), Symbol(x.field))
eval_AST(x::BaseModelicaNamedArgument) = unsupported("named argument outside a function call")

function record_field(value, field)
    value isa NamedTuple && haskey(value, field) ||
        unsupported("record field `$field` does not exist in `$value`")
    return getproperty(value, field)
end

function record_default(type, mods; depth = 0)
    depth < MAX_INLINE_DEPTH || unsupported("record default nesting exceeds $MAX_INLINE_DEPTH")
    mod = modification_value(mods)
    if !isnothing(mod.expr) && !isempty(mod.expr)
        return check_record_value(type, eval_AST(mod.expr[end]))
    end
    schema = record_type_map[type]
    fields = Symbol[Symbol(f.component_list[1].declaration.ident[1].name) for f in schema.fields]
    overrides = Dict{Symbol, Any}()
    for arg in something(mod.class_modifications, [])
        field = Symbol(modification_name(arg))
        field in fields || unsupported("record `$type` has no field `$field`")
        overrides[field] = isnothing(arg.modification) ? nothing : [arg.modification]
    end
    scope = isnothing(LOCAL_SCOPE[]) ? Dict{Symbol, Any}() : copy(LOCAL_SCOPE[])
    values = Any[]
    for (field, clause) in zip(fields, schema.fields)
        decl = clause.component_list[1].declaration
        merged = merge_record_modification(decl.modification, get(overrides, field, nothing))
        fieldtype = clause.type_specifier.type
        value = with_local_scope(scope) do
            if haskey(record_type_map, fieldtype)
                record_default(fieldtype, merged; depth = depth + 1)
            else
                expr = modification_value(merged).expr
                if !isnothing(expr) && !isempty(expr)
                    eval_AST(expr[end])
                else
                    subs = declaration_subscripts(decl)
                    isnothing(subs) || any(s -> s isa BMColon, subs) ? nothing :
                        fill!(Array{Any}(undef, (to_dim(eval_AST(s)) for s in subs)...), nothing)
                end
            end
        end
        # Record fields may themselves be literal-sized arrays of records.
        subs = declaration_subscripts(decl)
        if haskey(record_type_map, fieldtype) && !isnothing(subs)
            dims = literal_record_size(type * "." * String(field), subs)
            value = [record_default(fieldtype, merged; depth = depth + 1) for _ in CartesianIndices(dims)]
        end
        push!(values, value)
        scope[field] = value
    end
    return NamedTuple{Tuple(fields)}(Tuple(values))
end

function check_record_value(type, value)
    value isa NamedTuple || unsupported("value of record `$type` must be a record")
    fields = Tuple(Symbol(c.component_list[1].declaration.ident[1].name) for c in record_type_map[type].fields)
    keys(value) == fields || unsupported("record `$type` requires fields $(fields), got $(keys(value))")
    for (field, clause) in zip(fields, record_type_map[type].fields)
        fieldtype = clause.type_specifier.type
        item = value[field]
        subs = declaration_subscripts(clause.component_list[1].declaration)
        if !isnothing(subs)
            is_array(item) || unsupported("record `$type` field `$field` must be an array")
            dims = map(subs) do sub
                sub isa BMColon ? nothing : to_dim(eval_AST(sub))
            end
            ndims(item) == length(dims) && all(isnothing(d) || size(item, i) == d for (i, d) in enumerate(dims)) ||
                unsupported("record `$type` field `$field` has incompatible array size $(size(item))")
        elseif is_array(item)
            unsupported("record `$type` field `$field` must be scalar")
        end
        if haskey(record_type_map, fieldtype)
            if is_array(item)
                foreach(x -> check_record_value(fieldtype, x), item)
            else
                check_record_value(fieldtype, item)
            end
        elseif item isa NamedTuple
            unsupported("record `$type` field `$field` must have numeric or string values")
        end
    end
    return value
end

function record_constructor(type, arg_asts)
    fields = record_type_map[type].fields
    names = Symbol[Symbol(c.component_list[1].declaration.ident[1].name) for c in fields]
    args = bind_call_arguments(names, arg_asts, type)
    mods = [BaseModelicaModification([
        BaseModelicaClassModificationArg(String(k), BaseModelicaModification([], [v]))
            for (k, v) in args
    ], [])]
    # Arguments have been evaluated in the caller. Keep them as literal value ASTs while
    # resolving field defaults in declaration order.
    return require_assigned_record(check_record_value(type, record_default(type, mods)), "constructor `$type`")
end

# Evaluated call arguments are wrapped so values (including arrays and records) are never
# confused with parser AST nodes.
struct RecordArgumentValue
    value::Any
end
eval_AST(x::RecordArgumentValue) = x.value

function bind_call_arguments(names, asts, name)
    values = Dict{Symbol, RecordArgumentValue}()
    position = 0
    named = false
    for ast in asts
        if ast isa BaseModelicaNamedArgument
            named = true
            key = Symbol(identifier_name(ast.name))
            key in names || unsupported("`$name` has no argument `$key`")
            expr = ast.expression
        else
            named && unsupported("positional argument after named arguments in `$name`")
            position += 1
            position <= length(names) || unsupported("too many arguments to `$name`")
            key, expr = names[position], ast
        end
        haskey(values, key) && unsupported("duplicate argument `$key` in `$name`")
        values[key] = RecordArgumentValue(eval_AST(expr))
    end
    return values
end

function literal_record_size(name, subs)
    all(sub -> sub isa BaseModelicaNumber && isinteger(sub.val) && sub.val >= 0, subs) ||
        unsupported("array of records `$name` requires literal nonnegative integer sizes")
    return Tuple(Int(sub.val) for sub in subs)
end

function record_component_value(name)
    if haskey(record_arrays, name)
        return map(record_component_value, record_arrays[name])
    end
    pairs = record_components[name]
    return NamedTuple{Tuple(first.(pairs))}(Tuple(reference_value([String(last(p))]) for p in pairs))
end

function expand_record_components(components)
    empty!(record_components)
    empty!(record_arrays)
    result = Any[]
    for clause in components
        for comp in clause.component_list
            single = BaseModelicaComponentClause(clause.type_prefix, clause.type_specifier, [comp])
            expand_record_component!(result, single)
        end
    end
    return result
end

function expand_record_component!(result, clause)
    type = clause.type_specifier.type
    if !haskey(record_type_map, type)
        push!(result, clause)
        return
    end
    comp = only(clause.component_list)
    decl = comp.declaration
    name = String(decl.ident[1].name)
    subs = declaration_subscripts(decl)
    if !isnothing(subs)
        dims = literal_record_size(name, subs)
        names = Array{Symbol}(undef, dims)
        for index in CartesianIndices(dims)
            element = element_name(name, Tuple(index))
            names[index] = Symbol(element)
            # A record array binding/start is projected by element before by field.
            mods = split_modification(decl.modification, Tuple(index))
            newdecl = BaseModelicaDeclaration([BaseModelicaIdentifier(element)], nothing, mods)
            expand_record_component!(result, BaseModelicaComponentClause(clause.type_prefix,
                clause.type_specifier, [BaseModelicaComponentDeclaration(newdecl, comp.comment)]))
        end
        record_arrays[Symbol(name)] = names
        return
    end
    schema = record_type_map[type]
    fields = Symbol[Symbol(c.component_list[1].declaration.ident[1].name) for c in schema.fields]
    mod = modification_value(decl.modification)
    fieldmods = Dict{Symbol, Any}()
    attributes = Any[]
    for arg in something(mod.class_modifications, [])
        field = Symbol(modification_name(arg))
        if field in fields
            fieldmods[field] = isnothing(arg.modification) ? nothing : [arg.modification]
        elseif field in (:start, :fixed, :stateSelect)
            push!(attributes, arg)
        else
            unsupported("record `$type` has no field or supported attribute `$field`")
        end
    end
    mapping = Pair{Symbol, Symbol}[]
    for (field, fieldclause) in zip(fields, schema.fields)
        fieldcomp = only(fieldclause.component_list)
        fielddecl = fieldcomp.declaration
        merged = merge_record_modification(fielddecl.modification, get(fieldmods, field, nothing))
        inherited = Any[]
        for arg in attributes
            amod = arg.modification
            expr = isnothing(amod) ? nothing : amod.expr
            if modification_name(arg) == "start" && !isnothing(expr) && !isempty(expr)
                amod = BaseModelicaModification([], [BaseModelicaFieldAccess(expr[end], String(field))])
            end
            push!(inherited, BaseModelicaClassModificationArg(arg.name, amod))
        end
        binding = isnothing(mod.expr) || isempty(mod.expr) ? [] :
            [BaseModelicaFieldAccess(mod.expr[end], String(field))]
        # Explicit record binding/attributes override type defaults; per-field modifiers
        # then override inherited record attributes.
        merged = merge_record_modification(merged, [BaseModelicaModification(inherited, binding)])
        merged = merge_record_modification(merged, get(fieldmods, field, nothing))
        fullname = name * "." * String(field)
        push!(mapping, field => Symbol(fullname))
        prefix = fieldclause.type_prefix
        dpc = isnothing(clause.type_prefix.dpc) ? prefix.dpc : clause.type_prefix.dpc
        newprefix = BaseModelicaTypePrefix(clause.type_prefix.final_flag, dpc, clause.type_prefix.io)
        newdecl = BaseModelicaDeclaration([BaseModelicaIdentifier(fullname)], fielddecl.array_subs, merged)
        expand_record_component!(result, BaseModelicaComponentClause(newprefix, fieldclause.type_specifier,
            [BaseModelicaComponentDeclaration(newdecl, comp.comment)]))
    end
    record_components[Symbol(name)] = mapping
    return
end

# A record may contain arrays; branch merges and equality recurse by field without
# selecting or flattening the array representation.
function modelica_ifelse(c, a::NamedTuple, b::NamedTuple)
    keys(a) == keys(b) || unsupported("if branches return records with different fields")
    return NamedTuple{keys(a)}(map((x, y) -> modelica_ifelse(c, x, y), values(a), values(b)))
end

function equate(a::NamedTuple, b::NamedTuple)
    keys(a) == keys(b) || unsupported("record equation has different fields on its two sides")
    return reduce(vcat, [vcat(equate(a[k], b[k])) for k in keys(a)]; init = Equation[])
end

function require_assigned_record(value, context)
    isnothing(value) && unsupported("$context has an unassigned record field or array element")
    if value isa NamedTuple || is_array(value)
        foreach(x -> require_assigned_record(x, context), value)
    end
    return value
end

struct RecordDefault
    type::String
    modification::Any
end
eval_AST(x::RecordDefault) = record_default(x.type, x.modification)

# Update an immutable record or a copy of an array, so assignments in one symbolic
# branch never mutate values visible in another branch.
function assign_function_path(value, parts, replacement, context)
    isempty(parts) && return replacement
    part, rest = first(parts), parts[2:end]
    if part isa BaseModelicaArraySubscripts
        is_array(value) || unsupported("$context: subscript assignment requires an array")
        indices = Any[Colon() for _ in 1:ndims(value)]
        for (k, sub) in enumerate(part.subscripts)
            sub isa BMColon && continue
            indices[k] = to_index(with_end_size(() -> eval_AST(sub), size(value, k)))
        end
        array = Array{Any}(value)
        array[indices...] = assign_function_path(array[indices...], rest, replacement, context)
        return array
    end
    field = Symbol(part.name)
    item = record_field(value, field)
    return merge(value, NamedTuple{(field,)}((assign_function_path(item, rest, replacement, context),)))
end
