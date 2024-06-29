module BaseModelica

using ModelingToolkit
using ParserCombinator
using MLStyle

#Includes
include("parser.jl")
include("evaluator.jl")
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
    baseModelica_to_ModelingToolkit(package)
end

export parse_basemodelica

end
