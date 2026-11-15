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
