using Test, BaseModelica, ModelingToolkit, OrdinaryDiffEq

# Dyad is optional. An installed but broken Dyad must fail visibly.
dyad_available = Base.find_package("DyadInterface") !== nothing
if dyad_available
    @eval import DyadInterface
end

@testset "Compilation routes ($compiler, $parser, $arrays, $initialization)" for
        compiler in (:mtk, :dyad), parser in (:antlr, :julia),
        arrays in (:scalarize, :keep), initialization in (:fixed, :initial_equation)
    if compiler === :dyad && !dyad_available
        @test_skip dyad_available
        continue
    end
    simplify_model = compiler === :dyad ? DyadInterface.simplify_model : mtkcompile
    mktempdir() do dir
        file = joinpath(dir, "compilation.bmo")
        fixed = initialization === :fixed ? ", fixed = true" : ""
        initial = initialization === :initial_equation ? "initial equation x = {1, 2};" : ""
        write(file, """//! base 0.1.0
        package P
        model M
          parameter Real k = 1;
          Real x[2](start = {1, 2}$fixed);
          $initial
        equation
          der(x) = -k*x;
        end M;
        end P;
        """)
        for route in (:function, :manual)
            sys = if route === :function
                parse_basemodelica(file; parser, arrays, discrete_backend = :mtk,
                    simplify = simplify_model)
            else
                raw = parse_basemodelica(file; parser, arrays, discrete_backend = :mtk,
                    simplify = false)
                check_algebraic_crossings(simplify_model(raw))
            end
            @test check_algebraic_crossings(sys) === sys
            sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5(); reltol = 1e-9, abstol = 1e-11)
            @test sol.retcode == ReturnCode.Success
            for i in 1:2
                var = arrays === :keep ? sys.x[i] : getproperty(sys, Symbol("x[$i]"))
                @test sol(0.0; idxs = var) ≈ i
                @test sol(1.0; idxs = var) ≈ i*exp(-1) rtol = 1e-7
            end
        end
    end
end
