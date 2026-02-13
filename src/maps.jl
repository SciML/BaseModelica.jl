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
#   - pre(y), edge(b), change(v), reinit(x, e) — discrete event semantics
#   - initial(), terminal()                     — event phase booleans
#   - sample(start, interval)                   — periodic event generation
#   - String(...)                               — string conversion (not relevant for ODE)
#   - Integer(enum), EnumType(i)               — enumeration conversion
#
# Array functions with LIMITED support (BaseModelica array evaluation is incomplete):
#   - identity(n), diagonal(v)                 — need LinearAlgebra
#   - scalar(A), vector(A), matrix(A)          — dimensionality conversion
#   - symmetric(A), skew(x)                    — matrix construction
#   - outerProduct(x, y), cross(x, y)          — need LinearAlgebra
#   - promote(A, n)                            — dimension promotion

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
    :min => x -> Base.min(x...),
    :max => x -> Base.max(x...),

    # ── Event-triggering mathematical functions (Spec 3.7.2) ──────────────────
    # div: algebraic quotient with truncation toward zero
    :div => x -> Base.div(x[1], x[2]),
    :mod => x -> Base.mod(x[1], x[2]),
    :rem => x -> Base.rem(x[1], x[2]),
    :ceil => x -> Base.ceil(x...),
    :floor => x -> Base.floor(x...),
    :integer => x -> Base.floor(x...),

    # ── Special operators (Spec 3.7.4) ────────────────────────────────────────
    # semiLinear: smooth(0, if x >= 0 then k_pos*x else k_neg*x)
    :semiLinear => x -> ifelse(x[1] >= 0, x[2] * x[1], x[3] * x[1]),

    # homotopy: during simulation just use the actual expression
    :homotopy => x -> x[1],

    # ── Event-related functions (Spec 3.7.5) ──────────────────────────────────
    # noEvent: suppress event generation — in symbolic context, pass through
    :noEvent => x -> x[1],

    # smooth: declares expr is p times continuously differentiable — pass through
    :smooth => x -> x[2],

    # ── Array constructor functions (Spec 10.3.3) ─────────────────────────────
    :zeros => x -> Base.zeros(x...),
    :ones => x -> Base.ones(x...),
    :fill => x -> Base.fill(x[1], x[2:end]...),
    :linspace => x -> collect(range(x[1]; stop = x[2], length = Int(x[3]))),

    # ── Array dimension and size (Spec 10.3.1) ───────────────────────────────
    :ndims => x -> Base.ndims(x...),
    :size => x -> Base.size(x...),

    # ── Array reduction functions (Spec 10.3.4) ──────────────────────────────
    :sum => x -> Base.sum(x...),
    :product => x -> Base.prod(x...),

    # ── Matrix and vector algebra (Spec 10.3.5) ──────────────────────────────
    :transpose => x -> Base.transpose(x...),

    # ── Array concatenation (Spec 10.4) ──────────────────────────────────────
    :cat => x -> Base.cat(x[2:end]...; dims = Int(x[1])),
    :array => x -> [x...],

    # ── Assertion and termination (Spec 8.3.7-8.3.8) ─────────────────────────
    :assert => x -> nothing,
    :terminate => x -> nothing,
)

# holds variables, populated by evaluating component_clause
variable_map = Dict()

# holds parameter values, default values
parameter_val_map = Dict()

initial_value_map = Dict()
