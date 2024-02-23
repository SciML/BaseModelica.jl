module BaseModelica

using ModelingToolkit
using Automa

"Holds the name of the package, the models in the package, and eventually BaseModelica records."
struct BaseModelicaPackage
    name
    model
end

"Represents a BaseModelica model."
struct BaseModelicaModel
    name
    description
    parameters
    variables
    equations
    initialequations
end

struct BaseModelicaParameter
    type
    name
    value
    description
end

struct BaseModelicaVariable
    type
    name
    description
end

struct BaseModelicaEquation
    lhs
    rhs
    description
end

struct BaseModelicaInitialEquation
    lhs
    rhs
    description
end

# needed to parse derivatives in equations correctly
@parameters t
der = Differential(t)

#Includes
include("parser.jl")
include("conversion.jl")

export parse_str, parse_file, baseModelica_to_ModelingToolkit
end
