module BaseModelica

using ModelingToolkit
using ParserCombinator
using MLStyle


"""
Holds the name of the package, the models in the package, and eventually BaseModelica records.
"""
struct BaseModelicaPackage
    name::Any
    model::Any
end

"""
Represents a BaseModelica model.
"""
struct BaseModelicaModel
    name::Any
    description::Any
    parameters::Any
    variables::Any
    equations::Any
    initial_equations::Any
end

struct BaseModelicaParameter
    type::Any
    name::Any
    value::Any
    description::Any
end

struct BaseModelicaVariable
    type::Any
    name::Any
    input_or_output::Any
    description::Any
end

struct BaseModelicaEquation
    lhs::Any
    rhs::Any
    description::Any
end

struct BaseModelicaInitialEquation
    lhs::Any
    rhs::Any
    description::Any
end

# needed to parse derivatives in equations correctly
@variables t
der = Differential(t)

#Includes
include("parser.jl")
include("conversion.jl")
"""
    parse_basemodelica(filename::String)::ODESystem

Parses a BaseModelica .mo file into a ModelingToolkit ODESystem.

## Example

```julia
parse_basemodelica("testfiles/NewtonCoolingBase.mo")
```
"""
function parse_basemodelica(filename::String)
    package = parse_file(filename)
    baseModelica_to_ModelingToolkit(package.model)
end

export parse_basemodelica

end
