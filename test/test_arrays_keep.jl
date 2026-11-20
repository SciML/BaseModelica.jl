using Test, BaseModelica, ModelingToolkit, OrdinaryDiffEq

const BM = BaseModelica

function keep_file(body)
    path = tempname() * ".bmo"
    write(path, "//! base 0.1.0\npackage P\nmodel M\n" * body * "\nend M;\nend P;\n")
    return path
end

function keep_solve(path; parser = :julia, arrays = :keep)
    sys = parse_basemodelica(path; parser, arrays)
    prob = ODEProblem(sys, [], (0.0, 1.0);
        missing_guess_value = BM.ModelingToolkitBase.MissingGuessValue.Constant(0.0))
    return sys, solve(prob, Tsit5(); reltol = 1e-10, abstol = 1e-12)
end

@testset "Array mode validation" begin
    @test_throws ArgumentError parse_basemodelica("missing.bmo"; arrays = :invalid)
    @test_throws ArgumentError create_odeproblem("missing.bmo"; arrays = "keep")
end

@testset "Retained arrays ($parser)" for parser in (:julia, :antlr)
    path = keep_file("""
        parameter Real k[3] = {1,2,3};
        Real x[3](start={1,2,3}, fixed=true);
        Real y[3];
    equation
        for i in 1:3 loop
            der(x[i]) = -k[i]*x[i];
        end for;
        y = cat(1, x[1:2], {x[3]});
        """)
    raw = parse_basemodelica(path; parser, arrays = :keep, simplify = false)
    @test size(raw.x) == (3,)
    @test size(raw.k) == (3,)
    @test length(equations(raw)) == 2
    @test BM.ModelingToolkitBase.getguess(raw.y) == zeros(3)
    sys, sol = keep_solve(path; parser)
    @test sol.retcode == ReturnCode.Success
    @test sol(1.0; idxs = sys.x) ≈ [exp(-1), 2exp(-2), 3exp(-3)] rtol = 1e-8
    @test sol(1.0; idxs = sys.y) ≈ sol(1.0; idxs = sys.x) rtol = 1e-8
    @test size(sol[sys.x][end]) == (3,)
    prob = create_odeproblem(path; parser, arrays = :keep)
    changed = remake(prob; p = [prob.f.sys.k => [2.0, 2.0, 2.0]])
    @test solve(changed, Tsit5(); reltol = 1e-10, abstol = 1e-12)(1.0; idxs = prob.f.sys.x) ≈
        [1,2,3] .* exp(-2) rtol = 1e-8
end

@testset "Per-variable fallback ($parser)" for parser in (:julia, :antlr)
    path = keep_file("""
        parameter Integer n=2;
        Real structural[n](start=0, fixed=true);
        Real kept[2](start=0, fixed=true);
    equation
        der(structural) = fill(1, n);
        der(kept) = ones(2);
        """)
    raw = parse_basemodelica(path; parser, arrays = :keep, simplify = false)
    @test hasproperty(raw, Symbol("structural[1]"))
    @test size(raw.kept) == (2,)
    sys, sol = keep_solve(path; parser)
    @test sol(1.0; idxs = sys.kept) ≈ ones(2) rtol = 1e-8
end

@testset "Array elements in events ($parser)" for parser in (:julia, :antlr)
    path = keep_file("""
        Real x[2](start={1,2}, fixed=true);
        discrete Real d[2](start=0);
    equation
        der(x) = -x;
        when time >= 0.5 then
            d[1] = pre(d[2]) + 1;
            d[2] = pre(d[1]) + 2;
            reinit(x[2], pre(x[1]));
        end when;
        """)
    sys, sol = keep_solve(path; parser)
    @test sol.retcode == ReturnCode.Success
    @test sol(1.0; idxs = sys.x) ≈ fill(exp(-1), 2) rtol = 1e-8
    @test sol(1.0; idxs = sys.d[1]) == 1
    @test sol(1.0; idxs = sys.d[2]) == 2
end
