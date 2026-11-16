using Test
using BaseModelica
using ModelingToolkit
using OrdinaryDiffEq

function iteration_model(body)
    path = tempname() * ".bmo"
    write(path, """//! base 0.1.0
    package 'Iteration'
      model 'Iteration'
    $body
      end 'Iteration';
    end 'Iteration';
    """)
    return path
end

@testset "Self-resetting when conditions ($parser)" for parser in (:julia, :antlr)
    @testset "$pattern" for pattern in (:P3, :P3c, :P3d, :sample_pre, :thresholds)
        declarations, other_events = if pattern === :P3
            """
                discrete Real 'T'(start = 0.25);
                discrete Real 'n'(start = 0.0);
            """, """
                when time >= pre('T') then
                  'T' = pre('T') + 0.25;
                  'n' = pre('n') + 1.0;
                end when;
            """
        elseif pattern in (:P3d, :sample_pre)
            "discrete Real 'k'(start = 0.0);", """
                when sample(0, 0.3) then 'k' = pre('k') + 1.0; end when;
            """
        else
            thresholds = pattern === :P3c ? (0.75,) : (0.75, 1.25, 2.25)
            join(["discrete Real 'k$i'(start = 0.0);" for i in eachindex(thresholds)], "\n"),
                join([
                "when 'x' > $threshold then 'k$i' = pre('k$i') + 1.0; end when;"
                    for (i, threshold) in enumerate(thresholds)
            ], "\n")
        end
        counter = pattern === :P3d ? "'c'" : "pre('c')"
        path = iteration_model("""
            Real 'x'(start = 0.0, fixed = true);
            discrete Real 'c'(start = 0.0);
            $declarations
          equation
            der('x') = 1.0;
            $other_events
            when 'x' > $counter + 0.5 then 'c' = pre('c') + 1.0; end when;
        """)
        sys = parse_basemodelica(path; parser, discrete_backend = :mtk)
        sol = solve(ODEProblem(sys, [], (0.0, 3.0)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        # Modelica 3.6 §8.3.5/§8.5 and §3.7.5: c's rising edges occur only at
        # 0.5, 1.5, 2.5. Each assignment resets its own condition. Other events
        # (including 0.75 and the sample at 0.6) cannot execute its body again.
        @test [sol(t; idxs = sys.c) for t in (0.4, 0.6, 0.9, 1.4, 1.6, 2.9)] ==
            [0, 1, 1, 1, 2, 3]
        if pattern === :P3
            @test [sol(t; idxs = sys.T) for t in (0.2, 0.3, 0.6, 2.9)] ==
                [0.25, 0.5, 0.75, 3.0]
            @test sol(2.9; idxs = sys.n) == 11
        elseif pattern in (:P3d, :sample_pre)
            # sample(0, 0.3) fires at 0, 0.3, ..., 2.7, including initialization.
            @test [sol(t; idxs = sys.k) for t in (0.1, 0.7, 2.9)] == [1, 3, 10]
        else
            @test sol(0.9; idxs = sys.k1) == 1
            if pattern === :thresholds
                @test sol(1.4; idxs = sys.k2) == 1
                @test sol(2.9; idxs = sys.k3) == 1
            end
        end
    end
end

@testset "Root timing for accepted continuous pre conditions ($parser)" for parser in (:julia, :antlr)
    path = iteration_model("""
        Real 'x'(start = 0.0, fixed = true);
        discrete Real 'tf'(start = 0.0);
      equation
        der('x') = 1.0;
        when pre('x') > 0.5 then 'tf' = time; end when;
    """)
    # Compatibility extension: §3.7.5/§3.8.4 only permit pre(continuous x)
    # in a when *body*. For this accepted condition we use pre(x) = x between
    # events, so the only crossing is at 0.5, independent of accepted steps.
    sys = parse_basemodelica(path; parser, discrete_backend = :mtk)
    for dtmax in (1.0, 0.07)
        sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5(); dtmax)
        @test sol.retcode == ReturnCode.Success
        @test sol(0.4; idxs = sys.tf) == 0
        @test sol(0.9; idxs = sys.tf) ≈ 0.5 atol = 1.0e-9
    end
end

@testset "If conditions validate when-assigned Booleans ($parser)" for parser in (:julia, :antlr)
    @testset "$form" for form in (:expression, :equation)
        use = form === :expression ? "'y' = if 'on' then 1.0 else 0.0;" :
            "if 'on' then 'y' = 1.0; else 'y' = 0.0; end if;"
        path = iteration_model("""
            Real 'x'(start = 0.0, fixed = true);
            Real 'y';
            Boolean 'on'(start = false);
          equation
            der('x') = 1.0;
            when 'x' > 0.5 then 'on' = true; end when;
            $use
        """)
        # P15 is valid Modelica: y should be 0 before 0.5, then 1 (§3.6.5).
        # Until when-assigned Booleans support this use, diagnose it explicitly.
        @test_throws BaseModelica.UnsupportedFeatureError parse_basemodelica(path; parser)

        # Equation-defined Booleans already support both forms. They must keep
        # the specified values when the condition validation is extended.
        supported = iteration_model("""
            Real 'x'(start = 0.0, fixed = true);
            Real 'y';
            Boolean 'on';
          equation
            der('x') = 1.0;
            'on' = 'x' > 0.5;
            $use
        """)
        sys = parse_basemodelica(supported; parser)
        sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        @test sol(0.4; idxs = sys.y) == 0
        @test sol(0.6; idxs = sys.y) == 1
    end
end

@testset "Unknowns read through pre in conditions ($parser)" for parser in (:julia, :antlr)
    @testset "Q30: change of an equation-defined Integer" begin
        path = iteration_model("""
            Real 'x'(start = 0.0, fixed = true);
            discrete Real 'c'(start = 0.0);
            Integer 'n';
            discrete Integer 'k'(start = 0);
          equation
            der('x') = 1.0;
            'n' = if 'c' > 0.5 then 1 else 0;
            when 'x' > 0.5 then 'c' = 1.0; end when;
            when 'n' <> pre('n') then 'k' = pre('k') + 1; end when;
        """)
        sys = parse_basemodelica(path; parser, discrete_backend = :mtk)
        sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        # §3.7.5/§8.6: n is discrete-time even without a discrete qualifier.
        # Its change activates k once, then pre(n) := n terminates iteration.
        @test [sol(t; idxs = sys.n) for t in (0.4, 0.9)] == [0, 1]
        @test [sol(t; idxs = sys.k) for t in (0.4, 0.9)] == [0, 1]
    end

    @testset "Q25: pre of an algebraic discrete-time Real" begin
        path = iteration_model("""
            Real 'x'(start = 0.0, fixed = true);
            discrete Real 'c'(start = 0.0);
            Real 'y';
            discrete Real 'd'(start = 0.0);
          equation
            der('x') = 1.0;
            'y' = 2.0 * 'c';
            when 'x' > 0.5 then 'c' = pre('c') + 1.0; end when;
            when pre('y') > 1.0 then 'd' = time; end when;
        """)
        sys = parse_basemodelica(path; parser, discrete_backend = :mtk)
        sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        # §3.7.5/§8.6: iteration 1 sets y = 2; iteration 2 sees pre(y) = 2
        # at the same instant, rather than waiting for an accepted solver step.
        @test sol(0.4; idxs = sys.d) == 0
        @test sol(0.5 + 1.0e-8; idxs = sys.d) ≈ 0.5 atol = 1.0e-9
        @test sol(0.9; idxs = sys.d) ≈ 0.5 atol = 1.0e-9
        @test sol(0.9; idxs = sys.y) == 2
    end

    # Compatibility extension: continuous arguments to pre in conditions are
    # outside §3.7.5/§3.8.4. Use pre(v) = v between events and advance condition
    # snapshots in §8.6's iteration, including after a body changes the argument.
    @testset "Q19: pre of a reinitialized state" begin
        path = iteration_model("""
            Real 'x'(start = 0.0, fixed = true);
            discrete Integer 'n'(start = 0);
          equation
            der('x') = 1.0;
            when pre('x') > 0.5 then
              reinit('x', 0.0);
              'n' = pre('n') + 1;
            end when;
        """)
        sys = parse_basemodelica(path; parser, discrete_backend = :mtk)
        sol = solve(ODEProblem(sys, [], (0.0, 3.0)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        @test [sol(t; idxs = sys.n) for t in (0.4, 0.7, 2.9)] == [0, 1, 5]
        @test sol(0.7; idxs = sys.x) ≈ 0.2 atol = 1.0e-9
    end

    @testset "Q20: pre of an algebraic continuous Real" begin
        path = iteration_model("""
            Real 'x'(start = 0.0, fixed = true);
            Real 'y';
            discrete Real 'c'(start = 0.0);
          equation
            der('x') = 1.0;
            'y' = 'x' + 'c';
            when pre('y') > 1.0 then 'c' = pre('c') - 1.0; end when;
        """)
        sys = parse_basemodelica(path; parser, discrete_backend = :mtk)
        sol = solve(ODEProblem(sys, [], (0.0, 3.0)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        @test [sol(t; idxs = sys.c) for t in (0.9, 1.1, 2.1, 2.9)] == [0, -1, -2, -2]
        @test sol(2.9; idxs = sys.y) ≈ 0.9 atol = 1.0e-9
    end
end
