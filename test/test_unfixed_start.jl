using Test
using BaseModelica
using ModelingToolkit
using OrdinaryDiffEq

# Filters support a separate bounded Julia process for every model/parser/array mode.
unfixed_cases = (
    :minimal, :tunable_if, :initial_override, :coupled_initial, :array, :array_partial,
    :many_switches, :quaternion, :constant, :constant_initial_override,
    :constant_array, :constant_array_partial, :constant_coupled, :conditional_state,
    :nested_conditional_state,
    :parameter_start, :coupled_parameter_start, :array_coupled, :array_scalar_coupled,
    :nonlinear_ode, :nonlinear_dae_rejected, :dynamic_state_rejected,
    :initial_derivative, :inconsistent_initial, :inconsistent_fixed_start, :inconsistent_direct_initial,
    :index2_start,
    :repeated_consistent_initial,
)
unfixed_selected(values, key) = isempty(get(ENV, key, "")) ? values :
    Tuple(x for x in values if string(x) == ENV[key])

@testset "Unfixed start ($case, $parser, $arrays, $path)" for
        case in unfixed_selected(unfixed_cases, "BASEMODELICA_UNFIXED_CASE"),
        parser in unfixed_selected((:julia, :antlr), "BASEMODELICA_REVIEW_PARSER"),
        arrays in unfixed_selected((:scalarize, :keep), "BASEMODELICA_REVIEW_ARRAYS"),
        path in unfixed_selected((:automatic, :manual), "BASEMODELICA_UNFIXED_PATH")
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
    elseif case === :index2_start
        """
        Real 'x'(start = 1); Real 'y'(start = 7); Real 'z';
        equation der('x') = 'z'; der('y') = time - 2*'z'; 'x' + 'y' = 3;
        """
    elseif case === :initial_derivative
        """
        parameter Real 'k' = 1;
        Real 'x'(start = 1); Real 'v'(start = 2);
        initial equation der('x') = 0;
        equation der('x') = 'v'; der('v') = -'k'*'x';
        """
    elseif case in (:inconsistent_initial, :inconsistent_fixed_start, :inconsistent_direct_initial, :repeated_consistent_initial)
        x_declaration = case !== :inconsistent_fixed_start ? "Real 'x'(start = 5);" :
            "Real 'x'(start = 1, fixed = true);"
        initial = case === :inconsistent_initial ? "{0, 0} = {'x' - 1, 'x' - 2};" :
            case === :inconsistent_direct_initial ? "'x' = 1; 'x' = 2;" :
            case === :repeated_consistent_initial ? "'x' = 1; 'x' = 1;" : "'x' = 2;"
        dynamics = case in (:inconsistent_initial, :repeated_consistent_initial) ? "der('x') = 0; der('y') = 0;" :
            "der('x') = -'x'; der('y') = -'y';"
        """
        $x_declaration Real 'y'(start = 5);
        initial equation $initial
        equation $dynamics
        """
    elseif case === :nonlinear_ode
        """
        parameter Real 'k' = 1; Real 'x'(start = 1);
        equation der('x') = -'k'*'x'^2;
        """
    elseif case === :nonlinear_dae_rejected
        """
        parameter Real 'L' = 1; parameter Real 'g' = 9.81;
        Real 'x'(start = 0.6); Real 'y'(start = -0.8);
        Real 'vx'(start = 0); Real 'vy'(start = 0); Real 'lam';
        equation
          der('x') = 'vx'; der('y') = 'vy';
          der('vx') = -'lam'*'x'; der('vy') = -'lam'*'y' - 'g';
          'x'^2 + 'y'^2 = 'L'^2;
        """
    elseif case === :dynamic_state_rejected
        """
        Real 'x'(start = 1); Real 'y';
        equation
          if time < 0.5 then
            der('x') = -'x'; 0 = 'y' - 'x';
          else
            0 = 'x' - 2; 0 = 'y' - der('x');
          end if;
        """
    elseif case === :parameter_start
        """
        parameter Real 'x0' = 2; parameter Real 'k' = 1;
        Real 'x'(start = 'x0');
        equation der('x') = -'k'*'x';
        """
    elseif case === :coupled_parameter_start
        """
        parameter Real 'x0' = 2; parameter Real 'k' = 1;
        Real 'x'(start = 1); Real 'y'(start = 1); Real 'z'(start = 'x0');
        initial equation 'x' + 'y' = 3;
        equation der('x') = -'k'*'x'; der('y') = -'k'*'y'; der('z') = -'k'*'z';
        """
    elseif case === :array_scalar_coupled
        """
        parameter Real 'k' = 1;
        Real 'x'[2](start = {1, 2}); Real 'y'(start = 4);
        initial equation 'x'[1] + 'y' = 10;
        equation der('x') = -'k'*'x'; der('y') = -'y';
        """
    elseif case === :array_coupled
        """
        parameter Real 'k' = 1;
        Real 'x'[3](start = {1, 2, 3}, fixed = {true, false, false});
        initial equation 'x'[2] + 'x'[3] = 10;
        equation der('x') = -'k'*'x';
        """
    elseif case in (:constant, :constant_initial_override)
        initial = case === :constant_initial_override ? "initial equation 0 = 'x' - 2;" : ""
        """
        Real 'x'(start = 3);
        $initial
        equation der('x') = 0;
        """
    elseif case in (:constant_array, :constant_array_partial)
        initial = case === :constant_array_partial ? "initial equation 'x'[1] = 5;" : ""
        """
        Real 'x'[2](start = {3, 4});
        $initial
        equation der('x') = {0, 0};
        """
    elseif case === :constant_coupled
        """
        Real 'x'(start = 1); Real 'y'(start = 2);
        initial equation 'x' + 'y' = 10;
        equation der('x') = 0; der('y') = 0;
        """
    elseif case in (:conditional_state, :nested_conditional_state)
        outer_parameter = case === :nested_conditional_state ? "parameter Boolean 'enable' = true;" : ""
        before = case === :nested_conditional_state ? "if 'enable' then" : ""
        after = case === :nested_conditional_state ? "else der('x') = -2*'x'; 0 = 'y' - 'x'; end if;" : ""
        """
        $outer_parameter
        parameter Boolean 'b' = true;
        Real 'x'(start = 1); Real 'y';
        equation
          $before
          if 'b' then
            der('x') = -'x'; 0 = 'y' - 'x';
          else
            0 = 'y' - der('x'); 0 = 'x' - sin(time);
          end if;
          $after
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
        compile_model() = if path === :manual
            raw = parse_basemodelica(file; parser, arrays, simplify = false)
            check_algebraic_crossings(mtkcompile(raw))
        else
            parse_basemodelica(file; parser, arrays)
        end
        if case in (:nonlinear_dae_rejected, :dynamic_state_rejected)
            err = try
                compile_model()
                nothing
            catch e
                e
            end
            @test err isa BaseModelica.UnsupportedFeatureError
            message = case === :nonlinear_dae_rejected ? "nonlinear initialization component" :
                "time-dependent if-equation changes the initialization constraints"
            @test occursin(message, sprint(showerror, err))
            return
        end
        sys = compile_model()
        @test complete_unfixed_initialization(sys) === sys
        prob = ODEProblem(sys, [], (0.0, 1.0))
        sol = solve(prob, case in (:conditional_state, :nested_conditional_state, :index2_start) ? Rodas5P() : Tsit5(); reltol = 1e-9, abstol = 1e-11)
        if case in (:inconsistent_initial, :inconsistent_fixed_start, :inconsistent_direct_initial)
            # An independent free y must not hide contradictory constraints on x.
            @test sol.retcode == ReturnCode.InitialFailure
            return
        end
        @test sol.retcode == ReturnCode.Success
        if case === :repeated_consistent_initial
            @test sol(0.0; idxs = sys.x) ≈ 1
            @test sol(0.0; idxs = sys.y) ≈ 5
            @test sol(1.0; idxs = sys.x) ≈ 1
            @test sol(1.0; idxs = sys.y) ≈ 5
        elseif case === :index2_start
            @test sol(0.0; idxs = sys.x) ≈ 1
            @test sol(0.0; idxs = sys.y) ≈ 2
            @test sol(1.0; idxs = sys.x) ≈ 1.5 rtol = 1e-7
            @test sol(1.0; idxs = sys.y) ≈ 1.5 rtol = 1e-7
            for values in ([sys.x => 2.5], [sys.y => 0.5])
                changed = solve(remake(prob; u0 = values), Rodas5P(); reltol = 1e-9, abstol = 1e-11)
                @test changed.retcode == ReturnCode.Success
                @test changed(0.0; idxs = sys.x) ≈ 2.5
                @test changed(0.0; idxs = sys.y) ≈ 0.5
            end
        elseif case === :initial_derivative
            @test sol(0.0; idxs = sys.x) ≈ 1
            @test sol(0.0; idxs = sys.v) ≈ 0 atol = 1e-10
            @test sol(1.0; idxs = sys.x) ≈ cos(1) rtol = 1e-7
            @test sol(1.0; idxs = sys.v) ≈ -sin(1) rtol = 1e-7
            changed = solve(remake(prob; u0 = [sys.x => 2.5]), Tsit5(); reltol = 1e-9, abstol = 1e-11)
            @test changed.retcode == ReturnCode.Success
            @test changed(0.0; idxs = sys.x) ≈ 2.5
            @test changed(0.0; idxs = sys.v) ≈ 0 atol = 1e-10
        elseif case === :nonlinear_ode
            @test sol(0.0; idxs = sys.x) ≈ 1
            @test sol(1.0; idxs = sys.x) ≈ 0.5 rtol = 1e-7
            changed = solve(remake(prob; u0 = [sys.x => 2.0]), Tsit5(); reltol = 1e-9, abstol = 1e-11)
            @test changed.retcode == ReturnCode.Success
            @test changed(1.0; idxs = sys.x) ≈ 2/3 rtol = 1e-7
        elseif case === :array_scalar_coupled
            elems = [arrays === :keep ? sys.x[i] : getproperty(sys, Symbol("x[$i]")) for i in 1:2]
            @test sol(0.0; idxs = [elems; sys.y]) ≈ [1, 2, 9]
            @test sol(1.0; idxs = [elems; sys.y]) ≈ [1, 2, 9] .* exp(-1) rtol = 1e-7
            for values in ([elems[1] => 3.0], [sys.y => 7.0])
                for override in (ODEProblem(sys, values, (0.0, 1.0)), remake(prob; u0 = values))
                    changed = solve(override, Tsit5(); reltol = 1e-9, abstol = 1e-11)
                    @test changed.retcode == ReturnCode.Success
                    @test changed(0.0; idxs = [elems; sys.y]) ≈ [3, 2, 7]
                    @test changed(1.0; idxs = [elems; sys.y]) ≈ [3, 2, 7] .* exp(-1) rtol = 1e-7
                end
            end
        elseif case === :array_coupled
            elems = [hasproperty(sys, :x) ? sys.x[i] : getproperty(sys, Symbol("x[$i]")) for i in 1:3]
            @test sol(0.0; idxs = elems) ≈ [1, 2, 8]
            for override in (ODEProblem(sys, [elems[3] => 7.0], (0.0, 1.0)), remake(prob; u0 = [elems[3] => 7.0]))
                changed = solve(override, Tsit5(); reltol = 1e-9, abstol = 1e-11)
                @test changed.retcode == ReturnCode.Success
                @test changed(0.0; idxs = elems) ≈ [1, 3, 7]
            end
        elseif case === :parameter_start
            @test sol(0.0; idxs = sys.x) ≈ 2
            changed = solve(remake(prob; p = [sys.x0 => 3.0]), Tsit5(); reltol = 1e-9, abstol = 1e-11)
            @test changed.retcode == ReturnCode.Success
            @test changed(0.0; idxs = sys.x) ≈ 3
            @test changed(1.0; idxs = sys.x) ≈ 3exp(-1) rtol = 1e-7
        elseif case in (:array, :array_partial)
            for i in 1:2
                x = arrays === :keep ? sys.x[i] : getproperty(sys, Symbol("x[$i]"))
                start = case === :array_partial && i == 1 ? 3 : i
                @test sol(0.0; idxs = x) ≈ start
                @test sol(1.0; idxs = x) ≈ start*exp(-1) rtol = 1e-7
            end
        elseif case in (:constant_array, :constant_array_partial)
            for i in 1:2
                x = arrays === :keep ? sys.x[i] : getproperty(sys, Symbol("x[$i]"))
                start = case === :constant_array_partial && i == 1 ? 5 : i + 2
                @test sol(0.0; idxs = x) ≈ start
                @test sol(1.0; idxs = x) ≈ start
            end
        elseif case in (:constant, :constant_initial_override)
            start = case === :constant ? 3 : 2
            @test sol(0.0; idxs = sys.x) ≈ start
            @test sol(1.0; idxs = sys.x) ≈ start
        elseif case === :constant_coupled
            @test sol(0.0; idxs = sys.x) + sol(0.0; idxs = sys.y) ≈ 10
            @test any(((sys.x, 1), (sys.y, 2))) do (var, start)
                isapprox(sol(0.0; idxs = var), start)
            end
            @test sol(1.0; idxs = sys.x) + sol(1.0; idxs = sys.y) ≈ 10
        elseif case in (:conditional_state, :nested_conditional_state)
            @test sol(0.0; idxs = sys.x) ≈ 1
            @test sol(0.0; idxs = sys.y) ≈ 1
            @test sol(1.0; idxs = sys.x) ≈ exp(-1) rtol = 1e-7
            @test sol(1.0; idxs = sys.y) ≈ exp(-1) rtol = 1e-7
            algebraic = remake(prob; p = [sys.b => false])
            other = solve(algebraic, Rodas5P(); reltol = 1e-9, abstol = 1e-11)
            @test other.retcode == ReturnCode.Success
            @test other(0.0; idxs = sys.x) ≈ 0 atol = 1e-9
            @test other(1.0; idxs = sys.x) ≈ sin(1) rtol = 1e-7
            @test other(1.0; idxs = sys.y) ≈ cos(1) rtol = 1e-7
            back = solve(remake(algebraic; p = [sys.b => true]), Rodas5P(); reltol = 1e-9, abstol = 1e-11)
            @test back.retcode == ReturnCode.Success
            @test back(0.0; idxs = sys.x) ≈ 1
            @test back(1.0; idxs = sys.x) ≈ exp(-1) rtol = 1e-7
            if case === :nested_conditional_state
                # Both inner choices share this outer incidence graph. Keep both
                # configurations when merging graphs and constructing the guard.
                disabled = solve(remake(prob; p = [sys.enable => false, sys.b => false]), Rodas5P(); reltol = 1e-9, abstol = 1e-11)
                @test disabled.retcode == ReturnCode.Success
                @test disabled(0.0; idxs = sys.x) ≈ 1
                @test disabled(1.0; idxs = sys.x) ≈ exp(-2) rtol = 1e-7
                @test disabled(1.0; idxs = sys.y) ≈ exp(-2) rtol = 1e-7
            end
        elseif case === :quaternion
            @test sol(0.0; idxs = sys.x) ≈ 0 atol = 1e-8
            @test sol(0.0; idxs = sys.y) ≈ 0 atol = 1e-8
            @test sol(0.0; idxs = sys.z) ≈ 0 atol = 1e-8
            @test abs(sol(0.0; idxs = sys.q)) ≈ 1
        elseif case in (:coupled_initial, :coupled_parameter_start)
            @test sol(0.0; idxs = sys.x) ≈ 1
            @test sol(0.0; idxs = sys.y) ≈ 2
            @test sol(1.0; idxs = sys.x) + sol(1.0; idxs = sys.y) ≈ 3exp(-1) rtol = 1e-7
            # A start is a fallback for the whole coupled component, so supplying
            # either state must let the real initial equation determine the other.
            for values in ([sys.x => 2.5], [sys.y => 0.5])
                for override in (ODEProblem(sys, values, (0.0, 1.0)), remake(prob; u0 = values))
                    overridden = solve(override, Tsit5(); reltol = 1e-9, abstol = 1e-11)
                    @test overridden.retcode == ReturnCode.Success
                    @test overridden(0.0; idxs = sys.x) ≈ 2.5
                    @test overridden(0.0; idxs = sys.y) ≈ 0.5
                    case === :coupled_parameter_start && @test overridden(0.0; idxs = sys.z) ≈ 2
                end
            end
            extra = ODEProblem(sys, [], (0.0, 1.0); initialization_eqs = [sys.y ~ 0.5])
            overridden = solve(extra, Tsit5(); reltol = 1e-9, abstol = 1e-11)
            @test overridden.retcode == ReturnCode.Success
            @test overridden(0.0; idxs = sys.x) ≈ 2.5
            @test overridden(0.0; idxs = sys.y) ≈ 0.5
            if case === :coupled_parameter_start
                @test sol(0.0; idxs = sys.z) ≈ 2
                changed = solve(remake(prob; p = [sys.x0 => 3.0]), Tsit5(); reltol = 1e-9, abstol = 1e-11)
                @test changed.retcode == ReturnCode.Success
                @test changed(0.0; idxs = sys.z) ≈ 3
            end
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
