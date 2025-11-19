module BaseModelica

using ModelingToolkit
using ParserCombinator
using MLStyle
using CondaPkg
using PythonCall

include("ast.jl")
include("parser.jl")
include("antlr_parser.jl")
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
