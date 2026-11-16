# Mapping from Modelica built-in functions to Julia functions.
#
# Reference: Modelica Language Specification v3.6, Sections 3.7.1-3.7.5
# BaseModelica (flat Modelica) subset: MCP 0031 functions.md
#
# Functions are categorized by their Modelica specification section.
# Each entry takes a vector of evaluated arguments (from eval_AST).
#
# Functions NOT YET SUPPORTED (need deeper ModelingToolkit integration):
#   - delay(expr, delayTime[, delayMax])       — variable delay
#   - spatialDistribution(...)                  — transport PDE approximation
#   - edge(b), change(v), reinit(x, e)          — discrete event semantics
#   - initial(), terminal()                     — event phase booleans
#   - sample(start, interval)                   — periodic event generation
#   - String(...)                               — string conversion (not relevant for ODE)
#   - Integer(enum), EnumType(i)               — enumeration conversion
#
# Array arguments: the functions listed in `ELEMENTWISE_FUNCTIONS` (arrays.jl) apply
# elementwise; the array functions below follow Spec 10.3 for arrays of symbolic scalars.
# `promote` is not supported.

function_map = Dict(
    # ── Derivative operator (Spec 3.7.4) ──────────────────────────────────────
    :der => x -> D(x...),

    # ── Elementary mathematical functions (Spec 3.7.3) ────────────────────────
    # Trigonometric
    :sin => x -> Base.sin(x...),
    :cos => x -> Base.cos(x...),
    :tan => x -> Base.tan(x...),
    :asin => x -> Base.asin(x...),
    :acos => x -> Base.acos(x...),
    :atan => x -> Base.atan(x...),
    :atan2 => x -> Base.atan(x[1], x[2]),

    # Hyperbolic
    :sinh => x -> Base.sinh(x...),
    :cosh => x -> Base.cosh(x...),
    :tanh => x -> Base.tanh(x...),

    # Exponential and logarithmic
    :exp => x -> Base.exp(x...),
    :log => x -> Base.log(x...),
    :log10 => x -> Base.log10(x...),

    # ── Numeric functions and operators (Spec 3.7.1) ──────────────────────────
    :abs => x -> Base.abs(x...),
    :sign => x -> Base.sign(x...),
    :sqrt => x -> Base.sqrt(x...),
    :min => x -> reduce_or_scalar(Base.min, minimum, x),
    :max => x -> reduce_or_scalar(Base.max, maximum, x),

    # ── Event-triggering mathematical functions (Spec 3.7.2) ──────────────────
    # div: algebraic quotient with truncation toward zero
    :div => x -> Base.div(x[1], x[2]),
    :mod => x -> Base.mod(x[1], x[2]),
    :rem => x -> Base.rem(x[1], x[2]),
    :ceil => x -> Base.ceil(x...),
    :floor => x -> Base.floor(x...),
    :integer => x -> Base.floor(x...),

    # ── Delay operator (Spec 3.7.2.1) ──────────────────────────────────────
    :delay => x -> ModelingToolkit.EvalAt(t - x[2])(x[1]),

    # ── Special operators (Spec 3.7.4) ────────────────────────────────────────
    # semiLinear: smooth(0, if x >= 0 then k_pos*x else k_neg*x)
    :semiLinear => x -> ifelse(x[1] >= 0, x[2] * x[1], x[3] * x[1]),

    # homotopy: during simulation just use the actual expression
    :homotopy => x -> x[1],

    # ── Event-related functions (Spec 3.7.5) ──────────────────────────────────
    # pre: value of discrete variable at the previous event instant
    :pre => x -> ModelingToolkit.Pre(x...),

    # noEvent: suppress event generation — in symbolic context, pass through
    :noEvent => x -> x[1],

    # smooth: declares expr is p times continuously differentiable — pass through
    :smooth => x -> x[2],

    # ── Array constructor functions (Spec 10.3.3) ─────────────────────────────
    :zeros => x -> Base.zeros(to_dim.(x)...),
    :ones => x -> Base.ones(to_dim.(x)...),
    :fill => x -> Base.fill(x[1], to_dim.(x[2:end])...),
    :identity => x -> identity_matrix(only(x)),
    :diagonal => x -> diagonal_matrix(only(x)),
    :linspace => x -> collect(range(x[1]; stop = x[2], length = Int(x[3]))),

    # ── Array dimension and size (Spec 10.3.1) ───────────────────────────────
    :ndims => x -> Base.ndims(x...),
    :size => x -> length(x) == 1 ? collect(Base.size(x[1])) : Base.size(x[1], to_dim(x[2])),

    # ── Array reduction functions (Spec 10.3.4) ──────────────────────────────
    :sum => x -> Base.sum(x...),
    :product => x -> Base.prod(x...),

    # ── Matrix and vector algebra (Spec 10.3.5) ──────────────────────────────
    :transpose => x -> permutedims(only(x)),
    :outerProduct => x -> x[1] * permutedims(x[2]),
    :cross => x -> cross_product(x...),
    :skew => x -> skew_matrix(only(x)),
    :symmetric => x -> symmetric_matrix(only(x)),
    :scalar => x -> only(only(x)),
    :vector => x -> to_vector(only(x)),
    :matrix => x -> to_matrix(only(x)),
    # constsize(a, sizes...) only asserts sizes, which are constant here anyway
    :constsize => x -> x[1],

    # ── Array concatenation (Spec 10.4) ──────────────────────────────────────
    :cat => x -> Base.cat(x[2:end]...; dims = to_dim(x[1])),
    :array => x -> stack_elements(x),

    # ── Assertion and termination (Spec 8.3.7-8.3.8) ─────────────────────────
    :assert => x -> nothing,
    :terminate => x -> nothing,
)

# holds variables, populated by evaluating component_clause
variable_map = Dict()

# holds parameter values, default values
parameter_val_map = Dict()

initial_value_map = Dict()

# names of variables that only appear in when-equation bodies (declared as discrete parameters)
discrete_variable_names = Set{Symbol}()

# Equation-defined Integers are represented as Real unknowns in MTK. Preserve their
# declared variability for the built-in when-body read guard.
integer_variable_names = Set{Symbol}()

# names of Boolean variables defined by an equation (e.g. `off = s < 0`), lowered to
# 0/1 discrete parameters, see relation_booleans.jl
bool_comparison_names = Set{Symbol}()

# name => the Real discrete parameter (0 or 1) that holds the value of a Boolean in
# `bool_comparison_names`
relation_boolean_syms = Dict{Symbol, Any}()

# Boolean symbol => (event time, value before its first update at that time).
relation_boolean_history = Dict{Any, Tuple{Any, Any}}()

# name => start value (0.0 or 1.0, possibly a parameter expression) of a Boolean in
# `bool_comparison_names`, the value of `pre(b)` at initialization
relation_boolean_starts = Dict{Symbol, Any}()

# names of parameters declared with fixed = false (to be solved during initialization)
free_parameter_names = Set{Symbol}()

# names of parameters marked `annotation(Evaluate = true)`, in declaration order
evaluated_parameter_names = Symbol[]

# maps enum type name → (value_name → integer), e.g. "Modelica.Blocks.Types.Init" => Dict(:NoInit => 1, ...)
enum_map = Dict{String, Dict{Symbol, Int}}()

# instants (numbers or expressions of parameters) at which an if-condition comparing
# `time` with them switches, see `collect_time_events!`
tstops_collection = Any[]
