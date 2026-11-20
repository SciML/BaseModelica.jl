using Test
using BaseModelica
using ModelingToolkit
using OrdinaryDiffEq
import Symbolics

function review_initialization_model(body)
    path = tempname() * ".bmo"
    write(path, """//! base 0.1.0
    package 'ReviewInitialization'
      model 'ReviewInitialization'
    $body
      end 'ReviewInitialization';
    end 'ReviewInitialization';
    """)
    return path
end

function review_initialization_member(sys, name, i)
    hasproperty(sys, Symbol("$name[$i]")) && return getproperty(sys, Symbol("$name[$i]"))
    return getproperty(sys, Symbol(name))[i]
end

# The optional filters let the review repros run one model per foreground process.
review_cases = (
    :repeated_lhs, :broadcast_lhs, :initial_vector_loop, :initial_loop, :discrete_array, :discrete_loop,
    :if_no_else, :if_mixed_shapes, :backend_equations,
)
review_case_filter = get(ENV, "BASEMODELICA_REVIEW_CASE", "")
review_parser_filter = get(ENV, "BASEMODELICA_REVIEW_PARSER", "")
review_arrays_filter = get(ENV, "BASEMODELICA_REVIEW_ARRAYS", "")
review_selected(values, selection) = isempty(selection) ? values :
    Tuple(x for x in values if string(x) == selection)

@testset "Review initialization ($parser, $arrays, $case)" for
        parser in review_selected((:julia, :antlr), review_parser_filter),
        arrays in review_selected((:scalarize, :keep), review_arrays_filter),
        case in review_selected(review_cases, review_case_filter)

    if case === :repeated_lhs
        # records/outputs/repros/p1_initial_array_eq.bmo: both residuals have LHS 0.
        path = review_initialization_model("""
            Real 'x'; Real 'y';
          initial equation
            {0.0, 0.0} = {'x' - 1.0, 'y' - 2.0};
          equation
            der('x') = -'x'; der('y') = -'y';
        """)
        sys = parse_basemodelica(path; parser, arrays)
        @test sum(eq -> length(vcat(Symbolics.scalarize(eq))), initialization_equations(sys)) == 2
        sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        @test sol(0.0; idxs = sys.x) ≈ 1.0
        @test sol(0.0; idxs = sys.y) ≈ 2.0
        @test sol(1.0; idxs = sys.x) ≈ exp(-1) rtol = 1.0e-3
        @test sol(1.0; idxs = sys.y) ≈ 2exp(-1) rtol = 1.0e-3
    elseif case in (:broadcast_lhs, :initial_vector_loop)
        # Array review div_initial_zero_lhs.bmo and cases/initloop2.bmo.
        initial = case === :broadcast_lhs ? "0 = 'x' - {1, 2};" : """
            for 'i' in 1:2 loop
              'x'['i'] = 'i';
            end for;
        """
        path = review_initialization_model("""
            Real 'x'[2];
          initial equation
            $initial
          equation
            der('x') = -'x';
        """)
        sys = parse_basemodelica(path; parser, arrays)
        sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        for i in 1:2
            var = review_initialization_member(sys, "x", i)
            @test sol(0.0; idxs = var) ≈ i
            @test sol(1.0; idxs = var) ≈ i * exp(-1) rtol = 1.0e-3
        end
    elseif case === :initial_loop
        # arrays/outputs/review/cases/initloop2.bmo, including nested loops.
        path = review_initialization_model("""
            Real 'x'[2,2];
          initial equation
            for 'i' in 1:2 loop
              for 'j' in 1:2 loop
                'x'['i','j'] = 2 * 'i' + 'j';
              end for;
            end for;
          equation
            der('x') = -'x';
        """)
        sys = parse_basemodelica(path; parser, arrays)
        sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        for i in 1:2, j in 1:2
            var = arrays === :keep ? sys.x[i,j] : getproperty(sys, Symbol("x[$i,$j]"))
            @test sol(0.0; idxs = var) ≈ 2i + j
            @test sol(1.0; idxs = var) ≈ (2i + j) * exp(-1) rtol = 1.0e-3
        end
    elseif case in (:discrete_array, :discrete_loop)
        # div_pre_whole_array_initial.bmo and cases/initloop.bmo.
        initial = case === :discrete_array ? """
            pre('d'[1]) = 5;
            pre('e') = {7, 8};
        """ : """
            for 'i' in 1:2 loop
              pre('d'['i']) = 'i';
              pre('e'['i']) = 'i' + 6;
            end for;
        """
        path = review_initialization_model("""
            Real 'x'(start = 0, fixed = true);
            discrete Real 'd'[2](each start = 0);
            discrete Real 'e'[2](each start = 0);
          initial equation
            $initial
          equation
            der('x') = 1;
            when time >= 0.5 then
              'd' = pre('d') + {1, 2};
              'e' = pre('e') + {3, 4};
            end when;
        """)
        sys = parse_basemodelica(path; parser, arrays, discrete_backend = :mtk)
        sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        for (name, starts, increments) in (
                ("d", case === :discrete_array ? (5, 0) : (1, 2), (1, 2)),
                ("e", (7, 8), (3, 4)),
            ), i in 1:2
            var = review_initialization_member(sys, name, i)
            @test sol(0.0; idxs = var) == starts[i]
            @test sol(0.25; idxs = var) == starts[i]
            @test sol(0.75; idxs = var) == starts[i] + increments[i]
        end
    elseif case === :if_no_else
        # P2a_if_no_else_array.bmo, plus the implicit zero fallback itself.
        path = review_initialization_model("""
            Real 'x'[2](start = {1, 2}, each fixed = true);
            Real 'y'[2]; Real 'z'[2];
          equation
            der('x') = -'x';
            if time < 0.5 then
              'y' = 'x';
            elseif true then
              'y' = -'x';
            end if;
            if time < 0.5 then
              'z' = 'x';
            end if;
        """)
        sys = parse_basemodelica(path; parser, arrays)
        sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        for i in 1:2
            y = review_initialization_member(sys, "y", i)
            z = review_initialization_member(sys, "z", i)
            @test sol(0.25; idxs = y) ≈ i * exp(-0.25) rtol = 1.0e-3
            @test sol(0.75; idxs = y) ≈ -i * exp(-0.75) rtol = 1.0e-3
            @test sol(0.25; idxs = z) ≈ i * exp(-0.25) rtol = 1.0e-3
            @test sol(0.75; idxs = z) == 0
        end
    elseif case === :if_mixed_shapes
        # P2b_if_branches_loop_vs_whole.bmo: y[1:1:3] and y are the same targets.
        path = review_initialization_model("""
            Real 'x'[3](start = {1, 2, 3}, each fixed = true);
            Real 'y'[3]; Real 'm'[2,2];
          equation
            der('x') = -'x';
            if time < 0.5 then
              for 'i' in 1:3 loop
                'y'['i'] = 'x'['i'];
              end for;
              for 'i' in 1:2 loop
                for 'j' in 1:2 loop
                  'm'['i','j'] = 'x'['i'] + 'j';
                end for;
              end for;
            else
              'y' = -'x';
              'm' = {{-'x'[1] - 1, -'x'[1] - 2}, {-'x'[2] - 1, -'x'[2] - 2}};
            end if;
        """)
        sys = parse_basemodelica(path; parser, arrays)
        sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        for i in 1:3
            y = review_initialization_member(sys, "y", i)
            @test sol(0.25; idxs = y) ≈ i * exp(-0.25) rtol = 1.0e-3
            @test sol(0.75; idxs = y) ≈ -i * exp(-0.75) rtol = 1.0e-3
        end
        for i in 1:2, j in 1:2
            m = arrays === :keep ? sys.m[i,j] : getproperty(sys, Symbol("m[$i,$j]"))
            @test sol(0.25; idxs = m) ≈ i * exp(-0.25) + j rtol = 1.0e-3
            @test sol(0.75; idxs = m) ≈ -i * exp(-0.75) - j rtol = 1.0e-3
        end
    elseif case === :backend_equations
        path = review_initialization_model("""
            Real 'x'[2](each start = 0, each fixed = true);
            discrete Real 'd'(start = 0);
          equation
            der('x') = {1, 2};
            when time >= 0.5 then
              'd' = pre('d') + 1;
            end when;
        """)
        sys = parse_basemodelica(path; parser, arrays, discrete_backend = :mtk, simplify = false)
        # MTK's backend returns the scalar event view. System must consume it.
        @test length(equations(sys)) == 2
        @test all(eq -> !BaseModelica.is_array(eq.lhs), equations(sys))
    end
end
