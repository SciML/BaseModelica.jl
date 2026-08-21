module BaseModelica

import CondaPkg
using DiffEqBase: BrownFullBasicInit
using MLStyle: @data, @match
import ModelingToolkit
using ModelingToolkitBase: @discretes, @named, @parameters, System, equations, mtkcompile
import ModelingToolkitBase
using ParserCombinator:
    @E_str, @e_str, @p_str, @with_names, Debug, Delayed, Drop, Lookahead, NoCache, Not, Plus,
    Space, Star, make, once
import ParserCombinator
using PrecompileTools: @compile_workload, @setup_workload
const set_name = ParserCombinator.set_name
using PythonCall: Py, pyconvert, pyhasattr, pyimport, pylen
using SciMLBase: ODEProblem
import SymbolicIndexingInterface
using SymbolicUtils: substitute
import SymbolicUtils
using Symbolics: @variables, Equation, Num
import Symbolics

include("ast.jl")
include("julia_parser.jl")
include("antlr_parser.jl")
include("evaluator.jl")

"""
    parse_basemodelica(filename::AbstractString; parser::Symbol = :antlr)

Parse a BaseModelica source file into a compiled ModelingToolkit system.

## Arguments
- `filename::AbstractString`: Path to a BaseModelica source file.

## Keyword Arguments
- `parser::Symbol = :antlr`: Parsing backend. `:antlr` uses the bundled ANTLR grammar;
  `:julia` uses the ParserCombinator implementation.

## Returns
- A compiled `ModelingToolkitBase.System` representing the equations, variables, parameters,
  and events in `filename`.

## Errors
- Throws an error when `parser` is neither `:antlr` nor `:julia`, or when the selected parser
  cannot parse `filename`.

## Examples

```julia
using BaseModelica

filename = joinpath(pkgdir(BaseModelica), "test", "testfiles", "NewtonCoolingBase.bmo")
system = parse_basemodelica(filename)
@assert !isnothing(system)
```
"""
function parse_basemodelica(filename::AbstractString; parser::Symbol = :antlr)
    filename = String(filename)
    package = if parser == :antlr
        parse_file_antlr(filename)
    elseif parser == :julia
        parse_file_julia(filename)
    else
        error("Unknown parser: $parser. Use :julia or :antlr")
    end
    return baseModelica_to_ModelingToolkit(package)
end

"""
    parse_experiment_annotation(annotation::Union{BaseModelicaAnnotation, Nothing})

Extract simulation settings from a parsed BaseModelica experiment annotation.

This is a developer-level API for code that already owns a BaseModelica AST. It does not parse
BaseModelica text and the AST representation is not a supported extension interface for ordinary
package users. Use [`create_odeproblem`](@ref) to apply experiment settings while importing a
model.

## Arguments
- `annotation::Union{BaseModelicaAnnotation, Nothing}`: A parsed AST annotation. Pass `nothing`
  when the imported model has no annotation.

## Returns
- `nothing` when no experiment annotation is present or the annotation has no experiment block.
- A named tuple with `StartTime`, `StopTime`, `Tolerance`, and `Interval` otherwise. Missing
  fields use the Modelica defaults `0.0`, `1.0`, and `1e-4`; `Interval` remains `nothing` when
  unspecified.

## Examples

```julia
using BaseModelica

parse_experiment_annotation(nothing)
# output
nothing
```
"""
function parse_experiment_annotation(annotation::Union{BaseModelicaAnnotation, Nothing})
    if isnothing(annotation)
        return nothing
    end

    annotation_content = annotation.annotation_content

    # Default values
    start_time = 0.0
    stop_time = 1.0
    tolerance = 1.0e-4
    interval = nothing

    # Both parsers now produce BaseModelicaModification structure
    if annotation_content isa BaseModelicaModification
        # annotation_content is the class_modification which contains the experiment(...) structure

        # The class_modifications should contain a single arg for "experiment"
        # which itself has nested class_modifications for the parameters
        if !isnothing(annotation_content.class_modifications) && !isempty(annotation_content.class_modifications)
            # Find the "experiment" argument
            experiment_arg = nothing
            for arg in annotation_content.class_modifications
                if arg isa BaseModelicaClassModificationArg && arg.name.name == "experiment"
                    experiment_arg = arg
                    break
                end
            end

            if !isnothing(experiment_arg) && !isnothing(experiment_arg.modification)
                # The experiment's modification contains the parameters

                exp_mod = experiment_arg.modification
                if !isnothing(exp_mod.class_modifications) && !isempty(exp_mod.class_modifications)
                    for param_arg in exp_mod.class_modifications
                        if param_arg isa BaseModelicaClassModificationArg
                            param_name = param_arg.name.name

                            # Extract value from the parameter's modification
                            if !isnothing(param_arg.modification) && !isnothing(param_arg.modification.expr) && !isempty(param_arg.modification.expr)
                                value_expr = param_arg.modification.expr[end]
                                if value_expr isa BaseModelicaNumber
                                    value = value_expr.val

                                    if param_name == "StartTime"
                                        start_time = value
                                    elseif param_name == "StopTime"
                                        stop_time = value
                                    elseif param_name == "Tolerance"
                                        tolerance = value
                                    elseif param_name == "Interval"
                                        interval = value
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    else
        return nothing
    end

    return (StartTime = start_time, StopTime = stop_time, Tolerance = tolerance, Interval = interval)
end

"""
    create_odeproblem(filename::AbstractString; parser::Symbol = :antlr, u0 = [], kwargs...)

Parse a BaseModelica source file and create an ODE problem with experiment settings.

If the model has an `annotation(experiment(...))` block, its `StartTime` and `StopTime` become
the problem time span, `Tolerance` becomes `reltol`, and `Interval` becomes `saveat`. Explicit
keyword arguments override those annotation-derived defaults.

## Arguments
- `filename::AbstractString`: Path to a BaseModelica source file.
- `u0`: Initial conditions forwarded to `SciMLBase.ODEProblem`.

## Keyword Arguments
- `parser::Symbol = :antlr`: Parsing backend, either `:antlr` or `:julia`.
- `kwargs...`: Keyword arguments forwarded to `SciMLBase.ODEProblem`. `reltol` and `saveat`
  override values read from an experiment annotation.

## Returns
- A `SciMLBase.ODEProblem` constructed from the imported ModelingToolkit system.

## Errors
- Throws an error when the parser cannot read `filename` or an unsupported parser is requested.

## Examples

```julia
using BaseModelica

filename = joinpath(pkgdir(BaseModelica), "test", "testfiles", "Experiment.bmo")
prob = create_odeproblem(filename)
prob.tspan
# output
(0.0, 2.0)
```
"""
function create_odeproblem(filename::AbstractString; parser::Symbol = :antlr, u0 = [], kwargs...)
    filename = String(filename)
    # Parse the file to get the package
    package = if parser == :antlr
        parse_file_antlr(filename)
    elseif parser == :julia
        parse_file_julia(filename)
    else
        error("Unknown parser: $parser. Use :julia or :antlr")
    end

    # Convert to ModelingToolkit
    sys = baseModelica_to_ModelingToolkit(package)

    # Collect tstops from time-based if-equation conditions (e.g. `if time < 1e-5`)
    # so the ODE solver stops exactly at each discontinuity.
    model_tstops = isempty(tstops_collection) ? nothing : sort!(collect(tstops_collection))

    # Extract experiment annotation from the model's composition
    annotation = nothing
    if package.model isa BaseModelicaModel
        long_class = package.model.long_class_specifier
        if long_class isa BaseModelicaLongClass
            composition = long_class.composition
            if composition isa BaseModelicaComposition
                annotation = composition.annotation
            end
        end
    end

    # Parse experiment settings
    exp_params = parse_experiment_annotation(annotation)

    # Create ODEProblem with appropriate time span and tolerance
    if !isnothing(exp_params)
        tspan = (exp_params.StartTime, exp_params.StopTime)

        # Build kwargs with annotation defaults, but allow user overrides
        # Check if reltol or saveat are already in kwargs
        kwargs_keys = keys(kwargs)

        # Start with annotation values
        annotation_kwargs = NamedTuple()
        if !(:reltol in kwargs_keys)
            annotation_kwargs = merge(annotation_kwargs, (reltol = exp_params.Tolerance,))
        end
        if !(:saveat in kwargs_keys) && !isnothing(exp_params.Interval)
            annotation_kwargs = merge(annotation_kwargs, (saveat = exp_params.Interval,))
        end

        # Merge annotation defaults with user kwargs (user kwargs take precedence)
        prob = ODEProblem(sys, u0, tspan; missing_guess_value = ModelingToolkitBase.MissingGuessValue.Constant(0.0), annotation_kwargs..., kwargs...)
        return prob
    else
        # Default time span if no annotation
        tspan = (0.0, 1.0)
        prob = ODEProblem(sys, u0, tspan; missing_guess_value = ModelingToolkitBase.MissingGuessValue.Constant(0.0), kwargs...)
        return prob
    end
end

include("precompilation.jl")

export parse_basemodelica, create_odeproblem, parse_experiment_annotation

end
