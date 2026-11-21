using Test
using BaseModelica
using ModelingToolkit
using OrdinaryDiffEq

BM = BaseModelica

testfile(name) = joinpath(dirname(dirname(pathof(BM))), "test", "testfiles", name * ".bmo")

function write_model(body)
    path = tempname() * ".bmo"
    write(
        path, """//! base 0.1.0
        package 'M'
          model 'M'
        $body
          end 'M';
        end 'M';
        """
    )
    return path
end

@testset "When-equations and events" begin
    @testset "Bouncing ball: reinit bounces ($parser)" for parser in (:julia, :antlr)
        prob = create_odeproblem(testfile("BouncingBall"); parser, discrete_backend = :mtk)
        sys = prob.f.sys
        @test length(ModelingToolkit.continuous_events(sys)) == 1
        sol = solve(prob, Tsit5())
        @test sol.retcode == ReturnCode.Success
        h = sol[sys.h]
        v = sol[sys.v]
        # The ball never falls through the floor ...
        @test minimum(h) > -1.0e-6
        # ... and its velocity flips from downwards to upwards at every bounce
        @test count(i -> v[i] < 0 && v[i + 1] > 0, 1:(length(v) - 1)) >= 3
        # First impact at t1 = sqrt(2 h0 / g); the rebound speed is e * g * t1
        t1 = sqrt(2 * 1.0 / 9.81)
        @test sol(t1 + 1.0e-3; idxs = sys.v) ≈ 0.8 * 9.81 * t1 - 9.81e-3 atol = 1.0e-3
        @test sol(t1 + 1.0e-3; idxs = sys.h) > 0
    end

    @testset "Discrete assignment with pre ($parser)" for parser in (:julia, :antlr)
        prob = create_odeproblem(testfile("DiscreteCounter"); parser, discrete_backend = :mtk)
        sys = prob.f.sys
        sol = solve(prob, Tsit5())
        @test sol.retcode == ReturnCode.Success
        n = sol.ps[sys.n]
        @test first(n) == 0.0
        @test last(n) == 1.0
        # The update of n must not disturb the continuous state x, which is coupled to
        # n through the algebraic equation y = 2x + n
        @test sol(1.0; idxs = sys.x) ≈ 1.0 atol = 1.0e-8
        @test sol(1.0; idxs = sys.y) ≈ 3.0 atol = 1.0e-8
        @test sol(0.25; idxs = sys.y) ≈ 0.5 atol = 1.0e-8
    end

    @testset "elsewhen branches ($parser)" for parser in (:julia, :antlr)
        package = parser == :julia ? BM.parse_file_julia(testfile("WhenElsewhen")) :
            BM.parse_file_antlr(testfile("WhenElsewhen"))
        when_eq = only(
            filter(!isnothing, BM.as_when_equation.(package.model.long_class_specifier.composition.equations))
        )
        @test length(when_eq.whens) == 2
        @test length(when_eq.thens) == 2

        prob = create_odeproblem(testfile("WhenElsewhen"); parser, discrete_backend = :mtk)
        sys = prob.f.sys
        sol = solve(prob, Tsit5())
        @test sol.retcode == ReturnCode.Success
        @test last(sol.ps[sys.a]) == 1.0
        @test last(sol.ps[sys.b]) == 2.0
    end

    @testset "Discrete start value from initial equation" begin
        path = write_model(
            """
                Real 'x'(fixed = true, start = 0.0);
                discrete Real 'd';
              initial equation
                pre('d') = 5.0;
              equation
                der('x') = 1.0;
                when 'x' > 0.5 then
                  'd' = pre('d') + 1.0;
                end when;
            """
        )
        sys = parse_basemodelica(path; discrete_backend = :mtk)
        sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5())
        @test first(sol.ps[sys.d]) == 5.0
        @test last(sol.ps[sys.d]) == 6.0
    end

    @testset "Discrete start value from initial algorithm ($parser)" for parser in (:julia, :antlr)
        path = write_model(
            """
                Real 'x'(fixed = true, start = 0.0);
                discrete Real 'd';
                discrete Real 'e';
              equation
                der('x') = 1.0;
                when 'x' > 0.5 then
                  'd' = pre('d') + 1.0;
                  'e' = pre('e') * 2.0;
                end when;
              initial algorithm
                'd' := integer((time + 2.5) / 1.0);
                'e' := 'd' + 1.0;
            """
        )
        sys = parse_basemodelica(path; parser, discrete_backend = :mtk)
        sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5())
        @test first(sol.ps[sys.d]) == 2.0
        @test first(sol.ps[sys.e]) == 3.0
        @test last(sol.ps[sys.d]) == 3.0
        @test last(sol.ps[sys.e]) == 6.0
    end

    @testset "assert in an initial algorithm ($parser)" for parser in (:julia, :antlr)
        failure(f) =
            try
                f()
                ""
            catch e
                sprint(showerror, e)
            end
        sys = parse_basemodelica(testfile("InitialAssert"); parser)
        prob = ODEProblem(sys, [], (0.0, 1.0))
        # All assertions hold: no warning, and the assignment between them still applies
        sol = @test_logs solve(prob, Tsit5())
        @test sol.retcode == ReturnCode.Success
        @test first(sol.ps[sys.counter]) == 1.0
        # They are checked at initialization with the current parameters and state
        @test_logs (:warn, r"width must be smaller than period") solve(
            remake(prob; p = [sys.period => 0.1]), Tsit5()
        )
        @test occursin(
            "period must be positive",
            failure(() -> solve(remake(prob; p = [sys.period => -1.0]), Tsit5()))
        )
        @test occursin(
            "x and counter must be positive",
            failure(() -> solve(remake(prob; u0 = [sys.x => -1.0]), Tsit5()))
        )
        # An assertion that fails whatever the parameters is rejected at translation
        path = write_model(
            """
                Real 'x'(fixed = true, start = 0.0);
              initial algorithm
                assert(1.0 > 2.0, "never holds");
              equation
                der('x') = 1.0;
            """
        )
        @test occursin("never holds", failure(() -> parse_basemodelica(path; parser)))
    end

    @testset "Booleans defined by relations ($parser)" for parser in (:julia, :antlr)
        # Every Boolean has a start value that contradicts its definition at t = 0, which
        # used to be kept: the solve succeeded with the wrong branch selected throughout.
        prob = create_odeproblem(testfile("RelationBoolean"); parser)
        sys = prob.f.sys
        sol = solve(prob, Rodas5P())
        @test sol.retcode == ReturnCode.Success
        at(time, var) = sol(time; idxs = var)
        # Consistent at initialization: x(0) = 1 so `off` is false and y = 2
        @test at(0.0, sys.y) == 2.0
        @test sol[sys.y][1] == 2.0
        # ... also when the relation depends on an unknown that depends on the Boolean
        # (ideal diode: s(0) = -0.5 so it blocks, i = 0.1 s)
        @test at(0.0, sys.i) ≈ -0.05
        # ... and with pre(): the hysteresis starts on since x(0) < 1.5
        @test at(0.0, sys.heating) == 1.0
        # Crossings switch the Booleans, including relations of time alone
        @test at(0.6, sys.i) ≈ 1.0                                  # diode conducts at t = 0.5
        @test at(1.1, sys.late) == 0.0
        @test at(1.3, sys.late) == 1.0                              # time >= 1.2
        @test at(1.3, sys.lateCopy) == 1.0                          # `late = lateCopy`
        @test at(1.4, sys.heating) == 1.0
        @test at(1.6, sys.heating) == 0.0                           # x crosses 2.5
        # Event iteration after a jump: reinit(x, -1) at t = 2 crosses no zero
        @test at(1.9, sys.y) == 2.0
        @test at(2.1, sys.y) == 1.0
        @test at(2.1, sys.heating) == 1.0
        @test at(2.1, sys.i) ≈ 0.1 * ((-1.0 + 0.1) - 1.5)          # x(2.1) = -0.9
        # Changing the initial state re-solves the Booleans
        sol2 = solve(remake(prob; u0 = [sys.x => -1.0]), Rodas5P())
        @test sol2(0.0; idxs = sys.y) == 1.0
    end

    @testset "Time events reach the solver as tstops ($parser)" for parser in (:julia, :antlr)
        # if-conditions comparing time with parameters or numbers, without events
        prob = create_odeproblem(testfile("TimeEvents"); parser)
        sys = prob.f.sys
        @test prob.kwargs[:tstops](prob.p, prob.tspan) == [0.3, 0.7, 0.9, 5.0]
        sol = solve(prob, Tsit5())
        @test sol.retcode == ReturnCode.Success
        @test all(ts -> any(≈(ts), sol.t), (0.3, 0.7, 0.9))
        # x(1) = 1 * (0.7 - 0.3) + 2 * (1 - 0.7) + 1 * (1 - 0.9)
        @test sol[sys.x][end] ≈ 1.1 rtol = 1.0e-4
        # The tstops are on the system, so a problem built without create_odeproblem gets
        # them too, and they follow the parameters
        prob2 = ODEProblem(parse_basemodelica(testfile("TimeEvents"); parser), [], (0.0, 1.0))
        prob2 = remake(prob2; p = [prob2.f.sys.startTime => 0.5])
        @test prob2.kwargs[:tstops](prob2.p, prob2.tspan) == [0.5, 0.9, 5.0]
        # Explicit tstops replace the model's
        @test create_odeproblem(testfile("TimeEvents"); parser, tstops = [0.25]).kwargs[:tstops] == [0.25]
    end

    @testset "Models without differential states ($parser)" for parser in (:julia, :antlr)
        # A single step could span the whole simulation and miss most of the 50 rising
        # edges of y > 0.5; create_odeproblem bounds the step by the output interval
        prob = create_odeproblem(testfile("NoStates"); parser)
        sys = prob.f.sys
        @test isempty(unknowns(sys))
        @test prob.kwargs[:dtmax] == 0.05
        @test prob.kwargs[:saveat] == 0.05
        sol = solve(prob, Tsit5())
        @test sol.retcode == ReturnCode.Success
        @test sol.ps[sys.n][end] == 50
        # y peaks at 0.005 + k/50 and has its minimum at 0.015 + k/50
        @test all(k -> sol(0.005 + k / 50; idxs = sys.high) == 1.0, 0:49)
        @test all(k -> sol(0.015 + k / 50; idxs = sys.high) == 0.0, 0:49)
        @test sol(0.123; idxs = sys.y) ≈ sin(2pi * 50 * 0.123) atol = 1.0e-10
        # An explicit dtmax takes precedence
        @test create_odeproblem(testfile("NoStates"); parser, dtmax = 0.01).kwargs[:dtmax] == 0.01
        # A lone continuous event on a system without states (ModelingToolkit used to
        # evaluate its condition into the empty state buffer: BoundsError)
        path = write_model(
            """
                Real 'y';
                discrete Real 'n'(start = 0.0);
              equation
                'y' = sin(2.0 * 3.141592653589793 * time);
                when 'y' > 0.5 then
                  'n' = pre('n') + 1.0;
                end when;
            """
        )
        prob = create_odeproblem(path; parser)
        sol = solve(prob, Tsit5())
        @test sol.retcode == ReturnCode.Success
        @test sol.ps[prob.f.sys.n][end] == 1.0
    end

    @testset "Unsupported constructs throw" begin
        reinit_outside = write_model(
            """
                Real 'x'(fixed = true, start = 1.0);
              equation
                der('x') = -'x';
                reinit('x', 0.0);
            """
        )
        @test_throws BM.UnsupportedFeatureError parse_basemodelica(reinit_outside)

        compound_condition = write_model(
            """
                Real 'x'(fixed = true, start = 0.0);
                discrete Real 'd';
              equation
                der('x') = 1.0;
                when 'x' > 0.5 and 'x' < 2.0 then
                  'd' = 1.0;
                end when;
            """
        )
        @test_throws BM.UnsupportedFeatureError parse_basemodelica(compound_condition; discrete_backend = :mtk)

        unknown_function = write_model(
            """
                Real 'x'(fixed = true, start = 0.0);
              equation
                der('x') = 'notAFunction'('x');
            """
        )
        @test_throws BM.UnsupportedFeatureError parse_basemodelica(unknown_function)
    end

    @testset "Unsimplified systems and experiment metadata" begin
        raw = parse_basemodelica(testfile("BouncingBall"); simplify = false)
        @test raw isa System
        @test !ModelingToolkit.iscomplete(raw)
        @test experiment_settings(raw) == (StartTime = 0.0, StopTime = 3.0, Tolerance = 1.0e-6, Interval = 0.01)

        compiled = mtkcompile(raw)
        @test experiment_settings(compiled) == experiment_settings(raw)
        sol = solve(ODEProblem(compiled, [], (0.0, 3.0)), Tsit5())
        @test minimum(sol[compiled.h]) > -1.0e-6

        custom = parse_basemodelica(testfile("BouncingBall"); simplify = mtkcompile)
        @test ModelingToolkit.iscomplete(custom)
        @test isnothing(experiment_settings(parse_basemodelica(testfile("NewtonCoolingBase"))))

        @test_throws ArgumentError create_odeproblem(testfile("BouncingBall"); simplify = false)
        @test_throws ArgumentError parse_basemodelica(testfile("BouncingBall"); discrete_backend = :bogus)
    end
end
