using Test
using BaseModelica
using ModelingToolkit
using OrdinaryDiffEq

BM = BaseModelica

testfile(name) = joinpath(dirname(dirname(pathof(BM))), "test", "testfiles", name * ".bmo")

function solve_model(name, parser; tspan = (0.0, 10.0), alg = Tsit5(), arrays = :scalarize)
    sys = parse_basemodelica(testfile(name); parser, arrays)
    prob = ODEProblem(
        sys, [], tspan;
        missing_guess_value = BM.ModelingToolkitBase.MissingGuessValue.Constant(0.0)
    )
    return sys, solve(prob, alg; reltol = 1.0e-10, abstol = 1.0e-12)
end

function array_member(sys, name)
    hasproperty(sys, Symbol(name)) && return getproperty(sys, Symbol(name))
    match_element = match(r"^(.*)\[([0-9,]+)\]$", name)
    isnothing(match_element) && return getproperty(sys, Symbol(name))
    return getproperty(sys, Symbol(match_element[1]))[parse.(Int, split(match_element[2], ','))...]
end

final(sol, sys, name) = sol[array_member(sys, name)][end]

@testset "Array variables ($parser, $arrays)" for parser in (:antlr, :julia), arrays in (:scalarize, :keep)
    @testset "vector states, matrix-vector, for-equations, slices" begin
        sys, sol = solve_model("ArrayModel", parser; arrays)
        @test sol.retcode == ReturnCode.Success
        # der(x[i]) = k[i] * (1 - x[i]) with k = fill(1.0, n), x(0) = 0
        for i in 1:3
            @test final(sol, sys, "x[$i]") ≈ 1 - exp(-10) rtol = 1.0e-6
        end
        @test final(sol, sys, "total") ≈ 3 * (1 - exp(-10)) rtol = 1.0e-6
        @test final(sol, sys, "tail[2]") ≈ final(sol, sys, "x[3]")
        # der(v) = A * v, A = {{0, 1}, {-1, 0}}, v(0) = {1, 0}: v = {cos t, -sin t}
        @test final(sol, sys, "v[1]") ≈ cos(10) atol = 1.0e-5
        @test final(sol, sys, "v[2]") ≈ -sin(10) atol = 1.0e-5
        @test final(sol, sys, "w[2]") ≈ 2 * final(sol, sys, "v[2]") + 2 atol = 1.0e-8
        # [1, 2; 3, 4][1, :] .* A[2, :] = {1 * -1, 2 * 0}
        @test final(sol, sys, "row[1]") ≈ -1
        @test final(sol, sys, "row[2]") ≈ 0 atol = 1.0e-12
    end

    @testset "arrays passed to and returned from functions" begin
        sys, sol = solve_model("ArrayFunction", parser; arrays, tspan = (0.0, 1.0))
        @test sol.retcode == ReturnCode.Success
        @test final(sol, sys, "x[1]") ≈ 3 * exp(-1) rtol = 1.0e-6
        @test final(sol, sys, "x[2]") ≈ 4 * exp(-1) rtol = 1.0e-6
        @test final(sol, sys, "r") ≈ 5 * exp(-1) rtol = 1.0e-6
    end

    @testset "array-form MSL example: PID_Controller" begin
        scalar_sys, scalar_sol = solve_model("PID_Controller", parser; arrays, tspan = (0.0, 4.0), alg = Rodas5P())
        array_sys, array_sol = solve_model("PID_ControllerArray", parser; arrays, tspan = (0.0, 4.0), alg = Rodas5P())
        @test array_sol.retcode == ReturnCode.Success
        for name in ("inertia1.phi", "inertia2.w", "kinematicPTP.y[1]")
            @test final(array_sol, array_sys, name) ≈ final(scalar_sol, scalar_sys, name) rtol = 1.0e-5
        end
    end
end

@testset "sample() with parameter arguments" begin
    prob = BM.create_odeproblem(testfile("SampleParameter"))
    sol = solve(prob, Tsit5())
    sys = prob.f.sys
    # The parameters resolve to sample(0, 0.25), including ticks at both 0 and 1.
    @test sol(0.1; idxs = sys.n) == 1.0
    @test last(sol.ps[sys.n]) == 5.0
end

@testset "array helpers" begin
    pkg = BM.parse_file_antlr(testfile("ArrayModel"))
    sys = BM.baseModelica_to_ModelingToolkit(pkg; simplify = false)
    names = Set(string.(ModelingToolkit.getname.(ModelingToolkit.unknowns(sys))))
    @test "x[1]" in names && "v[2]" in names && !("x" in names)
    pars = Set(string.(ModelingToolkit.getname.(ModelingToolkit.parameters(sys))))
    @test "A[2,1]" in pars && "k[3]" in pars
    # Non-constant array sizes are rejected
    path = tempname() * ".bmo"
    write(
        path, """
        //! base 0.1.0
        package 'Bad'
          model 'Bad'
            Real 'm';
            Real 'x'['m'];
          equation
            der('m') = 1;
            'x' = fill('m', 2);
          end 'Bad';
        end 'Bad';
        """
    )
    @test_throws BM.UnsupportedFeatureError parse_basemodelica(path)
end


@testset "Array mode solution parity ($parser)" for parser in (:antlr, :julia)
    for (fixture, names, stop, alg) in (
            ("ArrayModel", ["x[1]", "v[2]", "w[1]", "tail[2]", "row[1]", "total"], 1.0, Tsit5()),
            ("ArrayFunction", ["x[1]", "x[2]", "r"], 1.0, Tsit5()),
            ("PID_ControllerArray", ["inertia1.phi", "inertia2.w", "kinematicPTP.y[1]"], 4.0, Rodas5P()),
        )
        scalar, scalar_sol = solve_model(fixture, parser; tspan = (0.0, stop), alg)
        kept, kept_sol = solve_model(fixture, parser; arrays = :keep, tspan = (0.0, stop), alg)
        @test kept_sol.retcode == ReturnCode.Success
        for name in names
            for time in range(0.0, stop; length = 21)
                @test kept_sol(time; idxs = array_member(kept, name)) ≈
                    scalar_sol(time; idxs = array_member(scalar, name)) rtol = 1.0e-8 atol = 1.0e-9
            end
        end
    end
end
