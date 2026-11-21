using Test
using BaseModelica
using ModelingToolkit
using OrdinaryDiffEq

# Filters support a separate bounded Julia process for every model/parser/array mode.
unfixed_cases = (:minimal, :tunable_if, :initial_override, :coupled_initial, :array, :array_partial, :many_switches, :quaternion)
unfixed_selected(values, key) = isempty(get(ENV, key, "")) ? values :
    Tuple(x for x in values if string(x) == ENV[key])

@testset "Unfixed start ($case, $parser, $arrays)" for
        case in unfixed_selected(unfixed_cases, "BASEMODELICA_UNFIXED_CASE"),
        parser in unfixed_selected((:julia, :antlr), "BASEMODELICA_REVIEW_PARSER"),
        arrays in unfixed_selected((:scalarize, :keep), "BASEMODELICA_REVIEW_ARRAYS")
    body = if case === :minimal
        """
        parameter Real 'k' = 1;
        Real 'x'(start = 1);
        equation der('x') = -'k'*'x';
        """
    elseif case === :tunable_if
        """
        parameter Boolean 'b' = true;
        Real 'x'(start = 1);
        equation
          if 'b' then der('x') = -'x'; else der('x') = -2*'x'; end if;
        """
    elseif case === :many_switches
        # These switches change coefficients, not equation incidence. Enumerating
        # their Boolean product would need 2^16 equivalent initialization graphs.
        parameters = join(("parameter Boolean 'b$i' = true;" for i in 1:16), "\n")
        rate = join(("(if 'b$i' then 1 else 2)" for i in 1:16), " + ")
        """
        $parameters
        Real 'x'(start = 1);
        equation der('x') = -(($rate)/16)*'x';
        """
    elseif case === :initial_override
        """
        parameter Real 'k' = 1;
        Real 'x'(start = 1);
        initial equation 0 = 'x' - 2;
        equation der('x') = -'k'*'x';
        """
    elseif case === :coupled_initial
        """
        parameter Real 'k' = 1;
        Real 'x'(start = 1); Real 'y'(start = 1);
        initial equation 'x' + 'y' = 3;
        equation der('x') = -'k'*'x'; der('y') = -'k'*'y';
        """
    elseif case in (:array, :array_partial)
        initial = case === :array_partial ? "initial equation 'x'[1] = 3;" : ""
        """
        parameter Real 'k' = 1;
        Real 'x'[2](start = {1, 2});
        $initial
        equation der('x') = -'k'*'x';
        """
    else
        # A normalized orientation has one fewer independent initial value. The
        # real constraint must determine q4 rather than fixing all four starts.
        """
        parameter Real 'k' = 1;
        Real 'x'(start = 0.5); Real 'y'(start = 0.5);
        Real 'z'(start = 0.5); Real 'q'(start = 0.5);
        initial equation
          'x' = 0; 'y' = 0; 'z' = 0;
          'x'^2 + 'y'^2 + 'z'^2 + 'q'^2 = 1;
        equation
          der('x') = 'k'*0; der('y') = 'k'*0;
          der('z') = 'k'*0; der('q') = 'k'*0;
        """
    end
    mktempdir() do dir
        file = joinpath(dir, "unfixed.bmo")
        write(file, """//! base 0.1.0
        package 'UnfixedStart'
          model 'UnfixedStart'
          $body
          end 'UnfixedStart';
        end 'UnfixedStart';
        """)
        sys = parse_basemodelica(file; parser, arrays)
        prob = ODEProblem(sys, [], (0.0, 1.0))
        sol = solve(prob, Tsit5(); reltol = 1e-9, abstol = 1e-11)
        @test sol.retcode == ReturnCode.Success
        if case in (:array, :array_partial)
            for i in 1:2
                x = arrays === :keep ? sys.x[i] : getproperty(sys, Symbol("x[$i]"))
                start = case === :array_partial && i == 1 ? 3 : i
                @test sol(0.0; idxs = x) ≈ start
                @test sol(1.0; idxs = x) ≈ start*exp(-1) rtol = 1e-7
            end
        elseif case === :quaternion
            @test sol(0.0; idxs = sys.x) ≈ 0 atol = 1e-8
            @test sol(0.0; idxs = sys.y) ≈ 0 atol = 1e-8
            @test sol(0.0; idxs = sys.z) ≈ 0 atol = 1e-8
            @test abs(sol(0.0; idxs = sys.q)) ≈ 1
        elseif case === :coupled_initial
            @test sol(0.0; idxs = sys.x) + sol(0.0; idxs = sys.y) ≈ 3
            @test any(v -> isapprox(sol(0.0; idxs = v), 1), (sys.x, sys.y))
            @test sol(1.0; idxs = sys.x) + sol(1.0; idxs = sys.y) ≈ 3exp(-1) rtol = 1e-7
        else
            start = case === :initial_override ? 2 : 1
            @test sol(0.0; idxs = sys.x) ≈ start
            @test sol(1.0; idxs = sys.x) ≈ start*exp(-1) rtol = 1e-7
            if case in (:tunable_if, :many_switches)
                # Rule 3 keeps b tunable: the same imported system supports remake.
                parameters = case === :tunable_if ? [sys.b => false] :
                    [getproperty(sys, Symbol("b$i")) => false for i in 1:16]
                other = solve(remake(prob; p = parameters), Tsit5(); reltol = 1e-9, abstol = 1e-11)
                @test other.retcode == ReturnCode.Success
                @test other(0.0; idxs = sys.x) ≈ 1
                @test other(1.0; idxs = sys.x) ≈ exp(-2) rtol = 1e-7
            end
        end
    end
end
