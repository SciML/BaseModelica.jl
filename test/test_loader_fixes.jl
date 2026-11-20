using Test
using BaseModelica
using ModelingToolkit
using Symbolics

const BM = BaseModelica

function loader_package(f, body)
    return mktempdir() do dir
        path = joinpath(dir, "LoaderFixes.bmo")
        write(path, "//! base 0.1.0\npackage 'LoaderFixes'\n$body\nend 'LoaderFixes';\n")
        return f(path)
    end
end

numeric_at(expr, variable, value) = Symbolics.value(
    Symbolics.substitute(expr, Dict(variable => value); fold = Val(true))
)

@testset "Loader fixes" begin
    @testset "Branch-local reads ($parser)" for parser in (:antlr, :julia)
        loader_package(
            """
              function 'branchValues'
                input Real 'x';
                output Real 'y'[2];
                Real 'a';
                Real 'b';
              algorithm
                if 'x' > 1 then
                  'a' := 'x' - 2;
                  if 'a' > 0 then
                    'y'[1] := 'a';
                  else
                    'y'[1] := -'a';
                  end if;
                  'y'[2] := 2 * 'y'[1];
                elseif 'x' > 0 then
                  'b' := 'x' + 2;
                  'y'[1] := 'b';
                  'y'[2] := 3 * 'y'[1];
                else
                  'a' := 'x' - 1;
                  'y'[1] := 'a';
                  'y'[2] := -'y'[1];
                end if;
                'y'[2] := 'y'[2] + 'x';
              end 'branchValues';
              function 'isolatedValues'
                input Real 'x';
                output Real 'y'[2] = {10, 20};
              algorithm
                if 'x' > 0 then
                  'y'[1] := 'x';
                  'y'[2] := 'y'[1] + 1;
                else
                  'y'[2] := 'y'[1] - 1;
                  'y'[1] := 'y'[2] + 1;
                end if;
              end 'isolatedValues';
              function 'missingOutput'
                input Real 'x';
                output Real 'y';
              algorithm
                if 'x' > 0 then
                  'y' := 'x';
                end if;
              end 'missingOutput';
              model 'LoaderFixes'
                Real 'x';
              equation
                'x' = 0;
              end 'LoaderFixes';
            """
        ) do path
            package = BM.parse_package(path, parser)
            BM.register_user_functions!(package.class_defs)
            @variables branch_x
            arg = BM.BaseModelicaNumber(branch_x)
            sentinel = Dict{Symbol, Any}(:sentinel => 42)
            BM.with_local_scope(sentinel) do
                values = BM.inline_user_function(BM.user_function_map["branchValues"], [arg])
                @test BM.LOCAL_SCOPE[] === sentinel
                for (x, expected) in (
                        (3.0, [1.0, 5.0]), (1.5, [0.5, 2.5]),
                        (0.5, [2.5, 8.0]), (-1.0, [-2.0, 1.0]),
                    )
                    @test numeric_at.(values, branch_x, x) ≈ expected
                    # Constant conditions follow the same algorithm without a symbolic merge.
                    @test BM.inline_user_function(
                        BM.user_function_map["branchValues"], [BM.BaseModelicaNumber(x)]
                    ) ≈ expected
                end
                isolated = BM.inline_user_function(BM.user_function_map["isolatedValues"], [arg])
                @test numeric_at.(isolated, branch_x, 2.0) ≈ [2.0, 3.0]
                @test numeric_at.(isolated, branch_x, -2.0) ≈ [10.0, 9.0]
                @test_throws BM.UnsupportedFeatureError BM.inline_user_function(
                    BM.user_function_map["missingOutput"], [arg]
                )
                @test BM.LOCAL_SCOPE[] === sentinel
                @test BM.INLINE_DEPTH[] == 0
            end
            @test BM.LOCAL_SCOPE[] === nothing
        end
    end

    @testset "Concrete dimensions, symbolic values ($parser)" for parser in (:antlr, :julia)
        sizes = (
            ("floor", "floor('n')", 5), ("ceil", "ceil('n')", 6),
            ("integer", "integer('n')", 5), ("div", "div('n', 2)", 2),
            ("negative_floor", "floor(-'n') + 7", 1),
            ("negative_ceil", "ceil(-'n') + 7", 2),
            ("negative_integer", "integer(-'n') + 7", 1),
            ("negative_div", "div(-'n', 2) + 5", 3),
        )
        functions = join(
            [
                """
                  function 'sized_$name'
                    input Real 'n';
                    output Real 'y'[$dimension];
                  algorithm
                    'y' := fill('n' + floor('n') + ceil('n') + integer('n'), $dimension);
                  end 'sized_$name';
                """ for (name, dimension, _) in sizes
            ], "\n"
        )
        declarations = join(["Real '$name'[$dimension];" for (name, dimension, _) in sizes], "\n")
        equations = join(["'$name' = 'sized_$name'('n');" for (name, _, _) in sizes], "\n")
        loader_package(
            """
            $functions
              model 'LoaderFixes'
                parameter Real 'early'[floor('n')] = 'sized_floor'('n');
                parameter Real 'n' = 5.8;
                parameter Integer 'count' = div(9, 2);
                Real 'extra'['count'];
                $declarations
                Real 'runtime_floor';
                Real 'runtime_ceil';
                Real 'runtime_integer';
              equation
                $equations
                'extra' = zeros('count');
                'runtime_floor' = floor('n');
                'runtime_ceil' = ceil('n');
                'runtime_integer' = integer('n');
              end 'LoaderFixes';
            """
        ) do path
            sys = parse_basemodelica(path; parser, simplify = false)
            @test length(BM.array_components[:early]) == 5
            @test length(BM.array_components[:extra]) == 4
            for (name, _, size) in sizes
                @test length(BM.array_components[Symbol(name)]) == size
                elements = [BM.variable_map[n] for n in BM.array_components[Symbol(name)]]
                eqs = filter(eq -> any(isequal(eq.lhs), elements), ModelingToolkit.equations(sys))
                @test length(eqs) == size
                # Size inputs are concrete during loading; the returned values stay tunable.
                n = BM.variable_map[:n]
                @test all(eq -> isequal(eq.rhs, n + floor(n) + ceil(n) + floor(n)), eqs)
                @test all(eq -> numeric_at(eq.rhs, n, 8.4) ≈ 33.4, eqs)
            end
            for (name, expected) in (("floor", 8.0), ("ceil", 9.0), ("integer", 8.0))
                eq = only(
                    filter(
                        eq -> isequal(eq.lhs, BM.variable_map[Symbol("runtime_$name")]),
                        ModelingToolkit.equations(sys)
                    )
                )
                @test !isempty(Symbolics.get_variables(eq.rhs))
                @test numeric_at(eq.rhs, BM.variable_map[:n], 8.4) == expected
            end
            # A run-time div remains explicitly unsupported; structural folding must not
            # silently freeze the value of a symbolic parameter in ordinary equations.
            @test_throws BM.UnsupportedFeatureError BM.call_builtin(:div, [BM.variable_map[:n], 2])
            @test BM.STRUCTURAL_EVAL[] === false
            @test BM.LOCAL_SCOPE[] === nothing
        end
    end
end
