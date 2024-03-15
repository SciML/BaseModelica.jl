# BaseModelica.jl

[![Join the chat at https://julialang.zulipchat.com #sciml-bridged](https://img.shields.io/static/v1?label=Zulip&message=chat&color=9558b2&labelColor=389826)](https://julialang.zulipchat.com/#narrow/stream/279055-sciml-bridged)
[![Global Docs](https://img.shields.io/badge/docs-SciML-blue.svg)](https://docs.sciml.ai/BaseModelica/stable/)

[![codecov](https://codecov.io/gh/SciML/BaseModelica.jl/branch/main/graph/badge.svg)](https://app.codecov.io/gh/SciML/BaseModelica.jl)
[![Build Status](https://github.com/SciML/BaseModelica.jl/workflows/CI/badge.svg)](https://github.com/SciML/BaseModelica.jl/actions?query=workflow%3ACI)

[![ColPrac: Contributor's Guide on Collaborative Practices for Community Packages](https://img.shields.io/badge/ColPrac-Contributor%27s%20Guide-blueviolet)](https://github.com/SciML/ColPrac)
[![SciML Code Style](https://img.shields.io/static/v1?label=code%20style&message=SciML&color=9558b2&labelColor=389826)](https://github.com/SciML/SciMLStyle)


A parser for the [Base Modelica](https://github.com/modelica/ModelicaSpecification/tree/MCP/0031/RationaleMCP/0031) format. Contains utilities to parse Base Modelica model files in to Julia objects, and to convert Base Modelica models to [ModelingToolkit](https://docs.sciml.ai/ModelingToolkit/stable/) models.

So far only very simple Base Modelica models are supported. Only models with real parameters, real variables, and equations consisting of simple arithmetic equations and first order derivatives are supported. Support for the rest of the BaseModelica specification is planned to be added in the future. 

## Installation

Assuming that you already have Julia correctly installed, it suffices to import
BaseModelica.jl in the standard way:

```julia
import Pkg;
Pkg.add("BaseModelica");
```

# Example
A Base Modelica model is in the file `ExampleFirstOrder.mo`. Inside of the file is a Base Modelica model specifying a simple first order linear differential equation:

```
package 'FirstOrder'
  model 'FirstOrder'
    parameter Real 'x0' = 0 "Initial value for 'x'";
    Real 'x' "Real variable called 'x'";
  initial equation
    'x' = 'x0' "Set initial value of 'x' to 'x0'";
  equation
    der('x') = 1.0 - 'x'; 
  end 'FirstOrder';
end 'FirstOrder';
```

To parse the model in the file to ModelingToolkit, use the `parse_basemodelica` function:

```
using BaseModelica

parse_basemodelica("path/to/ExampleFirstOrder.mo")

```
