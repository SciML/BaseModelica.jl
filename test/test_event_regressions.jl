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
