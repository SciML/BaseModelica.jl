using Test
using BaseModelica
using ModelingToolkit
using OrdinaryDiffEq

function step_model(body)
    path = tempname() * ".bmo"
    write(
        path, """//! base 0.1.0
        package 'Step'
          model 'Step'
        $body
          end 'Step';
        end 'Step';
        """
    )
    return path
end

function step_solution(body, parser; stop = 1.0, alg = Tsit5())
    sys = parse_basemodelica(step_model(body); parser, discrete_backend = :mtk)
    sol = solve(ODEProblem(sys, [], (0.0, stop)), alg)
    @test sol.retcode == ReturnCode.Success
    return sys, sol
end

# A1-A3/B1-B2 are valid Modelica. Until the backend separates algebraic solves
# from reinit copies, reject them instead of returning the stale values from round 7.
function reject_step(body, parser, unknown; message = "plain read of non-state unknown `$unknown`")
    err = try
        parse_basemodelica(step_model(body); parser, discrete_backend = :mtk)
    catch e
        e
    end
    @test err isa BaseModelica.UnsupportedFeatureError
    @test occursin(message, sprint(showerror, err))
    return err
end

@testset "Event-step values" begin
    @testset "Current event-step unknowns ($parser)" for parser in (:julia, :antlr)
        @testset "A1: equation-defined Integer change" begin
            reject_step(
                """
                    Real 'x'(start = 0.0, fixed = true);
                    discrete Real 'c'(start = 0.0);
                    Integer 'n';
                    discrete Integer 'k'(start = 0);
                  equation
                    der('x') = 1.0;
                    'n' = if 'c' > 0.5 then 1 else 0;
                    when 'x' > 0.5 then 'c' = 1.0; end when;
                    when 'n' <> pre('n') then 'k' = 'n'; end when;
                """, parser, "n"
            )
            # §8.6 requires k(0.4, 0.9) = [0, 1]; round 7 silently returned [0, 0].
        end

        @testset "$pattern: algebraic body read" for pattern in (:A2, :A3, :A2b, :A2c, :A12)
            body = pattern === :A3 ? "'c' = 1.0; 'd' = 'y';" : "'c' = pre('c') + 1.0;"
            cascade = pattern === :A3 ? "" :
                "when $(pattern === :A2 ? "'c'" : "pre('c')") > 0.5 then 'd' = 'y'; end when;"
            dead = pattern === :A2b ? "when pre('y') > 100.0 then 'unused' = 1.0; end when;" : ""
            reject_step(
                """
                    Real 'x'(start = 0.0, fixed = true);
                    Real 'y';
                    discrete Real 'c'(start = 0.0);
                    discrete Real 'd'(start = 0.0);
                    discrete Real 'unused'(start = 0.0);
                  equation
                    der('x') = 1.0;
                    'y' = 2.0 * 'c';
                    when 'x' > 0.5 then $body end when;
                    $cascade
                    $dead
                """, parser, "y"
            )
            # §8.6 requires d(0.9) = 2 in all four cases, regardless of the dead when.
        end

        @testset "B1: alias and direct discrete reads agree" begin
            reject_step(
                """
                    Real 'x'(start = 0.0, fixed = true);
                    Real 'u';
                    discrete Real 'c'(start = 0.0);
                    discrete Real 'd'(start = 0.0);
                    discrete Real 'e'(start = 0.0);
                  equation
                    der('x') = 1.0;
                    'u' = 'c';
                    when 'x' > 0.5 then 'c' = 1.0; end when;
                    when 'c' > 0.5 then 'd' = 'c'; 'e' = 'u'; end when;
                """, parser, "u"
            )
            # §8.6 requires d = e = 1; round 7 returned d = 1, e = 0.
        end

        @testset "$pattern: two samplers on the same clock" for pattern in (:B2, :B3)
            body = """
                Real 'x'(start = 0.0, fixed = true);
                Real 'u2';
                discrete Real 'y1'(start = 0.0);
                discrete Real 'y2'(start = 0.0);
              equation
                der('x') = 1.0;
                'u2' = 'y1';
                when sample(0, 0.5) then 'y1' = 'x'; end when;
                when sample(0, 0.5) then 'y2' = $(pattern === :B2 ? "'u2'" : "'y1'"); end when;
            """
            # §8.6 requires y2(0.1, 0.6, 1.1) = [0, 0.5, 1.0] for both forms.
            # A flat connection equation must not introduce a one-tick delay.
            if pattern === :B2
                reject_step(body, parser, "u2")
            else
                sys, sol = step_solution(body, parser; stop = 1.2)
                @test [sol(t; idxs = sys.y2) for t in (0.1, 0.6, 1.1)] ≈ [0, 0.5, 1.0]
            end
        end
    end

    @testset "Reinit copies after the event-step solve ($parser)" for parser in (:julia, :antlr)
        @testset "$pattern: algebraic read before reinit copy" for pattern in (:C1, :C2)
            body = pattern === :C1 ? "'d' = 'y';" : "'c' = 1.0;"
            cascade = pattern === :C2 ? "when 'c' > 0.5 then 'd' = 'y'; end when;" : ""
            sys, sol = step_solution(
                """
                    Real 'x'(start = 0.0, fixed = true);
                    Real 'y';
                    discrete Real 'c'(start = 0.0);
                    discrete Real 'd'(start = 0.0);
                  equation
                    der('x') = 1.0;
                    'y' = 2.0 * 'x';
                    when 'x' > 0.5 then reinit('x', 0.0); $body end when;
                    $cascade
                """, parser; stop = 0.9
            )
            # §8.3.6: both bodies solve with x = 0.5, y = 1, before x := 0.
            @test sol(0.9; idxs = sys.d) ≈ 1.0 atol = 1.0e-9
            @test sol(0.9; idxs = sys.x) ≈ 0.4 atol = 1.0e-9
        end

        @testset "C3: bouncing ball records incoming speed" begin
            sys, sol = step_solution(
                """
                    Real 'h'(start = 1.0, fixed = true);
                    Real 'v'(start = 0.0, fixed = true);
                    Real 'speed';
                    discrete Real 'impact'(start = 0.0);
                  equation
                    der('h') = 'v';
                    der('v') = -9.81;
                    'speed' = abs('v');
                    when 'h' < 0.0 then
                      reinit('v', -0.8 * pre('v'));
                      'impact' = 'speed';
                    end when;
                """, parser; stop = 0.6
            )
            @test sol(0.6; idxs = sys.impact) ≈ sqrt(2 * 9.81) atol = 1.0e-8
            @test sol(0.6; idxs = sys.v) > 0
        end

        @testset "$pattern: state reads in later iterations" for pattern in (:E1, :E2, :E3)
            condition = pattern === :E2 ? "'c'" : "pre('c')"
            dead = pattern === :E3 ? "when pre('x') > 100.0 then 'unused' = 1.0; end when;" : ""
            sys, sol = step_solution(
                """
                    Real 'x'(start = 0.0, fixed = true);
                    discrete Real 'c'(start = 0.0);
                    discrete Real 'd'(start = -1.0);
                    discrete Real 'unused'(start = 0.0);
                  equation
                    der('x') = 1.0;
                    when 'x' > 0.5 then reinit('x', 0.0); 'c' = pre('c') + 1.0; end when;
                    when $condition > 0.5 then 'd' = 'x'; end when;
                    $dead
                """, parser; stop = 0.9
            )
            # E2 cascades within step 1. E1/E3 activate in step 2, after the copy.
            @test sol(0.9; idxs = sys.d) ≈ (pattern === :E2 ? 0.5 : 0.0) atol = 1.0e-9
        end
    end

    @testset "Original guarded change condition in diagnostics ($parser)" for parser in (:julia, :antlr)
        path = step_model(
            """
                Real 'x'(start = 0.0, fixed = true);
                Integer 'n';
                discrete Integer 'k'(start = 0);
              equation
                der('x') = 1.0;
                'n' = if 'x' > 0.5 then 1 else 0;
                when 'n' <> pre('n') and 'n' > 0 then 'k' = 'n'; end when;
            """
        )
        err = try
            parse_basemodelica(path; parser)
        catch e
            e
        end
        @test err isa BaseModelica.UnsupportedFeatureError
        @test occursin("compound when-condition", sprint(showerror, err))
        @test occursin("Pre(n(t))", sprint(showerror, err))
    end

    @testset "Non-state body-read guard boundaries ($parser)" for parser in (:julia, :antlr)
        @testset "Transitive/reversed and implicit equations ($implicit, $reinit)" for implicit in (false, true), reinit in (false, true)
            equations = implicit ? "0.0 = 'y'^3 + 'y' - 2.0 * 'c';" : "'c' = 'u'; 'u' = 'y';"
            body = reinit ? "reinit('x', 'y');" : "'d' = 'y';"
            reject_step(
                """
                    Real 'x'(start = 0.0, fixed = true);
                    Real 'u'; Real 'y'(start = 0.0);
                    discrete Real 'c'(start = 0.0); discrete Real 'd'(start = 0.0);
                  equation
                    der('x') = 1.0;
                    $(implicit ? "'u' = 0.0;" : "")
                    $equations
                    when 'x' > 0.5 then 'c' = 1.0; $body end when;
                """, parser, "y"
            )
            # The implicit equation has y = 1 after c = 1; the aliases give y = 1.
            # The reinit RHS must use that same new value, not the old y = 0.
        end
        @testset "Derivative dependency does not hide a discrete coupling" begin
            reject_step(
                """
                    Real 'x'(start = 0.0, fixed = true); Real 'y';
                    discrete Real 'c'(start = 1.0); discrete Real 'd'(start = 0.0);
                  equation
                    der('x') = 'c'; 'y' = der('x');
                    when 'x' > 0.5 then 'c' = 2.0; 'd' = 'y'; end when;
                """, parser, "y"
            )
            # The state remains fixed, but its derivative and hence y must become 2.
        end
        @testset "Equation-defined Boolean dependency" begin
            reject_step(
                """
                    Real 'x'(start = 0.0, fixed = true); Real 'y'; Boolean 'on';
                    discrete Real 'c'(start = 0.0); discrete Real 'd'(start = 0.0);
                  equation
                    der('x') = 1.0; 'on' = 'c' > 0.5;
                    'y' = if 'on' then 2.0 else 0.0;
                    when 'x' > 0.5 then 'c' = 1.0; 'd' = 'y'; end when;
                """, parser, "y"
            )
            # §8.6 requires d = 2, including through the relation Boolean.
        end
        @testset "State equations stop algebraic dependency propagation" begin
            sys, sol = step_solution(
                """
                    Real 'x'(start = 0.0, fixed = true); Real 'y';
                    discrete Real 'c'(start = 0.0); discrete Real 'd'(start = 0.0);
                  equation
                    der('x') = 1.0 + 'c'; 'y' = 2.0 * 'x';
                    when 'x' > 0.5 then 'c' = 1.0; 'd' = 'y'; end when;
                """, parser
            )
            @test sol(0.9; idxs = sys.d) ≈ 1.0 atol = 1.0e-9
            @test sol(0.9; idxs = sys.x) ≈ 1.3 atol = 1.0e-7
        end
        @testset "Body-only continuous algebraic snapshots advance after reinit" begin
            sys, sol = step_solution(
                """
                    Real 'x'(start = 0.0, fixed = true); Real 'y';
                    discrete Real 'c'(start = 0.0); discrete Real 'd'(start = -1.0);
                  equation
                    der('x') = 1.0; 'y' = 2.0 * 'x';
                    when 'x' > 0.5 then reinit('x', 0.0); 'c' = 1.0; end when;
                    when pre('c') > 0.5 then 'd' = 'y'; end when;
                """, parser; stop = 0.9
            )
            @test sol(0.9; idxs = sys.d) ≈ 0.0 atol = 1.0e-9
        end
        @testset "Explicit pre remains a previous-step read" begin
            sys, sol = step_solution(
                """
                    Real 'x'(start = 0.0, fixed = true); Real 'y';
                    discrete Real 'c'(start = 0.0); discrete Real 'e'(start = -1.0);
                    discrete Real 'd'(start = -1.0);
                  equation
                    der('x') = 1.0; 'y' = 2.0 * 'c';
                    when 'x' > 0.5 then 'c' = 1.0; 'e' = pre('y'); end when;
                    when pre('c') > 0.5 then 'd' = pre('y'); end when;
                """, parser
            )
            @test sol(0.9; idxs = sys.e) == 0
            @test sol(0.9; idxs = sys.d) == 2
        end
    end

end

@testset "Round 9 guard regressions ($parser)" for parser in (:julia, :antlr)
    @testset "S1/S1b: direct derivative reads ($reinit)" for reinit in (false, true)
        # §8.6 requires d = 2 (or z := 2), not the old derivative 1.
        body = reinit ? "reinit('z', der('x'));" : "'d' = der('x');"
        err = try
            parse_basemodelica(
                step_model(
                    """
                        Real 'x'(start = 0.0, fixed = true);
                        Real 'z'(start = 0.0, fixed = true);
                        discrete Real 'c'(start = 1.0); discrete Real 'd'(start = 0.0);
                      equation
                        der('x') = 'c'; der('z') = 0.0;
                        when 'x' > 0.5 then 'c' = 2.0; $body end when;
                    """
                ); parser
            )
        catch e
            e
        end
        @test err isa BaseModelica.UnsupportedFeatureError
        @test occursin("plain derivative read", sprint(showerror, err))
        @test occursin("event-step solve", sprint(showerror, err))
    end

    @testset "R1: coincident priority after snapshot advancement" begin
        # At 0.6 Modelica requires h=10, v=1, c=1, d=-1. Advancing
        # snapshots loses the sample branch's restore values and its cascades.
        err = try
            parse_basemodelica(
                step_model(
                    """
                        Real 'x'(start = 0.0, fixed = true);
                        Real 'h'(start = 0.0, fixed = true);
                        Real 'v'(start = 0.0, fixed = true);
                        discrete Real 'c'(start = 0.0); discrete Real 'd'(start = -1.0);
                      equation
                        der('x') = 1.0; der('h') = 0.0; der('v') = 0.0;
                        when 'x' > 0.5 then reinit('h', 10.0);
                        elsewhen sample(0, 0.5) then
                          reinit('v', pre('v') + 1.0); 'c' = pre('c') + 1.0;
                        end when;
                        when pre('c') > 1.5 then 'd' = time; end when;
                    """
                ); parser
            )
        catch e
            e
        end
        @test err isa BaseModelica.UnsupportedFeatureError
        @test occursin("coincident priority restoration after snapshot advancement", sprint(showerror, err))
    end

    @testset "G4: continuous signal with downstream discrete error ($reverse)" for reverse in (false, true)
        equation = reverse ? "2.0 * 'x' = 'y';" : "'y' = 2.0 * 'x';"
        sys, sol = step_solution(
            """
                Real 'x'(start = 0.0, fixed = true); Real 'y'; Real 'e';
                discrete Real 'r'(start = 0.0); discrete Real 'd'(start = -1.0);
              equation
                der('x') = 1.0; $equation 'e' = 'r' - 'y';
                when 'x' > 0.5 then 'r' = 2.0; 'd' = 'y'; end when;
            """, parser; stop = 0.9
        )
        @test sol(0.9; idxs = sys.d) ≈ 1.0 atol = 1.0e-9
    end

    @testset "G5b: sampler with continuous measurement and discrete setpoint" begin
        sys, sol = step_solution(
            """
                Real 'x'(start = 0.0, fixed = true); Real 'ymeas'; Real 'e';
                discrete Real 'r_d'(start = 0.0); discrete Real 'ys'(start = -1.0);
              equation
                der('x') = 'e'; 'ymeas' = 'x'; 'e' = 'r_d' - 'ymeas';
                when sample(0, 0.3) then 'ys' = 'ymeas'; 'r_d' = 1.0; end when;
            """, parser; stop = 1.0
        )
        # x(t) = 1-exp(-t); the last sample before 1.0 is at 0.9.
        @test sol(1.0; idxs = sys.ys) ≈ 1 - exp(-0.9) atol = 1.0e-5
    end

    @testset "G1/G6: relations on continuous states remain conservative" begin
        err = reject_step(
            """
                Real 'h'(start = 1.0, fixed = true); Real 'v'(start = 0.0, fixed = true);
                Real 'speed'; discrete Real 'd'(start = 0.0);
              equation
                der('h') = 'v'; der('v') = -9.81;
                'speed' = if 'v' < 0.0 then -'v' else 'v';
                when 'h' < 0.0 then reinit('v', -0.8 * pre('v')); 'd' = 'speed'; end when;
            """, parser, "speed"
        ) # Modelica d = sqrt(2*9.81).
        @test occursin("event-generating relations/functions", sprint(showerror, err))
        @test !occursin("involve discrete-time quantities", sprint(showerror, err))
        reject_step(
            """
                Real 'x'(start = 0.0, fixed = true); Real 'sat'; Real 'y';
                discrete Real 'd'(start = 0.0);
              equation
                der('x') = 1.0; 'sat' = if 'x' > 2.0 then 2.0 else 'x'; 'y' = 3.0 * 'sat';
                when 'x' > 0.5 then 'd' = 'y'; end when;
            """, parser, "y"
        ) # Modelica d = 1.5.
        # Removing *all* state-only relations would silently return d=0 here,
        # since LeftRootFind may stop just below x=0.5. Modelica requires d=1.
        reject_step(
            """
                Real 'x'(start = 0.0, fixed = true); Real 'y'; discrete Real 'd'(start = -1.0);
              equation
                der('x') = 1.0; 'y' = if 'x' > 0.5 then 1.0 else 0.0;
                when 'x' > 0.5 then 'd' = 'y'; end when;
            """, parser, "y"
        )
    end

    @testset "S3: event-generating functions on Real targets ($expression)" for expression in
        (
            "floor(2.0 * 'x')", "ceil(2.0 * 'x')", "integer(2.0 * 'x')",
            "div(2.0 * 'x', 1.0)", "mod(2.0 * 'x', 1.0)", "rem(2.0 * 'x', 1.0)",
        )
        # At the event floor/integer/div are 1; ceil is 1; mod/rem are 0.
        # The backend does not generate the functions' discontinuity events.
        message = startswith(expression, "div(") ? "div() with symbolic arguments" :
            "plain read of non-state unknown `y`"
        reject_step(
            """
                Real 'x'(start = 0.0, fixed = true); Real 'y'; discrete Real 'd'(start = -1.0);
              equation
                der('x') = 1.0; 'y' = $expression;
                when 'x' > 0.5 then 'd' = 'y'; end when;
            """, parser, "y"; message
        )
    end

    @testset "Constant div remains supported" begin
        sys, sol = step_solution(
            """
                Real 'x'(start = 0.0, fixed = true); Real 'y'; discrete Real 'd'(start = 0.0);
              equation
                der('x') = 1.0; 'y' = div(-5.5, 2.0);
                when 'x' > 0.5 then 'd' = 'y'; end when;
            """, parser; stop = 0.9
        )
        @test sol(0.9; idxs = sys.d) == -2.0
    end

    @testset "R4: reinit of one state in separate when-equations" begin
        err = try
            parse_basemodelica(
                step_model(
                    """
                        Real 'x'(start = 0.0, fixed = true); discrete Real 'c'(start = 0.0);
                      equation
                        der('x') = 1.0;
                        when 'x' > 0.5 then reinit('x', 0.0); 'c' = 1.0; end when;
                        when 'c' > 0.5 then reinit('x', 'x' + 10.0); end when;
                    """
                ); parser
            )
        catch e
            e
        end
        @test err isa BaseModelica.UnsupportedFeatureError
        @test occursin("reinit of `x` in multiple when-equations", sprint(showerror, err))
        # §8.3.6 permits this only within the same when/elsewhen chain.
        sys, sol = step_solution(
            """
                Real 'x'(start = 0.0, fixed = true);
              equation
                der('x') = 1.0;
                when 'x' > 0.5 then reinit('x', 0.0);
                elsewhen 'x' > 0.75 then reinit('x', 10.0); end when;
            """, parser; stop = 0.9
        )
        @test sol(0.9; idxs = sys.x) ≈ 0.4 atol = 1.0e-9
    end
end

@testset "Adjacent whole-step probes ($parser)" for parser in (:julia, :antlr)
    @testset "R2: bouncing ball with a pre(counter) threshold" begin
        ball = """
            Real 'h'(start = 1.0, fixed = true); Real 'v'(start = 0.0, fixed = true);
            discrete Integer 'n'(start = 0); discrete Real 'd'(start = -1.0);
          equation
            der('h') = 'v'; der('v') = -9.81;
            when 'h' < 0.0 then reinit('v', -0.8 * pre('v')); 'n' = pre('n') + 1; end when;
        """
        sys, sol = step_solution(ball * "when pre('n') >= 2 then 'd' = 'v'; end when;", parser; stop = 1.3)
        ctl, control = step_solution(ball, parser; stop = 1.3)
        @test sol(1.3; idxs = sys.d) ≈ 0.8^2 * sqrt(2 * 9.81) atol = 1.0e-8
        @test sol(1.3; idxs = sys.n) == 2
        for time in (0.4, 0.6, 1.0, 1.3), (var, ref) in ((sys.h, ctl.h), (sys.v, ctl.v))
            @test sol(time; idxs = var) ≈ control(time; idxs = ref) atol = 1.0e-8
        end
    end
    @testset "R5: later reinit reads the copied state" begin
        sys, sol = step_solution(
            """
                Real 'x'(start = 0.0, fixed = true); Real 'z'(start = 0.0, fixed = true);
                discrete Real 'c'(start = 0.0);
              equation
                der('x') = 1.0; der('z') = 0.0;
                when 'x' > 0.5 then reinit('x', 0.0); 'c' = 1.0; end when;
                when pre('c') > 0.5 then reinit('z', 'x' + 5.0); end when;
            """, parser; stop = 0.9
        )
        @test sol(0.9; idxs = sys.z) ≈ 5.0 atol = 1.0e-9
    end
    @testset "R6: sample counter, reinit and pre threshold" begin
        sys, sol = step_solution(
            """
                Real 'x'(start = 0.0, fixed = true);
                discrete Integer 'k'(start = 0); discrete Real 'd'(start = -1.0);
              equation
                der('x') = 1.0;
                when sample(0, 0.5) then 'k' = pre('k') + 1; reinit('x', 0.0); end when;
                when pre('k') >= 3 then 'd' = 100.0 * pre('k') + 'x'; end when;
            """, parser; stop = 2.2
        )
        @test [sol(t; idxs = sys.k) for t in (0.1, 1.1, 2.2)] == [1, 3, 5]
        @test [sol(t; idxs = sys.x) for t in (0.1, 1.1, 2.2)] ≈ [0.1, 0.1, 0.2] atol = 1.0e-9
        @test sol(2.2; idxs = sys.d) ≈ 300.0 atol = 1.0e-9
    end
    @testset "R7: reinit and pre counters in both steps" begin
        sys, sol = step_solution(
            """
                Real 'x'(start = 0.0, fixed = true);
                discrete Integer 'c'(start = 0); discrete Integer 'k'(start = 0);
                discrete Real 'd'(start = -1.0);
              equation
                der('x') = 1.0;
                when 'x' > 0.5 then reinit('x', 0.0); 'c' = pre('c') + 1; end when;
                when pre('c') > 0 then 'k' = pre('k') + 1; 'd' = 'x'; end when;
            """, parser; stop = 0.9
        )
        @test sol(0.9; idxs = sys.c) == 1
        @test sol(0.9; idxs = sys.k) == 1
        @test sol(0.9; idxs = sys.d) ≈ 0.0 atol = 1.0e-9
    end
end

@testset "Adjacent algebraic guard probes ($parser)" for parser in (:julia, :antlr)
    @testset "G2/G2b: time does not connect independent equations ($relation)" for relation in (false, true)
        sys, sol = step_solution(
            """
                Real 'x'(start = 0.0, fixed = true); Real 'y'; Real 'unrelated';
                discrete Real 'd'(start = -1.0);
              equation
                der('x') = 1.0; 'y' = 2.0 * time;
                'unrelated' = $(relation ? "if time > 0.25 then 1.0 else 0.0" : "3.0 * time");
                when 'x' > 0.5 then 'd' = 'y'; end when;
            """, parser; stop = 0.9
        )
        @test sol(0.9; idxs = sys.d) ≈ 1.0 atol = 1.0e-9
    end
    @testset "G5: state separates a signal from discrete dynamics" begin
        sys, sol = step_solution(
            """
                Real 'x'(start = 0.0, fixed = true); Real 'ymeas'; Real 'e';
                discrete Real 'r_d'(start = 1.0); discrete Real 'ys'(start = -1.0);
              equation
                der('x') = 'r_d'; 'ymeas' = 2.0 * 'x'; 'e' = 'r_d' - 'ymeas';
                when time > 0.25 then 'r_d' = 2.0; end when;
                when time > 0.5 then 'ys' = 'ymeas'; end when;
            """, parser; stop = 0.7
        )
        @test sol(0.7; idxs = sys.ys) ≈ 1.5 atol = 1.0e-8
    end
    @testset "S1c: cascaded derivative reads get the same diagnostic" begin
        err = try
            parse_basemodelica(
                step_model(
                    """
                        Real 'x'(start = 0.0, fixed = true);
                        discrete Real 'c'(start = 1.0); discrete Real 'd'(start = 0.0);
                      equation
                        der('x') = 'c';
                        when 'x' > 0.5 then 'c' = 2.0; end when;
                        when 'c' > 1.5 then 'd' = der('x'); end when;
                    """
                ); parser
            )
        catch e
            e
        end
        @test err isa BaseModelica.UnsupportedFeatureError
        @test occursin("plain derivative read", sprint(showerror, err))
    end
    @testset "S8/N1: Integer target ($name)" for name in ("n", "ctl.n")
        reject_step(
            """
                Real 'x'(start = 0.0, fixed = true); Integer '$name'; discrete Real 'd'(start = -1.0);
              equation
                der('x') = 1.0; '$name' = integer(2.0 * 'x');
                when 'x' > 0.5 then 'd' = '$name'; end when;
            """, parser, name
        )
    end
    @testset "S6: array algebraic read" begin
        reject_step(
            """
                Real 'x'(start = 0.0, fixed = true); Real 'y'[2];
                discrete Real 'c'(start = 0.0); discrete Real 'd'(start = -1.0);
              equation
                der('x') = 1.0; 'y' = {'c', 2.0 * 'c'};
                when 'x' > 0.5 then 'c' = 1.0; 'd' = 'y'[2]; end when;
            """, parser, "y[2]"
        )
    end
end
