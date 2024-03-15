# BaseModelica

[![Build Status](https://github.com/jClugstor/BaseModelica.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/jClugstor/BaseModelica.jl/actions/workflows/CI.yml?query=branch%3Amain)

A parser for the [Base Modelica](https://github.com/modelica/ModelicaSpecification/tree/MCP/0031/RationaleMCP/0031) format. Contains utilities to parse Base Modelica model files in to Julia objects, and to convert Base Modelica models to [ModelingToolkit](https://docs.sciml.ai/ModelingToolkit/stable/) models.

So far only very simple Base Modelica models are supported. Only models with real parameters, real variables, and equations consisting of simple arithmetic equations and first order derivatives are supported. Support for the rest of the BaseModelica specification is planned to be added in the future. 

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