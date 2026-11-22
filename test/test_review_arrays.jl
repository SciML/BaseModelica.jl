using Test, BaseModelica, ModelingToolkit, OrdinaryDiffEq

function review_array_member(sys, name, dims, arrays)
    arrays === :keep && hasproperty(sys, Symbol(name)) && return getproperty(sys, Symbol(name))
    return [getproperty(sys, Symbol(BaseModelica.element_name(name, Tuple(i)))) for i in CartesianIndices(dims)]
end

# Exact source inputs from review fb08ca60. Assert values on both sides of the
# branch boundary, as the errors originally occurred while constructing the system.
@testset "Array review inputs ($parser, $arrays)" for parser in (:julia, :antlr), arrays in (:scalarize, :keep)
    path(case) = joinpath(@__DIR__, "review_arrays", "$case.bmo")
    for case in ("P2a_if_no_else_array", "P2b_if_branches_loop_vs_whole", "P2c_matrix_power", "P3_empty_sum", "div_initial_zero_lhs", "div_pre_whole_array_initial")
        @testset "$case" begin
            sys = parse_basemodelica(path(case); parser, arrays)
            sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Rodas5P(); reltol = 1e-10, abstol = 1e-12)
            @test sol.retcode == ReturnCode.Success
            if startswith(case, "P2a") || startswith(case, "P2b")
                n = startswith(case, "P2a") ? 2 : 3
                y = review_array_member(sys, "y", (n,), arrays)
                @test sol(0.25; idxs = y) ≈ collect(1:n) .* exp(-0.25) atol = 1e-8
                @test sol(0.75; idxs = y) ≈ -collect(1:n) .* exp(-0.75) atol = 1e-8
            elseif startswith(case, "P2c")
                p = review_array_member(sys, "P2", (2, 2), arrays)
                @test sol(1.0; idxs = vec(p)) ≈ vec([7 10; 15 22] .* exp(-0.2)) atol = 1e-8
            elseif case == "P3_empty_sum"
                @test sol(1.0; idxs = sys.y) ≈ exp(-1) atol = 1e-8
            elseif case == "div_initial_zero_lhs"
                x = review_array_member(sys, "x", (2,), arrays)
                @test sol(0.0; idxs = x) ≈ [1, 2]
                @test sol(1.0; idxs = x) ≈ [1, 2] .* exp(-1) atol = 1e-8
            else
                e = review_array_member(sys, "e", (2,), arrays)
                d = review_array_member(sys, "d", (2,), arrays)
                @test sol(0.25; idxs = e) ≈ [7, 8]
                @test sol(0.25; idxs = d) ≈ [5, 0]
                @test sol(1.0; idxs = d) ≈ [6, 2]
                @test sol(1.0; idxs = e) ≈ [13, 10]
            end
        end
    end
end

# The review's pass-through backend receives scalar equations, even when the
# continuous model keeps array declarations. Use the original 3000-element input.
struct ReviewPassBackend <: BaseModelica.AbstractDiscreteBackend end
BaseModelica.lower_discrete(::ReviewPassBackend, m::BaseModelica.DiscreteModel) =
    BaseModelica.LoweredDiscrete(; equations = m.equations, initial_conditions = Pair[s => v for (s, v) in m.discretes])
@testset "Review pass-through backend ($arrays)" for arrays in (:scalarize, :keep)
    sys = parse_basemodelica(joinpath(@__DIR__, "review_arrays", "backend_big.bmo");
        parser = :antlr, arrays, discrete_backend = ReviewPassBackend(), simplify = false)
    @test length(equations(sys)) == 3000
end
