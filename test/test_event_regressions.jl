using Test
using BaseModelica
using ModelingToolkit
using OrdinaryDiffEq

function regression_model(body)
    path = tempname() * ".bmo"
    write(
        path, """//! base 0.1.0
        package 'Regression'
          model 'Regression'
        $body
          end 'Regression';
        end 'Regression';
        """
    )
    return path
end

@testset "Event regression tests ($parser)" for parser in (:julia, :antlr)
    @testset "Retained algebraic equation with a when and no Boolean: solve-level saveat" begin
        path = regression_model(
            """
                Real 'x'(start = 0.0, fixed = true);
                Real 'y'(start = 1.0);
                discrete Real 'q'(start = 0.0, fixed = true);
              equation
                der('x') = 'q' + 1.0;
                'y' * 'y' = 'x' + 1.0;
                when time > 0.5 then
                  'q' = 'y';
                end when;
              annotation(experiment(StartTime = 0.0, StopTime = 1.0, Interval = 0.1));
            """
        )
        # MTK appends the retained algebraic equation to the affect. Its implicit
        # solve inherits problem-level saveat despite having tspan = (t, t).
        @test_broken solve(create_odeproblem(path; parser), Rodas5P();
            reltol = 1.0e-9, abstol = 1.0e-11).retcode == ReturnCode.Success
        prob = create_odeproblem(path; parser, saveat = Float64[])
        sol = solve(prob, Rodas5P(); saveat = 0.1, reltol = 1.0e-9, abstol = 1.0e-11)
        @test sol.retcode == ReturnCode.Success
        sys = prob.f.sys
        # Before the event x = t, y = sqrt(t + 1), q = 0. At t = 0.5,
        # q samples sqrt(1.5), and x then has constant slope 1 + sqrt(1.5).
        @test sol(0.4; idxs = sys.q) ≈ 0.0 atol = 1.0e-8
        @test sol(0.4; idxs = sys.x) ≈ 0.4 atol = 1.0e-8
        @test sol(0.4; idxs = sys.y) ≈ sqrt(1.4) atol = 1.0e-8
        expected_q = sqrt(1.5)
        expected_x = 0.5 + 0.5 * (1.0 + expected_q)
        @test sol(1.0; idxs = sys.q) ≈ expected_q atol = 1.0e-8
        @test sol(1.0; idxs = sys.x) ≈ expected_x atol = 1.0e-8
        @test sol(1.0; idxs = sys.y) ≈ sqrt(expected_x + 1.0) atol = 1.0e-8
    end

    @testset "Continuous sampling relation containing pre keeps its root" begin
        path = regression_model(
            """
                Real 'x'(start = 0.0, fixed = true);
                discrete Real 'T'(start = 0.25);
                discrete Real 'n'(start = 0.0);
              equation
                der('x') = 1.0;
                when time >= pre('T') then
                  'T' = pre('T') + 0.25;
                  'n' = pre('n') + 1.0;
                end when;
            """
        )
        sys = parse_basemodelica(path; parser, discrete_backend = :mtk)
        sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        # Modelica §3.7.5/§8.5: pre is shared during an iteration, then
        # advances to the new T, scheduling the next sampling threshold.
        @test [sol(t; idxs = sys.T) for t in (0.2, 0.3, 0.6)] == [0.25, 0.5, 0.75]
        @test sol(0.9; idxs = sys.n) == 3
    end

    @testset "Continuous state relation containing pre keeps its root" begin
        path = regression_model(
            """
                Real 'x'(start = 0.0, fixed = true);
                discrete Real 'c'(start = 0.0);
              equation
                der('x') = 1.0;
                when 'x' > pre('c') + 0.5 then 'c' = pre('c') + 1.0; end when;
            """
        )
        sys = parse_basemodelica(path; parser, discrete_backend = :mtk)
        sol = solve(ODEProblem(sys, [], (0.0, 3.0)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        @test [sol(t; idxs = sys.c) for t in (0.4, 0.6, 1.4, 1.6, 2.9)] == [0, 1, 1, 2, 3]
    end

    @testset "Event-generating functions in continuous when conditions are rejected" begin
        # Modelica §3.7.2 requires events at every discontinuity. In the reviewer's
        # floor(x/0.25) > count model count must be 1 at 0.3 and 3 at 0.9;
        # a root of floor(x/0.25) - count silently misses these events.
        for expression in (
                "floor('x'/0.25)", "integer('x'/0.25)", "ceil('x'/0.25)",
                "div('x', 0.25)", "mod('x', 0.25)", "rem('x', 0.25)",
            ), count in ("'count'", "pre('count')")
            path = regression_model(
                """
                    Real 'x'(start = 0.0, fixed = true);
                    discrete Real 'count'(start = 0.0);
                  equation
                    der('x') = 1.0;
                    when $expression > $count then
                      'count' = pre('count') + 1.0;
                    end when;
                """
            )
            @test_throws BaseModelica.UnsupportedFeatureError parse_basemodelica(path; parser)
        end
    end

    @testset "Logical use of when-assigned Booleans has a useful diagnostic" begin
        for condition in ("not 'on'", "'on' and not pre('on')", "'on' or not pre('on')")
            path = regression_model(
                """
                    Real 'x'(start = 0.0, fixed = true);
                    Boolean 'on'(start = false);
                    discrete Real 'n'(start = 0.0);
                  equation
                    der('x') = 1.0;
                    when 'x' > 0.5 then 'on' = true; end when;
                    when $condition then 'n' = pre('n') + 1.0; end when;
                """
            )
            @test_throws BaseModelica.UnsupportedFeatureError parse_basemodelica(path; parser)
        end
    end

    @testset "Equation Boolean pre keeps the event left limit ($cascade)" for cascade in (false, true)
        path = regression_model(
            """
                Real 'x'(start = 0.0, fixed = true);
                discrete Real 's'(start = 0.0);
                discrete Real 'k'(start = 0.0);
                Boolean 'b';
              equation
                der('x') = 1.0;
                'b' = $(cascade ? "'s'" : "'x'") > 0.5;
                when 'x' > 0.5 then 's' = 1.0; end when;
                when $(cascade ? "'s'" : "'x'") > 0.5 then
                  'k' = if pre('b') then 1.0 else 2.0;
                end when;
            """
        )
        sys = parse_basemodelica(path; parser, discrete_backend = :mtk)
        sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        @test sol(0.4; idxs = sys.k) == 0
        # Modelica 3.6 §3.7.5/§8.5: both bodies use the same left limit, b = false.
        # Updating the equation-defined Boolean is part of solving this iteration.
        @test sol(0.6; idxs = sys.b) == 1
        @test sol(0.6; idxs = sys.k) == 2
    end

    @testset "Boolean condition retains pre(b): $condition" for condition in (
            "'b' and not pre('b')", "pre('b')",
        )
        path = regression_model(
            """
                Real 'x'(start = 0.0, fixed = true);
                Boolean 'b';
                discrete Real 'k'(start = 0.0);
              equation
                der('x') = 1.0;
                'b' = 'x' > 0.5 and 'x' < 0.75;
                when $condition then 'k' = pre('k') + 1.0; end when;
            """
        )
        sys = parse_basemodelica(path; parser, discrete_backend = :mtk)
        sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        @test sol(0.4; idxs = sys.k) == 0
        # Modelica 3.6 §3.7.5: edge(b) expands to b and not pre(b).
        # `pre(b)` alone rises in the following iteration, at the same instant (§8.5).
        @test sol(0.5 + 1.0e-8; idxs = sys.k) == 1
        @test sol(0.6; idxs = sys.k) == 1
        @test sol(0.9; idxs = sys.k) == 1
    end

    @testset "pre in a condition activates a later whole-system iteration" begin
        path = regression_model(
            """
                Real 'x'(start = 0.0, fixed = true);
                discrete Real 'n'(start = 0.0);
                discrete Real 'm'(start = 0.0);
              equation
                der('x') = 1.0;
                when 'x' > 0.5 then 'n' = pre('n') + 1.0; end when;
                when pre('n') > 0.5 then 'm' = pre('n') + 10.0; end when;
            """
        )
        sys = parse_basemodelica(path; parser, discrete_backend = :mtk)
        sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        @test sol(0.4; idxs = sys.m) == 0
        # §3.7.5/§8.5: n = 1 in the first iteration; only after pre(n) := n
        # can the second when activate, using that iteration's shared pre(n) = 1.
        @test sol(0.6; idxs = sys.n) == 1
        @test sol(0.6; idxs = sys.m) == 11
    end

    @testset "Compound Boolean transitions trigger when bodies" begin
        path = regression_model(
            """
                Real 'x'(start = 0.0, fixed = true);
                Boolean 'b';
                Boolean 'copy';
                discrete Real 'n'(start = 0.0);
                discrete Real 'm'(start = 0.0);
              equation
                der('x') = 1.0;
                'b' = 'x' > 0.5 and 'x' < 0.75;
                'copy' = 'b';
                when 'b' then
                  'n' = pre('n') + 1.0;
                end when;
                when 'copy' then
                  'm' = pre('m') + 1.0;
                end when;
            """
        )
        sys = parse_basemodelica(path; parser, discrete_backend = :mtk)
        sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        @test sol(0.4; idxs = sys.n) == 0
        @test sol(0.6; idxs = sys.b) == 1
        @test sol(0.6; idxs = sys.n) == 1
        @test sol(0.6; idxs = sys.m) == 1
        @test sol(0.9; idxs = sys.b) == 0
        @test sol(0.9; idxs = sys.n) == 1
    end

    @testset "Simultaneous sample elsewhen priority and initial tick" begin
        path = regression_model(
            """
                Real 'x'(start = 0.0, fixed = true);
                discrete Real 'd'(start = 0.0);
                discrete Real 'n'(start = 0.0);
                discrete Real 'independent'(start = 0.0);
              equation
                der('x') = 1.0;
                when sample(0, 0.5) then
                  'd' = 1.0;
                  'n' = pre('n') + 10.0;
                elsewhen sample(0, 0.25) then
                  'd' = 2.0;
                  'n' = pre('n') + 1.0;
                end when;
                when sample(0, 0.25) then
                  'independent' = pre('independent') + 1.0;
                end when;
            """
        )
        sys = parse_basemodelica(path; parser, discrete_backend = :mtk)
        sol = solve(ODEProblem(sys, [], (0.0, 0.9)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        @test sol(0.1; idxs = sys.d) == 1
        @test sol(0.3; idxs = sys.d) == 2
        @test sol(0.6; idxs = sys.d) == 1
        @test sol(0.8; idxs = sys.d) == 2
        @test sol(0.6; idxs = sys.n) == 21
        @test sol(0.8; idxs = sys.n) == 22
        @test last(sol.ps[sys.independent]) == 4
        # Callback bookkeeping belongs to each solve, including after remake.
        again = solve(remake(ODEProblem(sys, [], (0.0, 0.9))), Tsit5())
        @test last(again.ps[sys.n]) == 22
        @test last(again.ps[sys.independent]) == 4
    end

    @testset "Scaled simultaneous continuous elsewhen priority" begin
        path = regression_model(
            """
                Real 'x'(start = 0.0, fixed = true);
                discrete Real 'd'(start = 0.0);
                discrete Real 'n'(start = 0.0);
                discrete Real 'other'(start = 0.0);
              equation
                der('x') = 1.0;
                when 2.0 * 'x' > 1.0 then
                  'd' = 1.0;
                  'n' = pre('n') + 1.0;
                elsewhen 'x' > 0.5 then
                  'd' = 2.0;
                  'n' = pre('n') + 100.0;
                end when;
                when 'x' > 0.5 then
                  'other' = pre('other') + 1.0;
                end when;
            """
        )
        sys = parse_basemodelica(path; parser, discrete_backend = :mtk)
        sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        @test sol(0.4; idxs = sys.d) == 0
        @test sol(0.6; idxs = sys.d) == 1
        @test last(sol.ps[sys.n]) == 1
        @test last(sol.ps[sys.other]) == 1
    end
end

@testset "Event iteration and clock phase ($parser)" for parser in (:julia, :antlr)
    @testset "When assignments trigger Boolean bodies at the same instant" begin
        path = regression_model(
            """
                Real 'x'(start = 0.0, fixed = true);
                discrete Real 'd'(start = 0.0);
                discrete Real 'n'(start = 0.0);
                discrete Real 'last'(start = 0.0);
                Boolean 'b';
                Boolean 'c';
              equation
                der('x') = 1.0;
                'b' = 'd' > 0.5;
                'c' = 'n' > 0.5;
                when 'x' > 0.5 then
                  'd' = 1.0;
                end when;
                when 'b' then
                  'n' = pre('n') + 1.0;
                end when;
                when 'c' then
                  'last' = time;
                end when;
            """
        )
        sys = parse_basemodelica(path; parser, discrete_backend = :mtk)
        sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5(); dtmax = 0.2)
        @test sol.retcode == ReturnCode.Success
        @test sol(0.5 + 1.0e-6; idxs = sys.n) == 1
        @test sol(0.5 + 1.0e-6; idxs = sys.last) ≈ 0.5 atol = 1.0e-9
        @test last(sol.ps[sys.n]) == 1
    end

    @testset "Small scales do not merge distant roots" begin
        path = regression_model(
            """
                Real 'x'(start = 0.0, fixed = true);
                discrete Real 'early'(start = 0.0);
                discrete Real 'late'(start = 0.0);
              equation
                der('x') = 1.0;
                when 'x' > 0.5 then
                  'early' = 1.0;
                end when;
                when 0.000000000001 * 'x' > 0.000000000001 then
                  'late' = 1.0;
                end when;
            """
        )
        sys = parse_basemodelica(path; parser, discrete_backend = :mtk)
        sol = solve(ODEProblem(sys, [], (0.0, 1.2)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        @test sol(0.6; idxs = sys.early) == 1
        @test sol(0.6; idxs = sys.late) == 0
        @test sol(1.1; idxs = sys.late) == 1
    end

    @testset "Sample clock keeps its phase on an offset time span" begin
        path = regression_model(
            """
                Real 'x'(start = 0.0, fixed = true);
                discrete Real 'n'(start = 0.0);
              equation
                der('x') = 1.0;
                when sample(0, 0.25) then
                  'n' = pre('n') + 1.0;
                end when;
            """
        )
        sys = parse_basemodelica(path; parser, discrete_backend = :mtk)
        sol = solve(ODEProblem(sys, [], (0.1, 0.9)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        @test sol(0.2; idxs = sys.n) == 0
        @test sol(0.3; idxs = sys.n) == 1
        @test last(sol.ps[sys.n]) == 3
    end
end

@testset "Repeated and mixed triggers ($parser)" for parser in (:julia, :antlr)
    @testset "Repeated scaled roots retain chain priority" begin
        path = regression_model(
            """
                Real 'x'(start = 0.0, fixed = true);
                discrete Real 'n'(start = 0.0);
                discrete Real 'other'(start = 0.0);
              equation
                der('x') = 1.0;
                when sin(6.283185307179586 * 'x') > 0.5 then
                  'n' = pre('n') + 1.0;
                elsewhen 2.0 * sin(6.283185307179586 * 'x') > 1.0 then
                  'n' = pre('n') + 100.0;
                end when;
                when sin(6.283185307179586 * 'x') > 0.5 then
                  'other' = pre('other') + 1.0;
                end when;
            """
        )
        sys = parse_basemodelica(path; parser, discrete_backend = :mtk)
        sol = solve(ODEProblem(sys, [], (0.0, 1.9)), Tsit5(); dtmax = 0.05)
        @test sol.retcode == ReturnCode.Success
        @test last(sol.ps[sys.n]) == 2
        @test last(sol.ps[sys.other]) == 2
    end

    @testset "Sample and continuous elsewhen triggers resolve together ($continuous_first)" for continuous_first in (false, true)
        branches = continuous_first ? """
                when 'x' > 0.5 then
                  'd' = 1.0;
                  'n' = pre('n') + 1.0;
                elsewhen sample(0, 0.5) then
                  'd' = 2.0;
                  'n' = pre('n') + 100.0;
                end when;
            """ : """
                when sample(0, 0.5) then
                  'd' = 1.0;
                  'n' = pre('n') + 10.0;
                elsewhen 'x' > 0.5 then
                  'd' = 2.0;
                  'n' = pre('n') + 100.0;
                end when;
            """
        path = regression_model(
            """
                Real 'x'(start = 0.0, fixed = true);
                discrete Real 'd'(start = 0.0);
                discrete Real 'n'(start = 0.0);
              equation
                der('x') = 1.0;
                $branches
            """
        )
        sys = parse_basemodelica(path; parser, discrete_backend = :mtk)
        sol = solve(ODEProblem(sys, [], (0.0, 0.9)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        @test sol(0.6; idxs = sys.d) == 1
        expected = continuous_first ? 101 : 20
        @test sol(0.6; idxs = sys.n) == expected
        @test last(sol.ps[sys.n]) == expected
        @test sol(0.9; idxs = sys.x) ≈ 0.9
    end
end

@testset "True initial conditions do not activate when ($parser)" for parser in (:antlr, :julia)
    # Include the root-at-t0 and downward-only cases, aliases, and an undefined
    # Boolean. A simultaneous sample must still tick without activating them.
    for sampled in (false, true)
        path = regression_model(
            """
                Real 'x'(start = 0.0, fixed = true);
                Real 'falling'(start = 1.0, fixed = true);
                Boolean 'b';
                Boolean 'alias';
                Boolean 'held'(start = true);
                discrete Real 'n'[6](start = {0.0, 0.0, 0.0, 0.0, 0.0, 0.0});
                discrete Real 'ticks'(start = 0.0);
              equation
                der('x') = 1.0;
                der('falling') = -1.0;
                'b' = 'x' > 0.0 - 1.0;
                'alias' = 'b';
                when 'x' > 0.0 - 1.0 then 'n'[1] = pre('n'[1]) + 1.0; end when;
                when 'falling' > 0.5 then 'n'[2] = pre('n'[2]) + 1.0; end when;
                when time >= 0.0 then 'n'[3] = pre('n'[3]) + 1.0; end when;
                when 'b' then 'n'[4] = pre('n'[4]) + 1.0; end when;
                when 'alias' then 'n'[5] = pre('n'[5]) + 1.0; end when;
                when 'held' then 'n'[6] = pre('n'[6]) + 1.0; end when;
                $(sampled ? "when sample(0, 0.25) then 'ticks' = pre('ticks') + 1.0; end when;" : "")
            """
        )
        sys = @test_logs (:warn, r"have no defining equation") match_mode = :any parse_basemodelica(path; parser)
        sol = solve(ODEProblem(sys, [], (0.0, 0.9)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        for i in 1:6
            @test all(iszero, sol.ps[getproperty(sys, Symbol("n[$i]"))])
        end
        @test last(sol.ps[sys.ticks]) == (sampled ? 4 : 0)
    end
end

@testset "Event iteration callback count is independent of when count" begin
    for n in (2, 10, 25)
        declarations = join(["discrete Real 'd$i'(start = 0.0);" for i in 1:n], "\n")
        whens = join([
            "when 'x' > $(i / (n + 1)) then 'd$i' = pre('d$i') + 1.0; end when;"
                for i in 1:n
        ], "\n")
        path = regression_model(
            "Real 'x'(start = 0.0, fixed = true);\n$declarations\nequation\nder('x') = 1.0;\n$whens"
        )
        raw = parse_basemodelica(path; simplify = false)
        @test length(discrete_events(raw)) == 3
        sys = mtkcompile(raw)
        prob = ODEProblem(sys, [], (0.0, 1.0))
        @test length(prob.kwargs[:callback].discrete_callbacks) == 3
        sol = solve(prob, Tsit5())
        @test sol.retcode == ReturnCode.Success
        @test all(i -> last(sol.ps[getproperty(sys, Symbol("d$i"))]) == 1, 1:n)
    end
end

@testset "Active bodies share pre values ($parser)" for parser in (:antlr, :julia)
    @testset "State entry remembers the previous state ($via_boolean)" for via_boolean in (true, false)
        path = regression_model(
            """
                Real 'x'(start = 0.0, fixed = true);
                discrete Real 'state'(start = 1.0);
                discrete Real 'prev'(start = 0.0);
                $(via_boolean ? "Boolean 'entered';" : "")
              equation
                der('x') = 1.0;
                $(via_boolean ? "'entered' = 'state' > 1.5;" : "")
                when 'x' > 0.5 then 'state' = 2.0; end when;
                when $(via_boolean ? "'entered'" : "'state' > 1.5") then
                  'prev' = pre('state');
                end when;
            """
        )
        sys = parse_basemodelica(path; parser)
        sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        @test sol(0.4; idxs = sys.prev) == 0
        @test sol(0.6; idxs = sys.state) == 2
        @test sol(0.6; idxs = sys.prev) == 1
    end

    @testset "Acyclic counter reads the shared pre value" begin
        path = regression_model(
            """
                Real 'x'(start = 0.0, fixed = true);
                discrete Real 'n'(start = 0.0);
                discrete Real 'm'(start = 0.0);
              equation
                der('x') = 1.0;
                when 'x' > 0.5 then 'n' = pre('n') + 1.0; end when;
                when 'n' > 0.5 then 'm' = pre('n') + 10.0; end when;
            """
        )
        sys = parse_basemodelica(path; parser)
        sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        @test sol(0.6; idxs = sys.n) == 1
        @test sol(0.6; idxs = sys.m) == 10
    end

    @testset "Selected bodies re-solve current discrete dependencies" begin
        path = regression_model(
            """
                Real 'x'(start = 0.0, fixed = true);
                discrete Real 'gate'(start = 0.0);
                discrete Real 'd'(start = 0.0);
                discrete Real 'e'(start = 0.0);
              equation
                der('x') = 1.0;
                when 'x' > 0.5 then
                  'gate' = 1.0;
                  'd' = 'e' + 1.0;
                end when;
                when 'gate' > 0.5 then 'e' = 10.0; end when;
            """
        )
        sys = parse_basemodelica(path; parser)
        sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        @test sol(0.6; idxs = sys.e) == 10
        @test sol(0.6; idxs = sys.d) == 11
    end
end

@testset "Event iteration honours solution saving ($parser)" for parser in (:antlr, :julia)
    path = regression_model(
        """
            Real 'x'(start = 0.0, fixed = true);
            discrete Real 'n'(start = 0.0);
          equation
            der('x') = 1.0;
            when 'x' > 0.5 then 'n' = pre('n') + 1.0; end when;
        """
    )
    sys = parse_basemodelica(path; parser)
    for alg in (Tsit5(), Rodas5P())
        # Even when no event fires, an unconditional iteration callback used to
        # save every accepted step twice, regardless of either saving option.
        prob = ODEProblem(sys, [], (0.0, 0.4))
        grid = solve(prob, alg; saveat = 0.1, save_everystep = false)
        @test grid.retcode == ReturnCode.Success
        # Initialization may save both sides at t = 0, just like an event.
        saved_grid = unique(grid.t)
        @test length(saved_grid) == 5 && saved_grid ≈ collect(0.0:0.1:0.4)
        @test allunique(filter(t -> t > 0.0, grid.t))
        endpoints = solve(prob, alg; save_everystep = false)
        @test endpoints.retcode == ReturnCode.Success
        @test unique(endpoints.t) == [0.0, 0.4]

        # A real event may save both sides of its discontinuity, but must not
        # introduce off-grid saves or duplicates at ordinary integration steps.
        prob = ODEProblem(sys, [], (0.0, 1.0))
        grid = solve(prob, alg; saveat = 0.25, save_everystep = false)
        @test grid.retcode == ReturnCode.Success
        ordinary_times = filter(t -> t > 0.0 && !isapprox(t, 0.5; atol = 1.0e-9), grid.t)
        @test length(ordinary_times) == 3 && ordinary_times ≈ [0.25, 0.75, 1.0]
        @test allunique(ordinary_times)
        @test last(grid.ps[sys.n]) == 1
        endpoints = solve(prob, alg; save_everystep = false)
        @test endpoints.retcode == ReturnCode.Success
        @test filter(t -> t > 0.0 && !isapprox(t, 0.5; atol = 1.0e-9), endpoints.t) == [1.0]
        @test last(endpoints.ps[sys.n]) == 1
    end
end

@testset "Coincident priority restores a replaced reinit ($parser)" for parser in (:antlr, :julia)
    path = regression_model(
        """
            Real 'x'(start = 0.0, fixed = true);
            Real 'h'(start = 0.0, fixed = true);
            Real 'v'(start = 0.0, fixed = true);
          equation
            der('x') = 1.0;
            der('h') = 0.0;
            der('v') = 0.0;
            when 'x' > 0.5 then
              reinit('h', 10.0);
            elsewhen sample(0, 0.5) then
              reinit('v', pre('v') + 1.0);
            end when;
        """
    )
    sys = parse_basemodelica(path; parser)
    sol = solve(ODEProblem(sys, [], (0.0, 0.9)), Tsit5())
    @test sol.retcode == ReturnCode.Success
    @test sol(0.1; idxs = sys.v) == 1
    @test sol(0.6; idxs = sys.h) == 10
    @test sol(0.6; idxs = sys.v) == 1
end
