# Constants, parameters evaluated at translation, and parameters that nothing uses.
#
# - A `constant` cannot change after translation, so its value is inlined into every
#   expression that references it. ModelingToolkit's `@constants` would not be enough: it
#   is only `tunable = false` metadata, and `remake` can still change such a parameter.
# - A parameter with `annotation(Evaluate = true)` was evaluated by the tool that produced
#   the BaseModelica file, which may have used its value to size an array, unroll a loop or
#   pick an if-branch. It becomes a non-tunable parameter. ModelingToolkit has no metadata
#   that makes `remake` reject a parameter, so changing one is not an error; a warning at
#   load lists them instead.
# - A parameter that no equation, binding or start value references was most likely
#   consumed at translation by a tool that did not mark it `Evaluate = true`. A warning at
#   load lists them.

# The annotation of a component clause, or `nothing`.
function component_annotation(comp::BaseModelicaComponentClause)
    comment = comp.component_list[1].comment
    return comment isa BaseModelicaAnnotation ? comment : nothing
end

# Whether the component carries `annotation(Evaluate = true)`.
function is_evaluate_annotated(comp::BaseModelicaComponentClause)
    annotation = component_annotation(comp)
    isnothing(annotation) && return false
    value = get_class_modification_value([annotation.annotation_content], "Evaluate")
    return value === true
end

# The binding expression of a declaration (`= value`, after any class modification).
function binding_expression(declaration::BaseModelicaDeclaration)
    modification = declaration.modification
    (isnothing(modification) || isempty(modification)) && return nothing
    exprs = modification[1].expr
    (isnothing(exprs) || isempty(exprs)) && return nothing
    return exprs[end]
end

# `value` with every key of `values` substituted until nothing changes, so that chains such
# as `a = b; b = c; c = 1` resolve.
function resolve_value(value, values)
    for _ in 0:length(values)
        new_value = substitute(value, values)
        isequal(new_value, value) && break
        value = new_value
    end
    return value
end

# A concrete Julia value for `value` if it has one, or `nothing`.
function concrete_value(value)
    value = Symbolics.value(value)
    value isa Number && return value
    value isa SymbolicUtils.BasicSymbolic && SymbolicUtils.isconst(value) &&
        return SymbolicUtils.unwrap_const(value)
    return nothing
end

"""
Inline the values of the `constant` components of `components` into `variable_map`.

Constants have already been declared as symbols in `variable_map`, so the binding of one
constant may refer to another. Each constant whose binding resolves to a number is replaced
by that number. A constant without a numeric binding stays a symbol but loses tunability.
"""
function inline_constants!(variable_map, components)
    bindings = Dict{Any, Any}()
    types = Dict{Symbol, Type}()
    for comp in components
        comp.type_prefix.dpc == "constant" || continue
        comp.type_specifier.type == "String" && continue
        declaration = comp.component_list[1].declaration
        name = Symbol(declaration.ident[1].name)
        types[name] = modelica_type_to_julia(comp.type_specifier.type)
        expr = binding_expression(declaration)
        isnothing(expr) || (bindings[variable_map[name]] = eval_AST(expr))
    end
    for (name, julia_type) in types
        sym = variable_map[name]
        value = concrete_value(resolve_value(get(bindings, sym, sym), bindings))
        variable_map[name] = if isnothing(value)
            sym  # Already declared with public `tunable = false` metadata.
        else
            value isa julia_type ? value : convert(julia_type, value)
        end
    end
    return variable_map
end

# Whether `x`, a value of `variable_map`, is the value of an inlined constant.
is_inlined(x) = x isa Number && !(x isa Num)

# Names referenced by component references in `node`, skipping annotations.
function referenced_names!(names::Set{String}, node)
    if node isa BaseModelicaComponentReference
        name = node.ref_list[1].name
        push!(names, name)
        record_reference_names!(names, Symbol(name))
        foreach(ref -> referenced_names!(names, ref), node.ref_list)
    elseif node isa BaseModelicaAnnotation
        return names
    elseif node isa Union{AbstractVector, Tuple}
        foreach(child -> referenced_names!(names, child), node)
    elseif node isa BaseModelicaASTNode
        for field in fieldnames(typeof(node))
            referenced_names!(names, getfield(node, field))
        end
    end
    return names
end

"""
Names of the parameters of `composition` that no equation, binding, start value or other
attribute references. Parameters marked `Evaluate = true` are left out: they already get a
warning of their own.
"""
function inert_parameter_names(
        composition::BaseModelicaComposition, components = composition.components
    )
    referenced = Set{String}()
    for comp in composition.components, decl in comp.component_list
        referenced_names!(referenced, decl.declaration.array_subs)
        referenced_names!(referenced, decl.declaration.modification)
    end
    referenced_names!(referenced, composition.equations)
    referenced_names!(referenced, composition.initial_equations)
    referenced_names!(referenced, composition.parameter_equations)
    names = String[]
    for comp in components
        comp.type_prefix.dpc == "parameter" || continue
        comp.type_specifier.type == "String" && continue
        is_evaluate_annotated(comp) && continue
        name = comp.component_list[1].declaration.ident[1].name
        # An element of a scalarized array is referenced through its array
        array_name = get(scalarized_from, name, nothing)
        array_name in referenced && continue
        # Report an array once, by its name
        name = something(array_name, name)
        name in referenced || name in names || push!(names, name)
    end
    return names
end

# The description given to parameters marked `Evaluate = true`.
evaluated_description(name) =
    "parameter '$name' was evaluated at translation (Evaluate=true); recompile to change it"

# Quoted names, at most `limit` of them, for a one-line warning.
function quoted_names(names; limit = 10)
    quoted = join(("'$name'" for name in first(names, limit)), ", ")
    length(names) > limit && (quoted *= " and $(length(names) - limit) more")
    return quoted
end

function warn_structural_parameters(model_name, evaluated, inert)
    model_name isa BaseModelicaIdentifier && (model_name = model_name.name)
    if !isempty(evaluated)
        @warn "BaseModelica model '$model_name': parameters $(quoted_names(evaluated)) were evaluated at translation (Evaluate=true) and are not tunable; changing them after loading does not update the model, recompile to change them"
    end
    if !isempty(inert)
        @warn "BaseModelica model '$model_name': parameters $(quoted_names(inert)) are not used by any equation, binding or start value; changing them has no effect"
    end
    return nothing
end
