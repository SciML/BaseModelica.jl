using Test, BaseModelica, ModelingToolkit, OrdinaryDiffEq

function initial_if_file(body; classes = "")
    path = tempname() * ".bmo"
    write(path, "//! base 0.1.0\npackage P\n$classes\nmodel M\n" * body * "\nend M;\nend P;\n")
    return path
end

function initial_if_solve(body; parser, arrays, classes = "")
    sys = parse_basemodelica(initial_if_file(body; classes); parser, arrays)
    sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5(); reltol = 1e-9, abstol = 1e-11)
    @test sol.retcode == ReturnCode.Success
    return sys, sol
end

initial_if_element(sys, i) = hasproperty(sys, :x) ? sys.x[i] :
    getproperty(sys, Symbol("x[$i]"))

@testset "Structural initial if ($parser, $arrays)" for
        parser in (:julia, :antlr), arrays in (:scalarize, :keep)
    # Re-review P1 and its zero-derivative / Boolean variants.
    for (declaration, condition) in (
            ("parameter Real p = -1;", "p > 0"),
            ("parameter Boolean b = false;", "b"),
            ("parameter Real p = q; parameter Real q = -1;", "p > 0"),
        ), rhs in ("-x", "0")
        body = """
            $declaration
            Real x(start = 3);
          initial equation
            if $condition then x = 1; end if;
          equation
            der(x) = $rhs;
            """
        if rhs == "0"
            # With no initial equations der(x)=0 has underdetermined initialization
            # in MTK. Check the emitted system rather than adding a constraint.
            raw = parse_basemodelica(initial_if_file(body); parser, arrays, simplify = false)
            @test isempty(initialization_equations(raw))
            @test !BaseModelica.ModelingToolkitBase.hasdefault(raw.x)
            @test BaseModelica.ModelingToolkitBase.getguess(raw.x) == 3
        else
            sys, sol = initial_if_solve(body; parser, arrays)
            @test sol(0; idxs = sys.x) ≈ 3
            @test sol(1; idxs = sys.x) ≈ 3exp(-1) rtol = 1e-7
        end
    end

    # Array repro: dropping the branch must preserve every start value.
    body = """
        parameter Real p = -1;
        Real x[2](each start = 3);
      initial equation
        if p > 0 then x = {1, 2}; end if;
      equation
        der(x) = {0, 0};
        """
    raw = parse_basemodelica(initial_if_file(body); parser, arrays, simplify = false)
    @test isempty(initialization_equations(raw))
    for i in 1:2
        var = initial_if_element(raw, i)
        @test !BaseModelica.ModelingToolkitBase.hasdefault(var)
        @test BaseModelica.ModelingToolkitBase.getguess(var) == 3
    end
    # Fix the array starts to make the numerical check fully determined.
    sys, sol = initial_if_solve(replace(body, "each start = 3" => "each start = 3, each fixed = true"); parser, arrays)
    for i in 1:2
        @test sol(0; idxs = initial_if_element(sys, i)) ≈ 3
    end

    for (condition, tail, expected) in (("p > 0", "", 1), ("p < 0", "else x = 4;", 4))
        sys, sol = initial_if_solve("""
            parameter Real p = 1;
            Real x(start = 3);
          initial equation
            if $condition then x = 1; $tail end if;
          equation
            der(x) = -x;
            """; parser, arrays)
        @test sol(0; idxs = sys.x) ≈ expected
    end

    # A discarded initial constraint must not replace a discrete Boolean's start.
    sys, sol = initial_if_solve("""
        parameter Boolean enabled = false;
        Real x(start = 0, fixed = true);
        discrete Boolean b(start = true);
      initial equation
        if enabled then pre(b) = false; end if;
      equation
        der(x) = 1;
        when time > 0.5 then b = false; end when;
        """; parser, arrays)
    @test sol(0; idxs = sys.b) == true
    @test sol(1; idxs = sys.b) == false

    # MSL Init.NoInit/SteadyState/InitialState: distinct targets in each branch.
    for enum in (false, true), choice in 1:3
        classes = enum ? "type Init = enumeration(NoInit, SteadyState, InitialState);" : ""
        declaration = enum ?
            "parameter Init initType = Init.$(("NoInit", "SteadyState", "InitialState")[choice]);" :
            "parameter Integer initType = $choice;"
        c2, c3 = enum ? ("Init.SteadyState", "Init.InitialState") : ("2", "3")
        sys, sol = initial_if_solve("""
            $declaration
            Real y(start = 2);
          initial equation
            if initType == $c2 then
              der(y) = 0;
            elseif initType == $c3 then
              y = 5;
            end if;
          equation
            der(y) = 1 - y;
            """; parser, arrays, classes)
        @test sol(0; idxs = sys.y) ≈ (2, 1, 5)[choice]
    end

    # Selected branches alone are evaluated, including nested ifs and loops.
    sys, sol = initial_if_solve("""
        parameter Boolean b = true;
        Real x[2];
        Real y(start = 0);
      initial equation
        if b then
          for i in 1:2 loop
            if i > 1 then x[i] = 4; else x[i] = 2; end if;
          end for;
        else
          y = missingFunction(1);
        end if;
      equation
        der(x) = -x;
        der(y) = -y;
        """; parser, arrays)
    for i in 1:2
        var = initial_if_element(sys, i)
        @test sol(0; idxs = var) ≈ 2i
    end

    # Balanced explicit else branches retain their dynamic condition.
    sys, sol = initial_if_solve("""
        Real x(start = 3);
      initial equation
        if time > 0 then x = 1; else x = 2; end if;
      equation
        der(x) = -x;
        """; parser, arrays)
    @test sol(0; idxs = sys.x) ≈ 2

    # An explicit else is required for symbolic lowering. A terminal true
    # elseif still has an implicit empty else branch.
    for tail in ("", "elseif true then x = 2;")
        path = initial_if_file("""
            Real x(start = 3);
          initial equation
            if time > 0 then x = 1; $tail end if;
          equation
            der(x) = -x;
            """)
        @test_throws r"initial if-equation condition must be evaluable at load time" parse_basemodelica(path; parser, arrays)
    end
    # fixed=false parameters are initialization unknowns, not load-time values.
    path = initial_if_file("""
        parameter Real p(fixed = false, start = -1);
        Real x(start = 3);
      initial equation
        p = -1;
        if p > 0 then x = 1; end if;
      equation
        der(x) = -x;
        """)
    @test_throws r"initial if-equation condition must be evaluable at load time" parse_basemodelica(path; parser, arrays)
end
