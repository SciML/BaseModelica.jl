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

    @testset "Whole-array event-step reads ($dependency)" for dependency in (:sum, :max, :alias_dot, :array_destination, :algebraic_sum)
        algebraic = dependency in (:alias_dot, :algebraic_sum) ? "Real r[2];" : ""
        definition = dependency == :alias_dot ? "r=2*c; b=r*{1,1}>0.5;" :
            dependency == :algebraic_sum ? "r=2*c;" :
            dependency == :max ? "b=max(c)>0.5;" : "b=sum(c)>0.5;"
        boolean = dependency == :algebraic_sum ? "" : "Boolean b(start=false);"
        output = dependency == :array_destination ? "discrete Real d[2](start={0,0});" :
            "discrete Real d(start=0);"
        assignment = dependency == :algebraic_sum ? "d=sum(r);" :
            dependency == :array_destination ? "d[1]=if b then 10 else 20; d[2]=pre(d[2]);" :
            "d=if b then 10 else 20;"
        err = try
            parse_basemodelica(retained_event_model("""
                Real x(start=0, fixed=true);
                discrete Real c[2](start={0,0}); $algebraic $boolean $output
              equation
                der(x)=1; $definition
                when x>0.5 then c[1]=1; c[2]=pre(c[2]); $assignment end when;
                """); parser, arrays)
            nothing
        catch e
            e
        end
        @test err isa BaseModelica.UnsupportedFeatureError
        message = dependency == :algebraic_sum ? "plain read of non-state unknown `r" :
            "plain read of relation Boolean `b`"
        @test occursin(message, sprint(showerror, err))
    end

    @testset "Independent array relation ($whole_array)" for whole_array in (false, true)
        # The indexed control must not inherit its sibling's discrete dependency.
        # The reduction control reads a continuous array even though q also reads c.
        definition = whole_array ? "r=2*x; b=sum(r)>1; q=c-r;" :
            "r[1]=2*c[1]; r[2]=2*x[2]; b=r[2]>1; q=c-r;"
        sys = parse_basemodelica(retained_event_model("""
            Real x[2](start={0,0}, fixed=true); Real r[2]; Real q[2];
            discrete Real c[2](start={0,3}); discrete Real d[2](start={-1,-2});
            Boolean b(start=false);
          equation
            der(x)={1,2}; $definition
            when x[1]>0.75 then c[1]=1; d[1]=if b then 10 else 20; end when;
            """); parser, arrays)
        arrays == :keep && @test size(sys.x) == size(sys.c) == (2,)
        for alg in (Rodas5P(), FBDF())
            sol = solve(ODEProblem(sys, [], (0.0, 1.0)), alg; dtmax = 0.01)
            @test sol.retcode == ReturnCode.Success
            @test sol(0.25; idxs = array_element(sys, :c, 1, arrays)) == 0
            @test sol(1.0; idxs = array_element(sys, :c, 1, arrays)) == 1
            @test sol(1.0; idxs = array_element(sys, :d, 1, arrays)) == 10
            @test sol(1.0; idxs = array_element(sys, :d, 2, arrays)) == -2
            @test sol(1.0; idxs = sys.b) == 1
        end
    end

end

@testset "Array dependency walker" begin
    t = BaseModelica.t
    dep, unrelated = BaseModelica.Symbolics.@variables dep(t)[1:2, 1:2] unrelated(t)[1:2]
    candidates = vec(collect(dep))
    reads(expr, vars = candidates; skip_pre = false) =
        BaseModelica.when_body_unknowns!(Any[], expr, vars; skip_pre)
    @test Set(reads(dep)) == Set(candidates)
    @test Set(reads(dep, vcat(Any[dep], candidates))) == Set(vcat(Any[dep], candidates))
    @test Set(reads(sum(dep))) == Set(candidates)
    @test isequal(reads(dep[2, 2]), [dep[2, 2]])
    @test isempty(reads(dep[2, 2], [dep[1, 1]]))
    @test isempty(reads(unrelated))
    @test Set(reads((dep[1, 1], [dep[2, 2]]))) == Set([dep[1, 1], dep[2, 2]])
    @test isempty(reads(ModelingToolkit.Pre(dep); skip_pre = true))
    @test Set(reads(ModelingToolkit.Pre(dep))) == Set(candidates)
end

@testset "MTK callback reconstruction contract" begin
    # This deliberately exercises MTKBase's internal callback constructors. Fail
    # loudly on an upstream change rather than dropping options or affect phases.
    mtk = BaseModelica.ModelingToolkitBase
    affect = mtk.ImperativeAffect(BaseModelica.ArrayEventAssignment(); ctx = Ref(:original), skip_checks = true)
    replacement = mtk.ImperativeAffect(BaseModelica.ArrayEventAssignment(); ctx = Ref(:replacement))
    callbacks = (
        mtk.SymbolicDiscreteCallback(true, affect; initialize = affect, finalize = affect,
            reinitializealg = BaseModelica.SciMLBase.NoInit(), initialize_save_discretes = false),
        mtk.SymbolicContinuousCallback([BaseModelica.t ~ 1], affect;
            affect_neg = affect, initialize = affect, finalize = affect,
            rootfind = BaseModelica.SciMLBase.RightRootFind,
            reinitializealg = BaseModelica.SciMLBase.NoInit(), initialize_save_discretes = false),
    )
    for callback in callbacks
        mapped = BaseModelica.array_map_callback_affects(callback) do part
            part === affect ? replacement : part
        end
        @test typeof(mapped) === typeof(callback)
        for field in fieldnames(typeof(callback))
            original = getfield(callback, field)
            @test getfield(mapped, field) === (original === affect ? replacement : original)
        end
        @test mapped.affect === replacement
        @test mapped.initialize === mapped.finalize === replacement
    end
end
