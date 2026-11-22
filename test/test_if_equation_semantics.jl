using Test, BaseModelica, ModelingToolkit, OrdinaryDiffEq
using SciMLBase: remake

if_equation_fixture(name) = joinpath(@__DIR__, "if_equations", name * ".bmo")
if_equation_element(sys, name, i) = hasproperty(sys, name) ?
    getproperty(sys, name)[i] : getproperty(sys, Symbol("$name[$i]"))

function if_equation_solve(sys)
    sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5(); reltol = 1.0e-9, abstol = 1.0e-11)
    @test sol.retcode == ReturnCode.Success
    return sol
end

function if_equation_file(body)
    path = tempname() * ".bmo"
    write(path, "//! base 0.1.0\npackage P\nmodel M\n$body\nend M;\nend P;\n")
    return path
end

@testset "If-equation semantics ($parser, $arrays)" for
    parser in (:julia, :antlr), arrays in (:scalarize, :keep)
    @testset "T1 balanced initial condition remains tunable" begin
        sys = parse_basemodelica(if_equation_fixture("T1_tunable_else"); parser, arrays)
        @test ModelingToolkit.istunable(sys.p)
        prob = ODEProblem(sys, [], (0.0, 1.0))
        @test prob.ps[sys.p] == -1
        sol = solve(prob, Tsit5(); reltol = 1.0e-9, abstol = 1.0e-11)
        @test sol.retcode == ReturnCode.Success
        @test sol(0; idxs = sys.x) ≈ 2
        changed = remake(prob; p = [sys.p => 1.0])
        @test changed.ps[sys.p] == 1
        sol2 = solve(changed, Tsit5(); reltol = 1.0e-9, abstol = 1.0e-11)
        @test sol2.retcode == ReturnCode.Success
        @test sol2(0; idxs = sys.x) ≈ 1
        @test sol2(1; idxs = sys.x) ≈ exp(-1) rtol = 1.0e-7
    end

    @testset "Balanced regular condition remains tunable" begin
        path = if_equation_file(
            """
              parameter Real p = -1;
              Real x(start = 1, fixed = true);
              Real y;
            equation
              der(x) = -x;
              if p > 0 then y = x; else y = 2*x; end if;
              """
        )
        sys = parse_basemodelica(path; parser, arrays)
        prob = ODEProblem(sys, [], (0.0, 1.0))
        @test ModelingToolkit.istunable(sys.p)
        sol = solve(prob, Tsit5(); reltol = 1.0e-9, abstol = 1.0e-11)
        changed = solve(remake(prob; p = [sys.p => 1.0]), Tsit5(); reltol = 1.0e-9, abstol = 1.0e-11)
        @test sol.retcode == changed.retcode == ReturnCode.Success
        @test sol(1; idxs = sys.y) ≈ 2exp(-1) rtol = 1.0e-7
        @test changed(1; idxs = sys.y) ≈ exp(-1) rtol = 1.0e-7
    end

    @testset "Balanced residual rows preserve every constraint" begin
        path = if_equation_file(
            """
              parameter Boolean p = false;
              Real x(start = 1, fixed = true);
              Real y;
              Real z;
            equation
              der(x) = -x;
              if p then
                  0 = y - 1;
                  0 = z - 2;
              else
                  y = 3;
                  z = 4;
              end if;
              """
        )
        sys = parse_basemodelica(path; parser, arrays)
        prob = ODEProblem(sys, [], (0.0, 1.0))
        # Symbolic residuals can remain algebraic rows after MTK compilation.
        sol = solve(prob, Rodas5P(); reltol = 1.0e-9, abstol = 1.0e-11)
        changed = solve(remake(prob; p = [sys.p => true]), Rodas5P(); reltol = 1.0e-9, abstol = 1.0e-11)
        @test sol.retcode == changed.retcode == ReturnCode.Success
        @test [sol(0; idxs = sys.y), sol(0; idxs = sys.z)] ≈ [3, 4]
        @test [changed(0; idxs = sys.y), changed(0; idxs = sys.z)] ≈ [1, 2]
    end

    @testset "Residuals on distinct variables remain balanced by count ($start_time)" for start_time in (0.0, 1.0)
        path = if_equation_file(
            """
              Real x(start = 1);
              Real y(start = 2);
            initial equation
              if time > 0 then 0 = x - 3; else 0 = y - 4; end if;
            equation
              der(x) = -x;
              der(y) = -y;
              annotation(experiment(StartTime = $start_time));
              """
        )
        sys = parse_basemodelica(path; parser, arrays)
        sol = solve(ODEProblem(sys, [], (start_time, start_time + 1)), Tsit5();
            reltol = 1e-9, abstol = 1e-11)
        @test sol.retcode == ReturnCode.Success
        # The other state's unfixed start is only a guess. Check the active
        # initial constraint without asserting completion of the free coordinate.
        constrained = start_time > 0 ? sys.x : sys.y
        @test sol(start_time; idxs = constrained) ≈ (start_time > 0 ? 3 : 4)
    end

    @testset "Inactive branch equation counting is conservative" begin
        path = if_equation_file(
            """
              constant Boolean enabled = false;
              Real x(start = 1, fixed = true);
              Real y;
            equation
              der(x) = -x;
              if enabled then
                  for i in 1:missingFunction(1) loop y = i; end for;
              else
                  y = 2;
              end if;
              """
        )
        sys = parse_basemodelica(path; parser, arrays)
        sol = if_equation_solve(sys)
        @test sol(0; idxs = sys.y) ≈ 2
    end

    # OMC reference values: I5/I7/I8/I9/I18 initialize x=1; I6 initializes
    # x=2. These conditions must be evaluated by initialization, not at load.
    @testset "Balanced dynamic initial $name" for (name, expected) in (
            ("I5_discrete_cond", 1), ("I6_bool_var_cond", 2),
            ("I7_state_cond", 1), ("I8_int_discrete_cond", 1),
            ("I9_enum_var_cond", 1), ("I18_time_balanced", 1),
        )
        sys = parse_basemodelica(if_equation_fixture(name); parser, arrays)
        sol = if_equation_solve(sys)
        @test sol(0; idxs = sys.x) ≈ expected
        @test sol(1; idxs = sys.x) ≈ expected * exp(-1) rtol = 1.0e-7
    end

    @testset "L1 inactive loop branch does not index y[0]" begin
        sys = parse_basemodelica(if_equation_fixture("L1_loop_index_noelse"); parser, arrays)
        sol = if_equation_solve(sys)
        for i in 1:3, t in (0.0, 0.5, 1.0)
            @test sol(t; idxs = if_equation_element(sys, :y, i)) ≈ 2^(i - 1) * exp(-t) rtol = 1.0e-7
        end
    end

    @testset "Inactive regular constraints contribute no equations: $name" for name in (
            "L2_const_noelse", "R1_regular_two_ifs", "R2_regular_elseif_noelse",
            "R3_regular_struct", "R6_regular_residual",
        )
        sys = parse_basemodelica(if_equation_fixture(name); parser, arrays)
        sol = if_equation_solve(sys)
        @test all(t -> sol(t; idxs = sys.y) ≈ 2, (0.0, 0.5, 1.0))
        @test sol(1; idxs = sys.x) ≈ exp(-1) rtol = 1.0e-7
    end

    @testset "R4 inactive array constraints contribute no equations" begin
        sys = parse_basemodelica(if_equation_fixture("R4_regular_array"); parser, arrays)
        sol = if_equation_solve(sys)
        for i in 1:2, t in (0.0, 0.5, 1.0)
            @test sol(t; idxs = if_equation_element(sys, :y, i)) ≈ (2, 3)[i]
        end
    end

    @testset "R5 inactive derivative contributes no equation" begin
        sys = parse_basemodelica(if_equation_fixture("R5_regular_ode"); parser, arrays)
        sol = if_equation_solve(sys)
        @test [sol(t; idxs = sys.x) for t in (0.0, 0.5, 1.0)] ≈ [1, 1.5, 2]
    end

    @testset "Unbalanced dynamic $section if is rejected" for section in ("initial", "regular")
        path = if_equation_file(
            """
            Real x(start = 1, fixed = true);
            Real y(start = 2);
            $(section == "initial" ? "initial equation" : "equation")
            if time > 0 then x = 1; y = 3; else y = 2; end if;
            $(section == "initial" ? "equation" : "")
            der(x) = -x;
            der(y) = -y;
            """
        )
        @test_throws BaseModelica.UnsupportedFeatureError parse_basemodelica(path; parser, arrays)
    end

    @testset "Regular dynamic no-else if is rejected ($tail)" for tail in (
            "",
        )
        path = if_equation_file(
            """
              Real x(start = 1, fixed = true);
              Real y;
            equation
              der(x) = -x;
              if time > 0 then y = 1; $tail end if;
              """
        )
        @test_throws BaseModelica.UnsupportedFeatureError parse_basemodelica(path; parser, arrays)
    end

    @testset "Inactive elseif conditions are not evaluated structurally" begin
        path = if_equation_file(
            """
              parameter Boolean enabled = true;
              Real x(start = 1, fixed = true);
              Real y[1];
            equation
              der(x) = -x;
              if enabled then
                  y[1] = 2;
              elseif y[0] > 0 then
                  y[1] = 3;
                  x = 0;
              else
                  y[1] = 4;
              end if;
              """
        )
        sys = parse_basemodelica(path; parser, arrays)
        sol = if_equation_solve(sys)
        @test sol(0; idxs = if_equation_element(sys, :y, 1)) ≈ 2
    end

    @testset "Nested when diagnostics also cover loop bodies" begin
        path = if_equation_file(
            """
              parameter Boolean enabled = true;
              Real x(start = 0, fixed = true);
              discrete Real y(start = 0, fixed = true);
            equation
              der(x) = 1;
              if enabled then
                  for i in 1:1 loop
                      when time > 0.5 then y = 1; end when;
                  end for;
              end if;
              """
        )
        @test_throws r"when-equations in nested equation bodies" parse_basemodelica(path; parser, arrays)
    end

    @testset "First concrete true elseif terminates the branches" begin
        path = if_equation_file(
            """
              Real x(start = 1, fixed = true);
              Real y;
            equation
              der(x) = -x;
              if time < 0.5 then
                  y = x;
              elseif 2 > 1 then
                  y = 2*x;
              elseif time > 1 then
                  y = missingFunction(1);
                  y = missingFunction(2);
              else
                  y = missingFunction(3);
              end if;
              """
        )
        sys = parse_basemodelica(path; parser, arrays)
        sol = if_equation_solve(sys)
        @test sol(0.25; idxs = sys.y) ≈ exp(-0.25) rtol = 1.0e-7
        @test sol(0.75; idxs = sys.y) ≈ 2exp(-0.75) rtol = 1.0e-7
    end

    @testset "Structural selection warns once and names tunable condition parameters" begin
        # R1 has two no-else ifs depending on b: one warning for the load,
        # containing b's name, must cover both occurrences.
        @test_logs (:warn, r"(?is)(?=.*\bb\b)(?=.*(?:if-equation|if equation|branch))") min_level = Base.CoreLogging.Warn parse_basemodelica(
            if_equation_fixture("R1_regular_two_ifs"); parser, arrays, simplify = false
        )
        # A second conversion gets its own warning (no process-global suppression).
        @test_logs (:warn, r"(?is)(?=.*\bb\b)(?=.*(?:if-equation|if equation|branch))") min_level = Base.CoreLogging.Warn parse_basemodelica(
            if_equation_fixture("R1_regular_two_ifs"); parser, arrays, simplify = false
        )
        # Repeated structural initial conditions also warn only once per load.
        path = if_equation_file(
            """
              parameter Real threshold = -1;
              Real x(start = 1);
              Real y(start = 2);
            initial equation
              if threshold > 0 then x = 3; end if;
              if threshold > 0 then y = 4; end if;
            equation
              der(x) = -x;
              der(y) = -y;
              """
        )
        @test_logs (:warn, r"(?is)(?=.*\bthreshold\b)(?=.*(?:if-equation|if equation|branch))") min_level = Base.CoreLogging.Warn parse_basemodelica(
            path; parser, arrays, simplify = false
        )
        path = if_equation_file(
            """
              parameter Boolean p = q;
              parameter Boolean q = false;
              Real x(start = 1, fixed = true);
              Real y;
            equation
              der(x) = -x;
              if p then y = 1; end if;
              if not p then y = 2; end if;
              """
        )
        @test_logs (:warn, r"parameters 'p', 'q' select unbalanced if-equation") min_level = Base.CoreLogging.Warn parse_basemodelica(
            path; parser, arrays, simplify = false
        )
        # Balanced symbolic branches and constants need no structural warning.
        for name in ("T1_tunable_else", "L2_const_noelse")
            @test_logs min_level = Base.CoreLogging.Warn parse_basemodelica(
                if_equation_fixture(name); parser, arrays, simplify = false
            )
        end
    end
end
