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
parse_basemodelica("testfiles/NewtonCoolingBase.mo")
parse_basemodelica("testfiles/NewtonCoolingBase.mo", parser=:antlr)
# Use ParserCombinator parser
parse_basemodelica("testfiles/NewtonCoolingBase.mo", parser = :julia)
```
"""
function parse_basemodelica(filename::String; parser::Symbol=:antlr)
    package = if parser == :antlr
        parse_file_with_antlr(filename)
    elseif parser == :julia
        parse_file(filename)
    else
        error("Unknown parser: $parser. Use :julia or :antlr")
    end
    baseModelica_to_ModelingToolkit(package)
end

export parse_basemodelica

end
