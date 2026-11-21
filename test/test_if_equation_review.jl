using Test, BaseModelica, ModelingToolkit, OrdinaryDiffEq
using SciMLBase: remake
import BaseModelica.Symbolics

# These filters support one model per foreground Julia process under timeout.
# ANTLR is always invoked on the calling (main) thread, never in a spawned task.
if_review_cases = Tuple(sort([first(splitext(f)) for f in readdir(joinpath(@__DIR__, "if_equation_review")) if endswith(f, ".bmo")]))
if_review_selected(values, filter) = isempty(filter) ? values : Tuple(x for x in values if string(x) == filter)
if_review_case_filter = get(ENV, "BASEMODELICA_IF_REVIEW_CASE", "")
if_review_parser_filter = get(ENV, "BASEMODELICA_IF_REVIEW_PARSER", "")
if_review_arrays_filter = get(ENV, "BASEMODELICA_IF_REVIEW_ARRAYS", "")
# A typo in a validation filter must not produce a passing empty testset.
@assert isempty(if_review_case_filter) || if_review_case_filter in if_review_cases
@assert if_review_parser_filter in ("", "julia", "antlr")
@assert if_review_arrays_filter in ("", "scalarize", "keep")

function if_review_member(sys, name)
    hasproperty(sys, Symbol(name)) && return getproperty(sys, Symbol(name))
    m = match(r"^(.*)\[([0-9,]+)\]$", name)
    isnothing(m) && error("Missing model member $name")
    return getproperty(sys, Symbol(m[1]))[parse.(Int, split(m[2], ','))...]
end

function if_review_solve(sys; problem = ODEProblem(sys, [], (0.0, 1.0)))
    # Residual rows can remain algebraic after compilation. A stiff DAE-capable
    # solver checks them as constraints instead of relying on explicit assignment.
    sol = solve(problem, Rodas5P(); reltol = 1e-9, abstol = 1e-11, tstops = [0.25, 0.5])
    @test sol.retcode == ReturnCode.Success
    return sol
end

function if_review_values(sys, sol, name, expected)
    var = if_review_member(sys, name)
    # Both sides of each switching time, avoiding event-side ambiguity at t=.5.
    for t in (0.0, 0.1, 0.375, 0.75, 1.0)
        @test sol(t; idxs = var) ≈ expected(t) rtol = 2e-7 atol = 2e-9
    end
end

if_review_rows(eqs) = reduce(vcat, (vec(vcat(Symbolics.scalarize(eq))) for eq in eqs); init = Symbolics.Equation[])

function if_review_initial_value(raw, variable, value)
    rows = if_review_rows(initialization_equations(raw))
    if BaseModelica.ModelingToolkitBase.hasdefault(variable)
        # Scalar initial assignments are represented as defaults in the backend.
        @test isempty(rows)
        @test BaseModelica.ModelingToolkitBase.getdefault(variable) == value
    else
        @test length(rows) == 1
        isempty(rows) && return
        residual = only(rows).lhs - only(rows).rhs
        # Equations store unnamespaced symbols, while sys.x adds the sys prefix.
        @test BaseModelica.concrete_value(Symbolics.substitute(residual, Dict(variable => value))) == 0
        @test BaseModelica.concrete_value(Symbolics.substitute(residual, Dict(variable => value + 1))) != 0
    end
end

@testset "If-equation review regressions" begin
@testset "If-equation review ($case, $parser, $arrays)" for
        case in if_review_selected(if_review_cases, if_review_case_filter),
        parser in if_review_selected((:julia, :antlr), if_review_parser_filter),
        arrays in if_review_selected((:scalarize, :keep), if_review_arrays_filter)
    path = joinpath(@__DIR__, "if_equation_review", case * ".bmo")
    id = first(split(case, '_'))

    if id in ("B8", "B8b", "B8c", "E2", "E5", "E6", "E7", "E8", "E9", "E10", "E11", "E12", "I10", "I11", "I15")
        # Parameter-selected nested when is valid Modelica but deliberately
        # unsupported. Dynamic unbalanced branches may never use start values.
        @test_throws BaseModelica.UnsupportedFeatureError parse_basemodelica(path; parser, arrays)
    elseif id == "I19"
        # The enum event backend cannot represent this discrete enum parameter.
        @test_throws r"Non-time dependent parameter s passed in as a discrete" parse_basemodelica(path; parser, arrays)
    elseif id == "B11b"
        # OMC rejects unequal dynamic scalar counts. In particular z=7 must
        # never disappear through a set-of-targets or first-match shortcut.
        @test_throws BaseModelica.UnsupportedFeatureError parse_basemodelica(path; parser, arrays, simplify = false)
    elseif id == "B11"
        # Even identical duplicate constraints make this OMC input overdetermined.
        # Loading the raw system must retain all four rows, including both z=6.
        raw = parse_basemodelica(path; parser, arrays, simplify = false)
        rows = if_review_rows(equations(raw))
        @test length(rows) == 4
        @test count(eq -> isequal(Symbolics.unwrap(eq.lhs), Symbolics.unwrap(getproperty(raw, :z; namespace = false))) && BaseModelica.concrete_value(eq.rhs) == 6.0, rows) == 2
        @test_throws r"system is unbalanced" parse_basemodelica(path; parser, arrays)
    elseif case in ("I3_struct_int", "I12_bool_array", "K2_ctrl_array_one_init")
        # MTK's known underdetermined array initialization can silently set the
        # first element to zero. Check the actual constraints and guesses instead.
        raw = parse_basemodelica(path; parser, arrays, simplify = false)
        target = case == "I3_struct_int" ? 5 : 2
        variable = hasproperty(raw, Symbol("x[2]")) ?
            getproperty(raw, Symbol("x[2]"); namespace = false) : getproperty(raw, :x; namespace = false)[2]
        if_review_initial_value(raw, variable, target)
        for i in 1:2
            var = if_review_member(raw, "x[$i]")
            if i == 1
                @test !BaseModelica.ModelingToolkitBase.hasdefault(var)
            end
            @test BaseModelica.ModelingToolkitBase.getguess(var) == 3
        end
    elseif case in ("P1_initial_if_no_else_array", "P1_initial_if_no_else_zeroderiv", "K3_ctrl_scalar_zeroderiv", "K1_ctrl_array_noif")
        # No inactive initial equation may pin x=0. With der(x)=0 MTK cannot
        # complete initialization; the no-if control has exactly the same limit.
        raw = parse_basemodelica(path; parser, arrays, simplify = false)
        @test isempty(initialization_equations(raw))
        variables = occursin("array", case) ? [if_review_member(raw, "x[$i]") for i in 1:2] : [raw.x]
        for var in variables
            @test !BaseModelica.ModelingToolkitBase.hasdefault(var)
            @test BaseModelica.ModelingToolkitBase.getguess(var) == 3
        end
    else
        sys = if id == "E1"
            @test_logs (:warn, r"parameters 'p', 'q' select unbalanced if-equation") min_level = Base.CoreLogging.Warn parse_basemodelica(path; parser, arrays)
        elseif id == "E13"
            @test_logs (:warn, r"parameters 'initType', 'initType2' select unbalanced if-equation") min_level = Base.CoreLogging.Warn parse_basemodelica(path; parser, arrays)
        elseif id == "B13"
            @test_logs min_level = Base.CoreLogging.Warn parse_basemodelica(path; parser, arrays)
        else
            parse_basemodelica(path; parser, arrays)
        end
        sol = if_review_solve(sys)
        if id in ("B1", "B9", "N1")
            if_review_values(sys, sol, "y", t -> t < 0.5 ? 1 : 2)
            if id == "N1"
                # The first literal true is terminal even when source branches
                # follow it; those unreachable rows must not affect balancing.
                mktempdir() do dir
                    extra = replace(read(path, String), "end if;" =>
                        "elseif time < 0.8 then y = 9.0; y = 8.0; else y = 7.0; end if;")
                    extra_path = joinpath(dir, "unreachable.bmo")
                    write(extra_path, extra)
                    extra_sys = parse_basemodelica(extra_path; parser, arrays)
                    extra_sol = if_review_solve(extra_sys)
                    if_review_values(extra_sys, extra_sol, "y", t -> t < 0.5 ? 1 : 2)
                end
            end
        elseif id == "B2"
            if_review_values(sys, sol, "y", t -> t < 0.5 ? exp(-t) : 2)
        elseif id == "B2b"
            if_review_values(sys, sol, "x", t -> t < 0.5 ? exp(-t) : exp(-0.5) + t - 0.5)
        elseif id in ("B3", "B4", "B7")
            for i in 1:(id == "B4" ? 3 : 2)
                before, after = (1, 2, 5)[i], (3, 4, 6)[i]
                if_review_values(sys, sol, "y[$i]", t -> t < 0.5 ? before : after)
            end
        elseif id == "B4b"
            if_review_values(sys, sol, "y[1]", t -> 3)
            if_review_values(sys, sol, "y[2]", t -> 7)
        elseif id in ("B5", "B5b")
            if_review_values(sys, sol, "r.a", t -> t < 0.5 ? 1 : 3)
            if_review_values(sys, sol, "r.b", t -> t < 0.5 ? 2 : 4)
        elseif id == "B6"
            if_review_values(sys, sol, "y", t -> t < 0.25 ? 1 : t < 0.5 ? 2 : 3)
        elseif id in ("B6b", "B6c")
            if_review_values(sys, sol, "y", t -> t < 0.5 ? 1 : 3)
            if_review_values(sys, sol, "z", t -> t < 0.5 ? 6 : 7)
        elseif id == "B10"
            if_review_values(sys, sol, "y", t -> 2)
            if_review_values(sys, sol, "z", t -> 1)
        elseif id == "B12"
            for i in 1:2
                if_review_values(sys, sol, "y[$i]", t -> t < 0.5 ? exp(-t) : exp(-0.5) + i * (t - 0.5))
            end
        elseif id == "B13"
            @test ModelingToolkit.istunable(sys.p)
            if_review_values(sys, sol, "r.a", t -> 3exp(-t))
            if_review_values(sys, sol, "r.b", t -> 4exp(-t))
            changed = if_review_solve(sys; problem = remake(ODEProblem(sys, [], (0.0, 1.0)); p = [sys.p => false]))
            if_review_values(sys, changed, "r.a", t -> exp(-t))
            if_review_values(sys, changed, "r.b", t -> 2exp(-t))
        elseif id in ("E1", "E3", "E4", "R7")
            if_review_values(sys, sol, "y", t -> id == "E1" ? 1 : 2)
        elseif id == "E13"
            if_review_values(sys, sol, "y", t -> 2exp(-t))
            if_review_values(sys, sol, "z", t -> 1)
        elseif id in ("I1", "I17", "I20", "P1")
            if_review_values(sys, sol, "x", t -> 3exp(-t))
        elseif id == "I2"
            if_review_values(sys, sol, "x", t -> 7exp(-t))
        elseif id == "I4"
            if_review_values(sys, sol, "y", t -> 1 + exp(-t))
        elseif id == "I13"
            if_review_values(sys, sol, "x", identity)
            if_review_values(sys, sol, "b", t -> t > 0.5)
        elseif id == "I14"
            for i in 1:2
                if_review_values(sys, sol, "x[$i]", t -> (6 + i) * exp(-t))
            end
        elseif id == "I16"
            if_review_values(sys, sol, "x", t -> 3exp(-t))
            if_review_values(sys, sol, "y", t -> 6exp(-t))
        elseif id in ("I21", "I22", "I23")
            if_review_values(sys, sol, "x", t -> 2exp(-t))
            if id == "I23"
                if_review_values(sys, sol, "w", t -> t - 0.5)
            else
                if_review_values(sys, sol, "z", t -> -1)
            end
        elseif id in ("L3", "L5")
            for i in 1:3
                if_review_values(sys, sol, "y[$i]", t -> 2^(i - 1) * exp(-t))
            end
        elseif id == "L4"
            for i in 1:3, j in 1:3
                if_review_values(sys, sol, "y[$i,$j]", t -> i == j ? exp(-t) : 10i + j)
            end
        elseif id == "K4"
            if_review_values(sys, sol, "x1", t -> 3exp(-t))
            if_review_values(sys, sol, "x2", t -> 2exp(-t))
        else
            error("Review fixture $case needs an explicit assertion")
        end
        # Every regular probe's independent state must keep its dynamics too.
        if startswith(id, "B") && !(id in ("B2b", "B12", "B13")) || id in ("E1", "E3", "E4", "L3", "L4", "L5", "N1", "R7")
            if_review_values(sys, sol, "x", t -> exp(-t))
        end
    end
end
end
