include("event_step_helpers.jl")

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
