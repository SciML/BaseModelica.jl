module BaseModelica

using ModelingToolkit
using ParserCombinator
using MLStyle
using CondaPkg
using PythonCall

include("ast.jl")
include("julia_parser.jl")
include("antlr_parser.jl")
include("evaluator.jl")

"""
    parse_basemodelica(filename::String; parser::Symbol=:julia)::System

Parses a BaseModelica .mo file into a ModelingToolkit System.

## Arguments
- `filename::String`: Path to the .mo file to parse
- `parser::Symbol=:julia`: Parser to use. Options:
  - `:julia` - ParserCombinator parser (default)
  - `:antlr` - ANTLR parser

## Example

```julia
# Use ANTLR parser (default)
parse_basemodelica("testfiles/NewtonCoolingBase.bmo")
parse_basemodelica("testfiles/NewtonCoolingBase.bmo", parser=:antlr)
# Use ParserCombinator parser
parse_basemodelica("testfiles/NewtonCoolingBase.bmo", parser = :julia)
```
"""
function parse_basemodelica(filename::String; parser::Symbol = :antlr)
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

Parse experiment annotation to extract simulation parameters.
Returns a named tuple with StartTime, StopTime, Tolerance, and Interval, or nothing if no experiment annotation exists.

## Example
```julia
annotation = BaseModelicaAnnotation("annotation(experiment(StartTime = 0, StopTime = 2.0, Tolerance = 1e-06, Interval = 0.004))")
params = parse_experiment_annotation(annotation)
# Returns: (StartTime = 0.0, StopTime = 2.0, Tolerance = 1e-06, Interval = 0.004)
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
    create_odeproblem(filename::String; parser::Symbol=:antlr, u0=[], kwargs...)

Parse a BaseModelica file and create an ODEProblem with experiment settings from annotations.
If an experiment annotation is present, StartTime, StopTime, and Tolerance are automatically applied.

## Arguments
- `filename::String`: Path to the .mo file to parse
- `parser::Symbol=:antlr`: Parser to use (:julia or :antlr)
- `u0`: Initial conditions (default: [])
- `kwargs...`: Additional keyword arguments passed to ODEProblem

## Returns
- A tuple `(prob, sys)` where `prob` is the ODEProblem and `sys` is the System

## Example
```julia
using BaseModelica

prob, sys = create_odeproblem("testfiles/Experiment.bmo")
# The tspan and tolerances are automatically set from the annotation
```
"""
function create_odeproblem(filename::String; parser::Symbol = :antlr, u0 = [], kwargs...)
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

export parse_basemodelica, create_odeproblem, parse_experiment_annotation

end
