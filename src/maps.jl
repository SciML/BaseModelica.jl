# holds functions predefined or defined in the Base Modelica Package
function_map = Dict(
    :der => x -> D(x...),
    :abs => x -> Base.abs(x...),
    :sin => x -> Base.sin(x...)
)

# holds variables, populated by evaluating component_clause
variable_map = Dict()

# holds parameter values, default values
parameter_val_map = Dict()

initial_value_map = Dict()
