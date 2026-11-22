using Test, BaseModelica, ModelingToolkit, OrdinaryDiffEq

const BM = BaseModelica

@testset "Function call field projection ($parser, $arrays)" for parser in (:julia, :antlr), arrays in (:scalarize, :keep)
    source = """
    //! base 0.1.0
    package 'P'
      record 'Inner' Real 'x'; end 'Inner';
      record 'Outer' 'Inner' 'inner'; Real 'y'; end 'Outer';
      function 'f'
        input Real 'u';
        output 'Outer' 'r';
      algorithm
        'r' := 'Outer'('Inner'('u'), 2 * 'u');
      end 'f';
      model 'M'
        Real 'nested'; Real 'direct'; Real 'product'; Real 'power';
        Real 'quotient'; Real 'minus'; Real 'plus';
      equation
        'nested' = 'f'(time).'inner'.'x';
        'direct' = 'f'(time).'y';
        'product' = 'f'(time).'y' .* 2;
        'power' = 'f'(time).'y' .^ 2;
        'quotient' = 'f'(time).'y' ./ 2;
        'minus' = 'f'(time).'y' .- 2;
        'plus' = 'f'(time).'y' .+ 2;
      end 'M';
    end 'P';
    """
    mktemp() do path, io
        write(io, source)
        close(io)
        ast = parser === :antlr ? BM.parse_file_antlr(path) : BM.parse_file_julia(path)
        equations = ast.model.long_class_specifier.composition.equations
        equation = first(equations)
        rhs = (equation isa BM.BaseModelicaAnyEquation ? equation.equation : equation).rhs
        @test rhs isa BM.BaseModelicaFieldAccess
        @test rhs.field == "x"
        @test rhs.expression isa BM.BaseModelicaFieldAccess
        @test rhs.expression.field == "inner"
        @test rhs.expression.expression isa BM.BaseModelicaFunctionCall
        sys = parse_basemodelica(path; parser, arrays)
        sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        for t in (0.0, 0.5, 1.0), (name, expected) in (
                (:nested, t), (:direct, 2t), (:product, 4t), (:power, 4t^2),
                (:quotient, t), (:minus, 2t - 2), (:plus, 2t + 2),
            )
            @test sol(t; idxs = getproperty(sys, name)) ≈ expected atol = 1e-12
        end
    end
end
