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
    parse_basemodelica(filename::String; parser::Symbol=:julia)::ODESystem

Parses a BaseModelica .mo file into a ModelingToolkit ODESystem.

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
function parse_basemodelica(filename::String; parser::Symbol=:antlr)
    package = if parser == :antlr
        parse_file_antlr(filename)
    elseif parser == :julia
        parse_file_julia(filename)
    else
        error("Unknown parser: $parser. Use :julia or :antlr")
    end
    baseModelica_to_ModelingToolkit(package)
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
    tolerance = 1e-4
    interval = nothing

    # Check if annotation_content is a string (ANTLR parser) or structured data (Julia parser)
    if annotation_content isa String
        # ANTLR parser case - parse from text
        if !occursin("experiment", annotation_content)
            return nothing
        end

        # Extract StartTime
        start_match = match(r"StartTime\s*=\s*([0-9.eE+-]+)", annotation_content)
        if !isnothing(start_match)
            start_time = parse(Float64, start_match.captures[1])
        end

        # Extract StopTime
        stop_match = match(r"StopTime\s*=\s*([0-9.eE+-]+)", annotation_content)
        if !isnothing(stop_match)
            stop_time = parse(Float64, stop_match.captures[1])
        end

        # Extract Tolerance
        tol_match = match(r"Tolerance\s*=\s*([0-9.eE+-]+)", annotation_content)
        if !isnothing(tol_match)
            tolerance = parse(Float64, tol_match.captures[1])
        end

        # Extract Interval
        interval_match = match(r"Interval\s*=\s*([0-9.eE+-]+)", annotation_content)
        if !isnothing(interval_match)
            interval = parse(Float64, interval_match.captures[1])
        end
    elseif annotation_content isa Array
        # Julia parser case - parse from structured AST
        # Structure: [BaseModelicaIdentifier("experiment"), BaseModelicaModification(...), BaseModelicaString("")]
        if length(annotation_content) < 2
            return nothing
        end

        # Check if first element is "experiment"
        if !(annotation_content[1] isa BaseModelicaIdentifier) || annotation_content[1].name != "experiment"
            return nothing
        end

        # Second element should be the modification containing parameters
        if annotation_content[2] isa BaseModelicaModification
            mod_content = annotation_content[2].expr

            # Parse the modification array: [name1, mod1, string1, name2, mod2, string2, ...]
            i = 1
            while i <= length(mod_content)
                if mod_content[i] isa BaseModelicaIdentifier
                    param_name = mod_content[i].name

                    # Next element should be a modification with the value
                    if i + 1 <= length(mod_content) && mod_content[i + 1] isa BaseModelicaModification
                        mod_expr = mod_content[i + 1].expr
                        if !isempty(mod_expr) && mod_expr[1] isa BaseModelicaNumber
                            value = mod_expr[1].val

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

                    # Skip to next parameter (name is at i, modification at i+1, string at i+2)
                    i += 3
                else
                    i += 1
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
- A tuple `(prob, sys)` where `prob` is the ODEProblem and `sys` is the ODESystem

## Example
```julia
using BaseModelica

prob, sys = create_odeproblem("testfiles/Experiment.bmo")
# The tspan and tolerances are automatically set from the annotation
```
"""
function create_odeproblem(filename::String; parser::Symbol=:antlr, u0=[], kwargs...)
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
            annotation_kwargs = merge(annotation_kwargs, (reltol=exp_params.Tolerance,))
        end
        if !(:saveat in kwargs_keys) && !isnothing(exp_params.Interval)
            annotation_kwargs = merge(annotation_kwargs, (saveat=exp_params.Interval,))
        end

        # Merge annotation defaults with user kwargs (user kwargs take precedence)
        prob = ODEProblem(sys, u0, tspan; annotation_kwargs..., kwargs...)
        return prob
    else
        # Default time span if no annotation
        tspan = (0.0, 1.0)
        prob = ODEProblem(sys, u0, tspan; kwargs...)
        return prob
    end
end

export parse_basemodelica, create_odeproblem, parse_experiment_annotation

end
