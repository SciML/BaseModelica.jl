include("event_step_helpers.jl")

# Keep parser-sensitive guards on both parsers. Selection-only cases use the
# full Julia matrix and a small ANTLR subset; selection itself is shared.

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
        @test occursin("plain derivative read `der('x')`", sprint(showerror, err))
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

@testset "Round 10 guard regressions ($parser)" for parser in (:julia, :antlr)
    @testset "P3/P3c: sample priority with a non-sample sibling ($discrete, $advance)" for discrete in (false, true), advance in (false, true)
        declaration = discrete ? "discrete Real 'c'(start = 0.0);" : "Boolean 'b';"
        equation = discrete ? "when 'x' > 0.5 then 'c' = 1.0; end when;" : "'b' = 'x' > 0.5;"
        condition = discrete ? "'c' > 0.5" : "'b'"
        body = """
            Real 'x'(start = 0.0, fixed = true);
            Real 'h'(start = 0.0, fixed = true);
            Real 'v'(start = 0.0, fixed = true);
            discrete Real 'k'(start = 0.0); discrete Real 'd'(start = -1.0);
            $declaration
          equation
            der('x') = 1.0; der('h') = 0.0; der('v') = 0.0;
            $equation
            when $condition then reinit('h', 10.0);
            elsewhen sample(0, 0.5) then
              reinit('v', pre('v') + 1.0); 'k' = pre('k') + 1.0;
            end when;
            $(advance ? "when pre('k') > 1.5 then 'd' = time; end when;" : "")
        """
        # P3/P3c require h=10, v=k=1, d=-1 at 0.6. Previously v=k=2,
        # d=0.5 when snapshot advancement discarded the priority restore values.
        if advance
            err = reject_step(body, parser, ""; message = "multi-branch when/elsewhen chain with a non-sample branch")
            @test occursin("coincident priority restoration after snapshot advancement", sprint(showerror, err))
        else
            # P3ctl/P3cctl: without pre() in a condition, restoration works.
            sys, sol = step_solution(body, parser; stop = 0.6)
            @test sol(0.6; idxs = sys.h) ≈ 10.0
            @test sol(0.6; idxs = sys.v) ≈ 1.0
            @test sol(0.6; idxs = sys.k) == 1.0
            @test sol(0.6; idxs = sys.d) == -1.0
        end
    end

    @testset "P3d: two non-sample siblings ($reverse, $advance)" for reverse in (false, true), advance in (false, true)
        definitions = ["'b1' = 'x' > 0.5;", "'b2' = 2.0 * 'x' > 1.0;"]
        reverse && reverse!(definitions)
        sys, sol = step_solution(
            """
                Real 'x'(start = 0.0, fixed = true);
                Real 'h'(start = 0.0, fixed = true);
                Real 'v'(start = 0.0, fixed = true);
                Boolean 'b1'; Boolean 'b2';
                discrete Real 'k'(start = 0.0); discrete Real 'd'(start = -1.0);
              equation
                der('x') = 1.0; der('h') = 0.0; der('v') = 0.0;
                $(join(definitions, "\n"))
                when 'b1' then reinit('h', 10.0);
                elsewhen 'b2' then reinit('v', pre('v') + 1.0); 'k' = pre('k') + 1.0;
                end when;
                $(advance ? "when pre('k') > 0.5 then 'd' = time; end when;" : "")
            """, parser; stop = 0.6
        )
        @test sol(0.6; idxs = sys.h) ≈ 10.0
        @test sol(0.6; idxs = sys.v) == 0.0
        @test sol(0.6; idxs = sys.k) == 0.0
        @test sol(0.6; idxs = sys.d) == -1.0
    end

    @testset "P1/P1v/P1ctl: sign-derived event-step values ($variant)" for variant in (:P1, :P1v, :P1ctl)
        start = variant === :P1v ? -1.0 : 0.0
        argument = variant === :P1v ? "'x'" : "'x' - 0.5"
        condition = variant === :P1v ? "'x' > 0.0" : "'x' > 0.5"
        expression = variant === :P1ctl ? "if $argument > 0.0 then 1.0 else if $argument < 0.0 then -1.0 else 0.0" : "sign($argument)"
        reject_step(
            """
                Real 'x'(start = $start, fixed = true); Real 'y';
                discrete Real 'd'(start = -2.0);
              equation
                der('x') = 1.0; 'y' = $expression;
                when $condition then 'd' = 'y'; end when;
            """, parser, "y"
        )
        # §3.7.1: sign is event-free (noEvent expansion). At a coincident root
        # its value is numerically ill-defined; without an algebraic event-step
        # solve, reject conservatively rather than asserting a left/right value.
    end
end

@testset "Round 11 guard regressions ($parser)" for parser in (:julia, :antlr)
    @testset "Q1: sample in a separate when ($upper, $lower, $advance)" for upper in (:root, :bool), lower in (:disc, :bool), advance in (false, true)
        udecl = upper === :bool ? "Boolean 'r';" : ""
        ueq = upper === :bool ? "'r' = 'x' > 0.5;" : ""
        ucond = upper === :bool ? "'r'" : "'x' > 0.5"
        ldecl = lower === :bool ? "Boolean 'b';" : ""
        leq = lower === :bool ? "'b' = 'c' > 1.5;" : ""
        lcond = lower === :bool ? "'b'" : "'c' > 1.5"
        body = """
            Real 'x'(start = 0.0, fixed = true);
            Real 'h'(start = 0.0, fixed = true); Real 'v'(start = 0.0, fixed = true);
            discrete Real 'c'(start = 0.0); discrete Real 'k'(start = 0.0);
            discrete Real 'd'(start = -1.0);
            $udecl $ldecl
          equation
            der('x') = 1.0; der('h') = 0.0; der('v') = 0.0;
            $ueq $leq
            when sample(0, 0.5) then 'c' = pre('c') + 1.0; end when;
            when $ucond then reinit('h', 10.0);
            elsewhen $lcond then reinit('v', pre('v') + 1.0); 'k' = pre('k') + 1.0;
            end when;
            $(advance ? "when pre('k') > 0.5 then 'd' = time; end when;" : "")
        """
        if advance
            # The sample cascade can select the lower branch before the root.
            # Advancing pre then loses the values needed to undo that branch.
            reject_step(body, parser, ""; message = "sample() anywhere and pre() in when-conditions")
        else
            sys, sol = step_solution(body, parser; stop = 0.6)
            @test sol(0.6; idxs = sys.h) ≈ 10.0
            @test sol(0.6; idxs = sys.v) == 0.0
            @test sol(0.6; idxs = sys.k) == 0.0
            @test sol(0.6; idxs = sys.d) == -1.0
        end
    end

    @testset "Q2: sample-free coincident roots ($upper, $lower, $advance)" for (upper, lower) in
            (("time > 0.5", "'x' > 0.5"), ("'x' * 'x' > 0.25", "'x' > 0.5"), ("'x' > 0.5", "time > 0.5")), advance in (false, true)
        parser === :antlr && (upper != "time > 0.5" || advance) && continue
        sys, sol = step_solution(
            """
                Real 'x'(start = 0.0, fixed = true);
                Real 'h'(start = 0.0, fixed = true); Real 'v'(start = 0.0, fixed = true);
                discrete Real 'k'(start = 0.0); discrete Real 'd'(start = -1.0);
              equation
                der('x') = 1.0; der('h') = 0.0; der('v') = 0.0;
                when $upper then reinit('h', 10.0);
                elsewhen $lower then reinit('v', pre('v') + 1.0); 'k' = pre('k') + 1.0;
                end when;
                $(advance ? "when pre('k') > 0.5 then 'd' = time; end when;" : "")
            """, parser; stop = 0.6
        )
        @test sol(0.6; idxs = sys.h) ≈ 10.0
        @test sol(0.6; idxs = sys.v) == 0.0
        @test sol(0.6; idxs = sys.k) == 0.0
        @test sol(0.6; idxs = sys.d) == -1.0
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
        @test occursin("plain derivative read `der('x')`", sprint(showerror, err))
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

@testset "Round 12 coincident roots and equation pre ($parser)" for parser in (:julia, :antlr)
    @testset "M1: coincident roots ($variant, $clock)" for variant in (:unit, :steep, :late), clock in (false, true)
        parser === :antlr && (variant !== :unit || !clock) && continue
        slope, start, event, stop = variant === :late ? (1.0, -1000.0, 1000.5, 1001.0) :
            variant === :steep ? (1000.0, -499.5, 0.5, 0.6) : (1.0, 0.0, 0.5, 0.6)
        sys, sol = step_solution(
            """
                Real 'x'(start = $start, fixed = true);
                discrete Real 'c'(start = 0.0); discrete Real 'd'(start = -1.0);
              equation
                der('x') = $slope;
                $(clock ? "when time > $event then 'c' = pre('c') + 1.0; end when;" : "")
                when 'x' > 0.5 then 'd' = time; end when;
            """, parser; stop
        )
        @test sol(stop; idxs = sys.d) ≈ event atol = 1.0e-9 rtol = 0
        clock && @test sol(stop; idxs = sys.c) == 1.0
    end

    @testset "M1 control: nearby distinct roots ($late)" for late in (false, true)
        parser === :antlr && late && continue
        slope, clock, stop = late ? (1.0, 1000.5, 1001.0) : (1000.0, 0.5, 0.6)
        event = clock + 1.0e-6
        sys, sol = step_solution(
            """
                Real 'x'(start = $(0.5 - slope * event), fixed = true);
                discrete Real 'c'(start = 0.0); discrete Real 'd'(start = -1.0);
              equation
                der('x') = $slope;
                when time > $clock then 'c' = 1.0; end when;
                when 'x' > 0.5 then 'd' = time; end when;
            """, parser; stop
        )
        @test sol(clock + 0.5e-6; idxs = sys.d) == -1.0
        @test sol(stop; idxs = sys.d) ≈ event atol = 1.0e-9 rtol = 0
    end

    @testset "M2: coincident reinit is saved at stop time" begin
        sys, sol = step_solution(
            """
                Real 'x'(start = -499.5, fixed = true);
                Real 'y'(start = 0.0, fixed = true);
                discrete Real 'c'(start = 0.0);
              equation
                der('x') = 1000.0; der('y') = 1.0;
                when time > 0.5 then 'c' = pre('c') + 1.0; end when;
                when 'x' > 0.5 then reinit('y', 0.0); end when;
            """, parser; stop = 0.6
        )
        @test sol(0.6; idxs = sys.y) ≈ 0.1 atol = 1.0e-9
        @test sol[sys.y][end] ≈ 0.1 atol = 1.0e-9
        @test sol(0.6; idxs = sys.c) == 1.0
    end

    @testset "Ra/Ra': root priority ($slope, $advance, $boolean, $reverse)" for slope in (1.0, 1000.0, 0.001), advance in (false, true), boolean in (false, true), reverse in (false, true)
        parser === :antlr && (slope != 1.0 || advance || reverse) && continue
        high = reverse ? "time > 0.5" : "'x' > 0.5"
        trigger = reverse ? "'x' > 0.5" : "time > 0.5"
        lower = boolean ? "'b'" : "'c' > 1.5"
        sys, sol = step_solution(
            """
                Real 'x'(start = $(0.5 - slope * 0.5), fixed = true);
                Real 'h'(start = 0.0, fixed = true); Real 'v'(start = 0.0, fixed = true);
                discrete Real 'c'(start = 0.0); discrete Real 'k'(start = 0.0);
                discrete Real 'd'(start = -1.0);
                $(boolean ? "Boolean 'b';" : "")
              equation
                der('x') = $slope; der('h') = 0.0; der('v') = 0.0;
                $(boolean ? "'b' = 'c' > 1.5;" : "")
                when $trigger then 'c' = 2.0; end when;
                when $high then reinit('h', 10.0);
                elsewhen $lower then reinit('v', pre('v') + 1.0); 'k' = pre('k') + 1.0;
                end when;
                $(advance ? "when pre('k') > 0.5 then 'd' = time; end when;" : "")
            """, parser; stop = 0.6
        )
        @test sol(0.6; idxs = sys.h) ≈ 10.0
        @test sol(0.6; idxs = sys.v) == 0.0
        @test sol(0.6; idxs = sys.k) == 0.0
        @test sol(0.6; idxs = sys.d) == -1.0
    end

    @testset "$case: cross-variable pre in ordinary equations" for case in (:E1, :E5, :Rb, :real, :boolean_read)
        definition = case === :E1 ? "Boolean 'b'; Boolean 'e';" :
            case === :E5 ? "Boolean 'b'; Boolean 'e';" :
            case === :Rb ? "Boolean 'b';" :
            case === :boolean_read ? "Boolean 'b'; Real 'y';" : "Real 'y';"
        equations = case === :E1 ? "'b' = 'x' > 0.5; 'e' = 'b' and not pre('b');" :
            case === :E5 ? "'b' = 'k' > 0.5; 'e' = 'b' and not pre('b');" :
            case === :Rb ? "'b' = pre('k') > 0.5;" :
            case === :boolean_read ? "'b' = 'x' > 0.5; 'y' = if pre('b') then 1.0 else 0.0;" : "'y' = pre('k');"
        consumer = case in (:E1, :E5) ? "when 'e' then 'd' = time; end when;" :
            case === :Rb ? "when 'b' then 'd' = pre('k'); end when;" : ""
        # E1/E5 require d=0.5/0.25; Rb requires d=1 in the second iteration.
        # Reject these until ordinary equations share the when pre-value machinery.
        reject_step(
            """
                Real 'x'(start = 0.0, fixed = true);
                discrete Real 'k'(start = 0.0); discrete Real 'd'(start = -1.0);
                $definition
              equation
                der('x') = 1.0;
                $equations
                when 'x' > 0.25 then 'k' = pre('k') + 1.0; end when;
                $consumer
            """, parser, ""; message = "pre() in ordinary equations is only supported for a Boolean's self-reference"
        )
    end

    @testset "Rb controls: direct pre condition and plain Boolean ($direct)" for direct in (false, true)
        sys, sol = step_solution(
            """
                Real 'x'(start = 0.0, fixed = true);
                discrete Real 'k'(start = 0.0); discrete Real 'm'(start = -1.0);
                $(direct ? "" : "Boolean 'b';")
              equation
                der('x') = 1.0;
                $(direct ? "" : "'b' = 'k' > 0.5;")
                when 'x' > 0.25 then 'k' = pre('k') + 1.0; end when;
                when $(direct ? "pre('k') > 0.5" : "'b'") then 'm' = pre('k'); end when;
            """, parser; stop = 0.6
        )
        @test sol(0.6; idxs = sys.m) == (direct ? 1.0 : 0.0)
    end
end

@testset "Round 13 interpolant roots ($parser)" for parser in (:julia,)
    @testset "N1: oscillator near an unrelated time root ($alg)" for alg in (Tsit5(), nothing)
        sys, sol = step_solution(
            """
                Real 'y'(start = 0.0, fixed = true); Real 'v'(start = 10.0, fixed = true);
                discrete Real 'n'(start = 0.0); discrete Real 'd'(start = -1.0);
                discrete Real 'a'(start = 0.0);
              equation
                der('y') = 'v'; der('v') = -100.0 * 'y';
                when time > 0.21 then 'a' = pre('a') + 1.0; end when;
                when 'y' > 0.863209317 then 'n' = pre('n') + 1.0; 'd' = time; end when;
            """, parser; stop = 0.4, alg
        )
        @test sol(0.4; idxs = sys.n) == 1.0
        @test sol(0.4; idxs = sys.d) ≈ asin(0.863209317) / 10 atol = 2.0e-4
        @test sol(0.4; idxs = sys.a) == 1.0
    end

    @testset "N1: oscillator threshold offsets ($clock, $offset)" for clock in (0.1, 0.14, 0.18, 0.21), offset in (-3.0e-5, -1.0e-6, -1.0e-8, 1.0e-8, 1.0e-6, 3.0e-5)
        threshold = sin(10clock) + offset
        sys, sol = step_solution(
            """
                Real 'y'(start = 0.0, fixed = true); Real 'v'(start = 10.0, fixed = true);
                discrete Real 'n'(start = 0.0); discrete Real 'd'(start = -1.0);
                discrete Real 'a'(start = 0.0);
              equation
                der('y') = 'v'; der('v') = -100.0 * 'y';
                when time > $clock then 'a' = pre('a') + 1.0; end when;
                when 'y' > $threshold then 'n' = pre('n') + 1.0; 'd' = time; end when;
            """, parser; stop = 0.4
        )
        @test sol(0.4; idxs = sys.n) == 1.0
        @test sol(0.4; idxs = sys.d) ≈ asin(threshold) / 10 atol = 2.0e-4
    end

    @testset "Coincident nonlinear roots precede a lower-priority cascade ($reverse)" for reverse in (false, true)
        high, trigger = reverse ? ("'x'^2 > 0.25", "'x' > 0.5") : ("'x' > 0.5", "'x'^2 > 0.25")
        sys, sol = step_solution(
            """
                Real 'x'(start = 0.0, fixed = true); Real 'z'(start = 0.0, fixed = true);
                discrete Real 'c'(start = 0.0); discrete Real 'n'(start = 0.0);
              equation
                der('x') = 1.0 - 'x'^3; der('z') = 0.0;
                when $trigger then 'c' = 2.0; end when;
                when $high then reinit('z', 10.0);
                elsewhen 'c' > 1.5 then 'n' = pre('n') + 1.0;
                end when;
            """, parser; stop = 0.8
        )
        @test sol(0.8; idxs = sys.c) == 2.0
        @test sol(0.8; idxs = sys.z) == 10.0
        @test sol(0.8; idxs = sys.n) == 0.0
    end
end

@testset "Round 14 single firing at coincident roots ($parser)" for parser in (:julia,)
    # Count both clauses: saving a timestamp or reinitializing to the same value
    # can hide a second firing. Rodas5P used to double-fire M1-unit and M2;
    # Vern9 and FBDF also exposed the pending-root/interpolant problem.
    @testset "M1: $variant ($(nameof(typeof(alg))))" for alg in (Rodas5P(), Vern9(), FBDF()),
            variant in (:unit, :slow)

        slope = variant === :unit ? 1.0 : 0.001
        sys, sol = step_solution(
            """
                Real 'x'(start = $(0.5 - 0.5slope), fixed = true);
                discrete Real 'c'(start = 0.0); discrete Real 'k'(start = 0.0);
              equation
                der('x') = $slope;
                when time > 0.5 then 'c' = pre('c') + 1.0; end when;
                when 'x' > 0.5 then 'k' = pre('k') + 1.0; end when;
            """, parser; stop = 0.6, alg
        )
        @test sol(0.6; idxs = sys.c) == 1.0
        @test sol(0.6; idxs = sys.k) == 1.0
    end

    @testset "M2: coincident reinit ($(nameof(typeof(alg))))" for alg in (Rodas5P(), Vern9(), FBDF())
        sys, sol = step_solution(
            """
                Real 'x'(start = -499.5, fixed = true);
                Real 'y'(start = 0.0, fixed = true);
                discrete Real 'c'(start = 0.0); discrete Real 'k'(start = 0.0);
              equation
                der('x') = 1000.0; der('y') = 1.0;
                when time > 0.5 then 'c' = pre('c') + 1.0; end when;
                when 'x' > 0.5 then reinit('y', 0.0); 'k' = pre('k') + 1.0; end when;
            """, parser; stop = 0.6, alg
        )
        @test sol(0.6; idxs = sys.c) == 1.0
        @test sol(0.6; idxs = sys.k) == 1.0
        # FBDF can locate the root less accurately than the event-time window.
        # Counts must be exact; the saved state follows the solver tolerance.
        @test sol[sys.y][end] ≈ 0.1 rtol = 1.0e-3
    end

    @testset "An exact-zero later root preserves its rising direction" begin
        # Vern9 can duplicate either root independently, depending on code
        # generation. Check positive edges here; the deterministic history
        # regression below guards against an extra edge from BaseModelica.
        sys, sol = step_solution(
            """
                Real 'x'(start = 0.0, fixed = true);
                discrete Real 'c'(start = 0.0); discrete Real 'k'(start = 0.0);
              equation
                der('x') = 1.0 - 'x'^3;
                when 'x' > 0.5 then 'c' = pre('c') + 1.0; end when;
                when 'x'^2 > 0.25 then 'k' = pre('k') + 1.0; end when;
            """, parser; stop = 0.8, alg = Vern9()
        )
        @test sol(0.8; idxs = sys.c) >= 1.0
        @test sol(0.8; idxs = sys.k) >= 1.0
    end

    @testset "Exact-zero root history does not invent an edge" begin
        t = ModelingToolkit.t_nounits
        D = Differential(t)
        @variables x(t)
        sys = mtkcompile(System([D(x) ~ 1.0 - x^3], t; name = :ExactZeroHistory))
        x = sys.x
        integ = init(ODEProblem(sys, [x => 0.5], (0.0, 1.0)), Vern9())
        body = Pair{Any, Any}[]
        blocks = [
            BaseModelica.WhenBlock(x > 0.5, x - 0.5, nothing, body, body),
            BaseModelica.WhenBlock(x^2 > 0.25, x^2 - 0.25, nothing, body, body),
        ]
        # x^2's rising root was already handled at a prior solver root report.
        history = (
            previous_x = 0.0, previous_square = 1.0, active_x = 0.0, active_square = 1.0,
            root_time = -1.0e-12, sample_time = -Inf, event_time = -1.0e-12, ready = 0.0,
            execute_x = 0.0, execute_square = 0.0, tolerance_x = 1.0e-9, tolerance_square = 1.0e-9,
        )
        at_root = (time = 0.0, condition1 = false, condition2 = false, crossing1 = 0.0, crossing2 = 0.0)
        selected = BaseModelica.WhenSelection(blocks, 1, 1, 0)(history, at_root, nothing, integ)
        @test selected.previous_square == 1.0
        # A later accepted step must not see a new false-to-true edge for x^2.
        after_root = (time = 0.1, condition1 = true, condition2 = true, crossing1 = 0.1, crossing2 = 0.11)
        stepped = BaseModelica.WhenSelection(blocks, 0, 0, 0)(selected, after_root, nothing, integ)
        @test stepped.active_square == 0.0
    end
end

@testset "Round 15 rate-scaled root history ($parser)" for parser in (:julia,)
    @testset "50 Hz mains at $start ($(nameof(typeof(alg))))" for start in (100.0, 1000.0),
            alg in (Tsit5(), Rodas5P())

        w = 2pi * 50
        # Start at the negative peak so neither endpoint is a rising root.
        sys, sol = step_solution(
            """
                Real 'v'(start = -325.0, fixed = true);
                Real 'i'(start = 0.0, fixed = true);
                discrete Real 'k'(start = 0.0);
              equation
                der('v') = 'i'; der('i') = -$(w^2) * 'v';
                when 'v' > 0.0 then 'k' = pre('k') + 1.0; end when;
            """, parser; start, stop = start + 1, alg
        )
        @test sol(start + 1; idxs = sys.k) == 50.0
    end

    @testset "50 Hz threshold after one day ($(nameof(typeof(alg))))" for alg in (Tsit5(), Rodas5P())
        w = 2pi * 50
        sys, sol = step_solution(
            """
                Real 'y'(start = 0.0, fixed = true);
                Real 'v'(start = $(10w), fixed = true);
                discrete Real 'k'(start = 0.0);
              equation
                der('y') = 'v'; der('v') = -$(w^2) * 'y';
                when 'y' > 5.0 then 'k' = pre('k') + 1.0; end when;
            """, parser; start = 86400.0, stop = 86401.0, alg
        )
        @test sol(86401.0; idxs = sys.k) == 50.0
    end

    @testset "Late ramp and relation-Boolean control ($boolean)" for boolean in (false, true)
        sys, sol = step_solution(
            """
                Real 'x'(start = 0.0, fixed = true);
                discrete Real 'k'(start = 0.0);
                $(boolean ? "Boolean 'b';" : "")
              equation
                der('x') = 1000.0;
                $(boolean ? "'b' = 'x' > 0.5;" : "")
                when $(boolean ? "'b'" : "'x' > 0.5") then 'k' = pre('k') + 1.0; end when;
            """, parser; start = 1.0e4, stop = 1.0e4 + 0.001
        )
        @test sol(1.0e4 + 0.001; idxs = sys.k) == 1.0
    end

    @testset "Reinit still enables another block at a root" begin
        sys, sol = step_solution(
            """
                Real 'x'(start = 0.0, fixed = true);
                Real 'z'(start = -1.0, fixed = true);
                discrete Real 'c'(start = 0.0); discrete Real 'k'(start = 0.0);
              equation
                der('x') = 1000.0; der('z') = 0.0;
                when 'x' > 0.5 then reinit('z', 1.0); 'c' = pre('c') + 1.0; end when;
                when 'z' > 0.0 then 'k' = pre('k') + 1.0; end when;
            """, parser; start = 1.0e4, stop = 1.0e4 + 0.001
        )
        @test sol(1.0e4 + 0.001; idxs = sys.c) == 1.0
        @test sol(1.0e4 + 0.001; idxs = sys.k) == 1.0
    end
end

@testset "Round 16 local tangent estimates ($parser)" for parser in (:julia,)
    @testset "Domain boundary before reinit ($event, $(nameof(typeof(alg))))" for
        event in (0.999999995, 1.0 - 5.0e-13), alg in (Tsit5(), nothing, Rodas5P())

        # The tangent can leave sqrt's domain before the time root's reinit.
        # The second event is close enough to exercise the finite fallback even
        # with the shorter tangent step. A NaN tolerance loses/delays this edge.
        sys, sol = step_solution(
            """
                Real 'x'(start = 1.0, fixed = true);
                discrete Real 'c'(start = 0.0); discrete Real 'k'(start = 0.0);
                discrete Real 'tb'(start = -1.0);
              equation
                der('x') = if 'c' > 0.5 then -1000.0 else -1.0;
                when time > $event then reinit('x', 0.0026); 'c' = pre('c') + 1.0; end when;
                when sqrt('x') > 0.05 then 'k' = pre('k') + 1.0; 'tb' = time; end when;
            """, parser; stop = 1.000001, alg
        )
        @test sol(1.000001; idxs = sys.c) == 1.0
        @test sol(1.000001; idxs = sys.k) == 1.0
        @test sol(1.000001; idxs = sys.tb) ≈ event atol = 32eps(Float64) rtol = 0
    end

    @testset "$frequency Hz sine at $start ($angle, $(nameof(typeof(alg))))" for
        (frequency, start, duration) in ((50, 6.7e5, 1.0), (50, 2.0e6, 1.0), (1000, 33554.0, 0.1)),
            angle in (false, true), alg in (Tsit5(), Rodas5P())

        w = 2pi * frequency
        # At these starts sqrt(eps)*t spans nearly an integer multiple of pi,
        # making a long forward difference underestimate the crossing rate.
        # State angles also exercise non-finite interpolant derivatives after roots.
        sys = parse_basemodelica(
            step_model(
                """
                    Real 'phi'(start = -1.0, fixed = true);
                    discrete Real 'k'(start = 0.0);
                  equation
                    der('phi') = $w;
                    when sin($(angle ? "'phi'" : "$w * (time - $start) - 1.0")) > 0.0 then
                      'k' = pre('k') + 1.0;
                    end when;
                """
            ); parser, discrete_backend = :mtk
        )
        stop = start + duration
        prob = ODEProblem(sys, [], (start, stop))
        # Resolve every half-cycle, including the time-explicit detector whose
        # otherwise trivial ODE would allow arbitrarily large solver steps.
        sol = solve(prob, alg; dtmax = 1 / (20frequency))
        @test sol.retcode == ReturnCode.Success
        @test sol(stop; idxs = sys.k) == frequency * duration
    end
end

@testset "Round 17 diagonal-mass root tangents ($parser)" for parser in (:julia,)
    @testset "$(coupled ? "p2: coupled" : "p3: unrelated") loop ($(nameof(typeof(alg))))" for coupled in (false, true),
            alg in (Rodas5P(), FBDF(), nothing)

        # Both an unrelated algebraic loop (p3) and one coupled to the phase
        # (p2) retain an algebraic unknown. At late times aligned root/step
        # boundaries can leave a zero-length interpolant with NaN derivatives.
        start = 1.0e5
        sys = parse_basemodelica(
            step_model(
                """
                    Real 'phi'(start = -1.0, fixed = true);
                    discrete Real 'k'(start = 0.0);
                    Real 'q'(start = 0.0, fixed = true); Real 'y'(start = 0.0);
                  equation
                    der('phi') = $(2pi * 50);
                    der('q') = -'q' + 'y';
                    'y'^3 + 'y' = $(coupled ? "'phi'" : "1.0");
                    when sin('phi') > 0.0 then 'k' = pre('k') + 1.0; end when;
                """
            ); parser, discrete_backend = :mtk
        )
        prob = ODEProblem(sys, [], (start, start + 1))
        @test !isone(prob.f.mass_matrix)
        sol = isnothing(alg) ? solve(prob; dtmax = 1.0e-3) :
            solve(prob, alg; dtmax = 1.0e-3)
        @test sol.retcode == ReturnCode.Success
        @test sol(start + 1; idxs = sys.k) == 50.0
    end
end

# Event selection is parser-independent. Keep a small ANTLR solve matrix here;
# guard/translation regressions above and the algebraic-crossing tests below
# retain both parsers.
@testset "ANTLR event-selection smoke" begin
    @testset "Coincident roots and reinit" begin
        sys, sol = step_solution(
            """
                Real 'x'(start = -499.5, fixed = true);
                Real 'z'(start = -1.0, fixed = true);
                discrete Real 'c'(start = 0.0); discrete Real 'k'(start = 0.0);
              equation
                der('x') = 1000.0; der('z') = 0.0;
                when time > 0.5 then 'c' = pre('c') + 1.0; end when;
                when 'x' > 0.5 then reinit('z', 1.0); end when;
                when 'z' > 0.0 then 'k' = pre('k') + 1.0; end when;
            """, :antlr; stop = 0.6, alg = Rodas5P()
        )
        @test sol(0.6; idxs = sys.c) == 1.0
        @test sol(0.6; idxs = sys.k) == 1.0
    end
end

@testset "Round 18 retained algebraic crossings ($parser)" for parser in (:julia, :antlr)
    @testset "Custom compilation and manual compilation are checked" begin
        path = step_model(
            """
                Real 'phi'(start = -1.0, fixed = true);
                discrete Real 'k'(start = 0.0); Real 'y'(start = 0.0);
              equation
                der('phi') = $(2pi); 'y'^3 + 'y' = sin('phi');
                when 'y' > 0.0 then 'k' = pre('k') + 1.0; end when;
            """
        )
        @test_throws BaseModelica.UnsupportedFeatureError parse_basemodelica(path; parser, simplify = mtkcompile)
        raw = parse_basemodelica(path; parser, simplify = false)
        @test raw isa System
        compiled = mtkcompile(raw)
        @test_throws BaseModelica.UnsupportedFeatureError BaseModelica.check_algebraic_crossings(compiled)
    end

    @testset "1 Hz $variant crossing" for variant in (:direct, :threshold, :alias)
        # Without the guard these default-tolerance 10-second solves return
        # k > 10 with Rodas5P, FBDF and the default solver, instead of 10.
        # Check at compilation: changing solvers cannot make this lowering safe.
        reject_step(
            """
                Real 'phi'(start = -1.0, fixed = true);
                discrete Real 'k'(start = 0.0); Real 'y'(start = 0.0);
                $(variant === :alias ? "Real 'z'; Real 'alias';" : "")
              equation
                der('phi') = $(2pi); 'y'^3 + 'y' = sin('phi');
                $(variant === :alias ? "'z' = 2 * 'y'; 'alias' = 'z';" : "")
                when $(variant === :alias ? "'alias'" : "'y'") > $(variant === :threshold ? 0.3 : 0.0) then
                  'k' = pre('k') + 1.0;
                end when;
            """, parser, ""; message = "crossing depends on retained algebraic unknown"
        )
    end

    @testset "Equation-defined Boolean crossing" begin
        reject_step(
            """
                Real 'phi'(start = -1.0, fixed = true);
                discrete Real 'k'(start = 0.0); Real 'y'(start = 0.0); Boolean 'b';
              equation
                der('phi') = $(2pi); 'y'^3 + 'y' = sin('phi');
                'b' = 'y' > 0.0;
                when 'b' then 'k' = pre('k') + 1.0; end when;
            """, parser, ""; message = "crossing depends on retained algebraic unknown"
        )
    end

    @testset "Eliminated explicit signal remains supported ($(nameof(typeof(alg))))" for alg in (Rodas5P(), FBDF(), nothing)
        sys = parse_basemodelica(
            step_model(
                """
                    Real 'phi'(start = -1.0, fixed = true);
                    discrete Real 'k'(start = 0.0); Real 'y';
                  equation
                    der('phi') = $(2pi); 'y' = sin('phi');
                    when 'y' > 0.0 then 'k' = pre('k') + 1.0; end when;
                """
            ); parser
        )
        prob = ODEProblem(sys, [], (0.0, 10.0))
        @test isone(prob.f.mass_matrix)
        sol = isnothing(alg) ? solve(prob; dtmax = 0.05) : solve(prob, alg; dtmax = 0.05)
        @test sol.retcode == ReturnCode.Success
        @test sol(10.0; idxs = sys.k) == 10.0
    end
end
