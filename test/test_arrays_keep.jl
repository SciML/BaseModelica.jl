using Test, BaseModelica, ModelingToolkit, OrdinaryDiffEq

const BM = BaseModelica

function keep_file(body)
    path = tempname() * ".bmo"
    write(path, "//! base 0.1.0\npackage P\nmodel M\n" * body * "\nend M;\nend P;\n")
    return path
end

function keep_solve(path; parser = :julia, arrays = :keep)
    sys = parse_basemodelica(path; parser, arrays)
    prob = ODEProblem(
        sys, [], (0.0, 1.0);
        missing_guess_value = BM.ModelingToolkitBase.MissingGuessValue.Constant(0.0)
    )
    return sys, solve(prob, Tsit5(); reltol = 1.0e-10, abstol = 1.0e-12)
end

@testset "Array mode validation" begin
    @test_throws ArgumentError parse_basemodelica("missing.bmo"; arrays = :invalid)
    @test_throws ArgumentError create_odeproblem("missing.bmo"; arrays = "keep")
end

@testset "Retained arrays ($parser)" for parser in (:julia, :antlr)
    path = keep_file(
        """
            parameter Real k[3] = {1,2,3};
            Real x[3](start={1,2,3}, fixed=true);
            Real y[3];
        equation
            for i in 1:3 loop
                der(x[i]) = -k[i]*x[i];
            end for;
            y = cat(1, x[1:2], {x[3]});
            """
    )
    raw = parse_basemodelica(path; parser, arrays = :keep, simplify = false)
    @test size(raw.x) == (3,)
    @test size(raw.k) == (3,)
    @test length(equations(raw)) == 2
    @test BM.ModelingToolkitBase.getguess(raw.y) == zeros(3)
    sys, sol = keep_solve(path; parser)
    @test sol.retcode == ReturnCode.Success
    @test sol(1.0; idxs = sys.x) ≈ [exp(-1), 2exp(-2), 3exp(-3)] rtol = 1.0e-8
    @test sol(1.0; idxs = sys.y) ≈ sol(1.0; idxs = sys.x) rtol = 1.0e-8
    @test size(sol[sys.x][end]) == (3,)
    prob = create_odeproblem(path; parser, arrays = :keep)
    changed = remake(prob; p = [prob.f.sys.k => [2.0, 2.0, 2.0]])
    @test solve(changed, Tsit5(); reltol = 1.0e-10, abstol = 1.0e-12)(1.0; idxs = prob.f.sys.x) ≈
        [1, 2, 3] .* exp(-2) rtol = 1.0e-8
end

@testset "Per-variable fallback ($parser)" for parser in (:julia, :antlr)
    path = keep_file(
        """
            parameter Integer n=2;
            Real structural[n](start=0, fixed=true);
            Real kept[2](start=0, fixed=true);
        equation
            der(structural) = fill(1, n);
            der(kept) = ones(2);
            """
    )
    raw = parse_basemodelica(path; parser, arrays = :keep, simplify = false)
    @test hasproperty(raw, Symbol("structural[1]"))
    @test size(raw.kept) == (2,)
    sys, sol = keep_solve(path; parser)
    @test sol(1.0; idxs = sys.kept) ≈ ones(2) rtol = 1.0e-8
end

@testset "Array elements in events ($parser)" for parser in (:julia, :antlr)
    path = keep_file(
        """
            Real x[2](start={1,2}, fixed=true);
            discrete Real d[2](start=0);
        equation
            der(x) = -x;
            when time >= 0.5 then
                d[1] = pre(d[2]) + 1;
                d[2] = pre(d[1]) + 2;
                reinit(x[2], pre(x[1]));
            end when;
            """
    )
    sys, sol = keep_solve(path; parser)
    @test sol.retcode == ReturnCode.Success
    @test sol(1.0; idxs = sys.x) ≈ fill(exp(-1), 2) rtol = 1.0e-8
    @test sol(1.0; idxs = sys.d[1]) == 1
    @test sol(1.0; idxs = sys.d[2]) == 2
end

@testset "Boolean fallback alongside retained states ($parser)" for parser in (:julia, :antlr)
    path = keep_file(
        """
            Real x[2](start={0,0}, fixed=true);
            Boolean b[2];
            Real y[2];
        equation
            der(x) = ones(2);
            b = {x[1] > 0.5, x[2] > 0.25};
            y = if time < 0.5 then x else 2*x;
            """
    )
    raw = parse_basemodelica(path; parser, arrays = :keep, simplify = false)
    @test size(raw.x) == (2,)
    @test hasproperty(raw, Symbol("b[1]"))
    sys, sol = keep_solve(path; parser)
    @test sol.retcode == ReturnCode.Success
    @test sol(1.0; idxs = sys.y) ≈ [2, 2] rtol = 1.0e-8
end

@testset "Array-valued conditional functions ($parser, $arrays)" for parser in (:julia, :antlr), arrays in (:scalarize, :keep)
    path = tempname() * ".bmo"
    write(
        path, """
        //! base 0.1.0
        package P
        function choose
          input Real u;
          input Real x[3];
          output Real y[3];
        algorithm
          if u < 0.5 then
            y := x;
          else
            y := -x;
          end if;
        end choose;
        model M
          Real x[3](start={1,2,3}, fixed=true);
          Real y[3];
          Real z[3];
        equation
          der(x) = -x;
          y = choose(time, x);
          z = cross(y, {0,0,1});
        end M;
        end P;
        """
    )
    sys, sol = keep_solve(path; parser, arrays)
    @test sol.retcode == ReturnCode.Success
    sy = arrays === :keep ? sys.y : [getproperty(sys, Symbol("y[$i]")) for i in 1:3]
    sz = arrays === :keep ? sys.z : [getproperty(sys, Symbol("z[$i]")) for i in 1:3]
    @test sol(1.0; idxs = sy) ≈ -[1, 2, 3] .* exp(-1) rtol = 1.0e-8
    @test sol(1.0; idxs = sz) ≈ [-2, 1, 0] .* exp(-1) atol = 1.0e-8
end

@testset "Array pre and element initialization ($parser)" for parser in (:julia, :antlr)
    path = keep_file(
        """
            Real x[2](start=0, fixed=true);
            discrete Real d[2](start=0);
        initial equation
            pre(d[1]) = 3;
            pre(d[2]) = 4;
        equation
            der(x) = ones(2);
            when time >= 0.5 then
                d = pre(d) + {1,2};
            end when;
            """
    )
    sys, sol = keep_solve(path; parser)
    @test sol.retcode == ReturnCode.Success
    @test sol(0.25; idxs = sys.d) == [3, 4]
    @test sol(1.0; idxs = sys.d) == [4, 6]
end

@testset "Matrix operations and non-vectorized loops ($parser)" for parser in (:julia, :antlr)
    path = keep_file(
        """
            parameter Real k[2] = {1,1};
            Real x[2](start={1,2}, fixed=true);
            Real R[2,2](start=identity(2), fixed=true);
            Real y[2];
            Real m[2,2];
        equation
            for i in 1:2 loop
                der(x[i]) = -sum({k[i]*x[i]});
            end for;
            der(R) = -R;
            y = transpose(R)*x;
            m = outerProduct(x,x);
            """
    )
    raw = parse_basemodelica(path; parser, arrays = :keep, simplify = false)
    @test length(equations(raw)) == 5
    @test size(raw.x) == (2,)
    sys, sol = keep_solve(path; parser)
    @test sol.retcode == ReturnCode.Success
    @test sol(1.0; idxs = sys.y) ≈ [1, 2] .* exp(-2) rtol = 1.0e-8
    @test sol(1.0; idxs = sys.m) ≈ [1 2; 2 4] .* exp(-2) rtol = 1.0e-8
end

@testset "Parameter slices in array starts ($parser)" for parser in (:julia, :antlr)
    path = keep_file(
        """
            parameter Real A[3,3]=identity(3);
            parameter Real v[3]=cross(A[1,:], A[2,:]);
            Real x[3](start=v, fixed=true);
        equation
            der(x)=-x;
            """
    )
    sys, sol = keep_solve(path; parser)
    @test size(sys.A) == (3, 3)
    @test sol.retcode == ReturnCode.Success
    @test sol(1.0; idxs = sys.x) ≈ [0, 0, exp(-1)] rtol = 1.0e-8
end

@testset "Array stateSelect priorities ($parser)" for parser in (:julia, :antlr)
    path = keep_file(
        """
            Real x[2](start=0, fixed=true, stateSelect=fill(StateSelect.avoid,2));
            Real y[2](start=0, fixed=true, stateSelect={StateSelect.avoid,StateSelect.prefer});
        equation
            der(x)=ones(2);
            der(y)=ones(2);
            """
    )
    raw = parse_basemodelica(path; parser, arrays = :keep, simplify = false)
    @test size(raw.x) == (2,)
    @test hasproperty(raw, Symbol("y[1]"))
    @test sort(collect(values(getfield(raw, :state_priorities)))) ==
        sort(Int.([BM.StateSelectAvoid, BM.StateSelectAvoid, BM.StateSelectPrefer]))
end

@testset "If-equation array regressions ($parser, $arrays)" for parser in (:julia, :antlr), arrays in (:scalarize, :keep)
    for branch in (
            """
            if time < 0.5 then
                y = x;
            elseif true then
                y = -x;
            end if;
            """,
            """
            if time < 0.5 then
                for i in 1:3 loop
                    y[i] = x[i];
                end for;
            else
                y = -x;
            end if;
            """,
            """
            if time < 0.5 then
                y[1:1:3] = x;
            else
                y = -x;
            end if;
            """,
        )
        path = keep_file(
            """
            Real x[3](start={1,2,3}, each fixed=true);
            Real y[3];
            Real kept[2](start=0, fixed=true);
            equation
            der(x) = -x;
            der(kept) = ones(2);
            """ * branch
        )
        raw = parse_basemodelica(path; parser, arrays, simplify = false)
        if arrays === :keep
            @test hasproperty(raw, Symbol("y[1]"))
            @test size(raw.kept) == (2,)
        end
        sys, sol = keep_solve(path; parser, arrays)
        y = [getproperty(sys, Symbol("y[$i]")) for i in 1:3]
        @test sol.retcode == ReturnCode.Success
        @test sol(0.25; idxs = y) ≈ [1, 2, 3] .* exp(-0.25) rtol = 1.0e-8
        @test sol(0.75; idxs = y) ≈ -[1, 2, 3] .* exp(-0.75) rtol = 1.0e-8
    end
end

@testset "Retained matrix powers ($parser, $arrays)" for parser in (:julia, :antlr), arrays in (:scalarize, :keep)
    path = keep_file(
        """
        Real A[2,2](start={{1,2},{3,4}}, each fixed=true);
        Real P0[2,2];
        Real P1[2,2];
        Real P2[2,2];
        Real P3[2,2];
        equation
        der(A) = -0.1*A;
        P0 = A^0;
        P1 = A^1;
        P2 = A^2;
        P3 = A^3;
        """
    )
    raw = parse_basemodelica(path; parser, arrays, simplify = false)
    arrays === :keep && @test size(raw.A) == (2, 2)
    sys, sol = keep_solve(path; parser, arrays)
    @test sol.retcode == ReturnCode.Success
    A = [1 2; 3 4] .* exp(-0.1)
    for n in 0:3
        value = arrays === :keep ? getproperty(sys, Symbol("P$n")) :
            [getproperty(sys, Symbol("P$n[$i,$j]")) for i in 1:2, j in 1:2]
        @test sol(1.0; idxs = value) ≈ A^n rtol = 1.0e-8
    end
end

@testset "Array event helper extensions" begin
    path = keep_file(
        """
        Real x[2](start=0, fixed=true);
        discrete Real d[2](start=0);
        equation
        der(x) = ones(2);
        when time >= 0.5 then
            d = pre(d) + {1,2};
        end when;
        """
    )
    raw = parse_basemodelica(path; parser = :julia, arrays = :keep, simplify = false)
    x = collect(raw.x)
    eq = BM.Equation(BM.D.(x), zeros(2))
    expected = BM.Symbolics.unwrap.(x)
    @test BM.differentiated_variables([eq, eq]) == vec(expected)
    @test BM.differentiated_variables((eq, eq)) == vec(expected)
    @test length(methods(BM.differentiated_variables)) == 1

    affect = BM.ModelingToolkitBase.ImperativeAffect
    f = (modified, observed, ctx, integrator) -> nothing
    driver = affect(f)
    scalar_read = affect(f; observed = (; x = raw.x[1]))
    @test BM.array_callback_part(driver) === driver
    @test BM.array_callback_part(scalar_read) === scalar_read
    for observed in (raw.d, raw.d[1], BM.ModelingToolkit.Pre(raw.d[2]))
        adapted = BM.array_callback_part(affect(f; observed = (; d = observed)))
        @test adapted.skip_checks
        @test adapted.f === f
        @test isequal(only(adapted.obs), observed)
    end
    modified = BM.array_callback_part(affect(f; modified = (; d = raw.d[1])))
    @test modified.skip_checks
end
