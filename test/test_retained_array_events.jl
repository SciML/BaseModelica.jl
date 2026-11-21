using BaseModelica, ModelingToolkit, OrdinaryDiffEq, Test

function retained_event_model(body)
    file = tempname() * ".bmo"
    write(file, "//! base 0.1.0\npackage P\nmodel M\n" * body * "\nend M;\nend P;\n")
    return file
end

array_element(sys, name, i, arrays) = arrays == :keep ? getproperty(sys, name)[i] :
    getproperty(sys, Symbol(name, "[", i, "]"))

@testset "Array event assignments ($parser, $arrays)" for parser in (:julia, :antlr), arrays in (:scalarize, :keep)
    @testset "Constant state and pre fallback ($reinit, $dependency)" for reinit in (false, true), dependency in (:direct, :real_alias, :boolean_alias)
        extra = dependency == :real_alias ? "Real r[2];" :
            dependency == :boolean_alias ? "Boolean source(start = false);" : ""
        definition = dependency == :real_alias ? "r = 2*c; b = r[1]>0.5;" :
            dependency == :boolean_alias ? "source = c[1]>0.5; b = source;" : "b = c[1]>0.5;"
        assignment = reinit ? "reinit(x[2], if b then 10 else 20);" : "d[1] = if b then 10 else 20;"
        body = """
            Real x[2](start={0,0}, fixed=true);
            discrete Real c[2](start={0,3});
            discrete Real d[2](start={-1,-2});
            Boolean b(start=false); $extra
          equation
            der(x)={1,0}; $definition
            when x[1]>0.5 then c[1]=1; $assignment end when;
            """
        err = try
            parse_basemodelica(retained_event_model(body); parser, arrays)
            nothing
        catch e
            e
        end
        @test err isa BaseModelica.UnsupportedFeatureError
        @test occursin("plain read of relation Boolean `b`", sprint(showerror, err))
        sys = parse_basemodelica(retained_event_model(replace(body, "if b then" => "if pre(b) then")); parser, arrays)
        # Confirm that :keep exercises real MTK arrays, including the constant state.
        arrays == :keep && @test size(sys.x) == size(sys.c) == (2,)
        for alg in (Rodas5P(), FBDF())
            sol = solve(ODEProblem(sys, [], (0.0, 1.0)), alg; dtmax = 0.01, reltol = 1.0e-9, abstol = 1.0e-11)
            @test sol.retcode == ReturnCode.Success
            @test sol(0.25; idxs = array_element(sys, :c, 1, arrays)) == 0
            @test sol(0.25; idxs = array_element(sys, :x, 2, arrays)) == 0
            @test sol(1.0; idxs = array_element(sys, :c, 1, arrays)) == 1
            @test sol(1.0; idxs = array_element(sys, :c, 2, arrays)) == 3
            @test sol(1.0; idxs = array_element(sys, :d, 2, arrays)) == -2
            @test sol(1.0; idxs = array_element(sys, reinit ? :x : :d, reinit ? 2 : 1, arrays)) == 20
            @test sol(1.0; idxs = sys.b) == 1
            @test sol(1.0; idxs = array_element(sys, :x, 1, arrays)) ≈ 1 atol = 1.0e-8
        end
    end
    @testset "Continuous alias with discrete setpoint" begin
        sys = parse_basemodelica(retained_event_model("""
            Real x[2](start={0,0}, fixed=true); Real r[2]; Real q[2];
            discrete Real c[2](start={0,3}); discrete Real d[2](start={-1,-2});
            Boolean b(start=false);
          equation
            der(x)={1,2}; r=2*x; b=r[1]>1; q=c-r;
            when x[1]>0.75 then c[1]=1; d[1]=if b then 10 else 20; end when;
            """); parser, arrays)
        arrays == :keep && @test size(sys.x) == size(sys.c) == (2,)
        for alg in (Rodas5P(), FBDF())
            prob = ODEProblem(sys, [], (0.0, 1.0))
            integ = init(prob, alg; dtmax = 0.01, reltol = 1.0e-9, abstol = 1.0e-11)
            solve!(integ)
            sol = integ.sol
            c1 = array_element(sys, :c, 1, arrays)
            @test sol.retcode == ReturnCode.Success
            @test sol(0.25; idxs = c1) == 0
            @test sol(0.25; idxs = array_element(sys, :q, 1, arrays)) ≈ -0.5 atol = 1.0e-8
            @test sol(1.0; idxs = c1) == 1
            @test ModelingToolkit.getp(sys, c1)(integ) == 1
            @test unique(sol[c1]) == [0, 1]
            @test sol(1.0; idxs = array_element(sys, :c, 2, arrays)) == 3
            @test sol(1.0; idxs = array_element(sys, :d, 1, arrays)) == 10
            @test sol(1.0; idxs = array_element(sys, :q, 1, arrays)) ≈ -1 atol = 1.0e-8
            @test sol(1.0; idxs = array_element(sys, :q, 2, arrays)) ≈ -1 atol = 1.0e-8
        end
    end
    @testset "Simultaneous discrete array dependencies" begin
        sys = parse_basemodelica(retained_event_model("""
            Real x[2](start={0,0}, fixed=true);
            discrete Real c[2](start={0,0});
          equation
            der(x)={1,2};
            when x[1]>0.5 then
              c[1]=c[2]+1;
              c[2]=pre(c[2])+1;
            end when;
            """); parser, arrays)
        for alg in (Rodas5P(), FBDF())
            sol = solve(ODEProblem(sys, [], (0.0, 1.0)), alg; dtmax = 0.01)
            @test sol.retcode == ReturnCode.Success
            @test sol(1.0; idxs = array_element(sys, :c, 1, arrays)) == 2
            @test sol(1.0; idxs = array_element(sys, :c, 2, arrays)) == 1
        end
    end

    @testset "Constant state starts and custom compilation" begin
        sys = parse_basemodelica(retained_event_model("""
            Real x[2](start={0,4}, fixed=true, stateSelect=StateSelect.prefer);
            Real r[2];
          equation
            der(x)={1,0}; r=2*x;
            when x[1]>0.5 then reinit(x[2],pre(x[2])+3); end when;
            """); parser, arrays, simplify = mtkcompile)
        for alg in (Rodas5P(), FBDF())
            sol = solve(ODEProblem(sys, [], (0.0, 1.0)), alg; dtmax = 0.01)
            @test sol.retcode == ReturnCode.Success
            x2 = array_element(sys, :x, 2, arrays)
            @test sol(0.25; idxs = x2) == 4
            @test sol(1.0; idxs = x2) == 7
            @test unique(sol[x2]) == [4, 7]
            @test sol(1.0; idxs = array_element(sys, :r, 2, arrays)) == 14
        end
    end

end
