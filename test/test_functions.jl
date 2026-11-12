using Test
using BaseModelica
using ModelingToolkit
using OrdinaryDiffEq

BM = BaseModelica

testfile(name) = joinpath(dirname(dirname(pathof(BM))), "test", "testfiles", name * ".bmo")

parse_package(path, parser) = parser == :julia ? BM.parse_file_julia(path) : BM.parse_file_antlr(path)

function write_package(body)
    path = tempname() * ".bmo"
    write(path, "//! base 0.1.0\npackage 'M'\n$body\nend 'M';\n")
    return path
end

@testset "User functions, arrays and unsupported constructs" begin
    @testset "User function AST ($parser)" for parser in (:julia, :antlr)
        package = parse_package(testfile("UserFunction"), parser)
        functions = [
            cd.class for cd in package.class_defs
                if cd isa BM.BaseModelicaClassDefinition && occursin("function", cd.class_type)
        ]
        @test sort([BM.identifier_name(f.name) for f in functions]) == ["decayRate", "polySum"]
        decay = only(filter(f -> BM.identifier_name(f.name) == "decayRate", functions))
        # The indented algorithm section is parsed into statements
        section = only(filter(eq -> eq isa BM.BaseModelicaAlgorithmSection, decay.composition.equations))
        @test length(section.statements) == 2
        @test section.statements[1] isa BM.BaseModelicaAssignment
        @test section.statements[2] isa BM.BaseModelicaIfStatement
        f = BM.UserFunction(BM.identifier_name(decay.name), decay)
        @test first.(f.inputs) == [:x, :k]
        @test first.(f.outputs) == [:y]
        @test first.(f.locals) == [:tmp]
    end

    @testset "User functions are inlined ($parser)" for parser in (:julia, :antlr)
        sys = parse_basemodelica(testfile("UserFunction"); parser)
        sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5(); reltol = 1.0e-8, abstol = 1.0e-10)
        @test sol.retcode == ReturnCode.Success
        # der(x) = -2x while x > 0.5 (until t = log(2)/2), then der(x) = -x
        x1 = sol(1.0; idxs = sys.x)
        @test x1 ≈ 0.5 * exp(-(1 - log(2) / 2)) rtol = 1.0e-4
        # polySum unrolls `for i in 1:3 loop y := y + x^i`
        @test sol(1.0; idxs = sys.z) ≈ x1 + x1^2 + x1^3 rtol = 1.0e-8
        # sum({1.0, 2.0, 3.0}) * x
        @test sol(1.0; idxs = sys.w) ≈ 6 * x1 rtol = 1.0e-8
    end

    @testset "Array constructor parsing ($parser)" for parser in (:julia, :antlr)
        path = write_package(
            """
              model 'M'
                Real 'x';
              equation
                'x' = sum({1.0, 2.0, 3.0});
              end 'M';
            """
        )
        package = parse_package(path, parser)
        eq = only(package.model.long_class_specifier.composition.equations)
        rhs = (eq isa BM.BaseModelicaAnyEquation ? eq.equation : eq).rhs
        @test only(rhs.args.args) isa BM.BaseModelicaArrayConstructor
        @test BM.eval_AST(only(rhs.args.args)) == [1.0, 2.0, 3.0]
    end

    @testset "Unsupported constructs throw ($parser)" for parser in (:julia, :antlr)
        array_variable = write_package(
            """
              model 'M'
                Real 'x'[3];
              equation
                der('x') = {1.0, 2.0, 3.0};
              end 'M';
            """
        )
        # Array variables are supported now (see test_arrays.jl)
        @test length(unknowns(parse_basemodelica(array_variable; parser))) == 3

        matrix = write_package(
            """
              model 'M'
                Real 'x';
              equation
                'x' = sum([1.0, 2.0; 3.0, 4.0]);
              end 'M';
            """
        )
        # Matrix constructors are supported now
        @test parse_basemodelica(matrix; parser) isa BM.ModelingToolkitBase.System

        model_algorithm = write_package(
            """
              model 'M'
                Real 'x';
              algorithm
                'x' := 1.0;
              end 'M';
            """
        )
        @test_throws BM.UnsupportedFeatureError parse_basemodelica(model_algorithm; parser)

        while_function = write_package(
            """
              function 'f'
                input Real 'x';
                output Real 'y';
              algorithm
                'y' := 'x';
                while 'y' > 1.0 loop
                  'y' := 'y' / 2.0;
                end while;
              end 'f';
              model 'M'
                Real 'x';
              equation
                'x' = 'f'(3.0);
              end 'M';
            """
        )
        @test_throws BM.UnsupportedFeatureError parse_basemodelica(while_function; parser)
    end

    @testset "Scalar for-equation is unrolled ($parser)" for parser in (:julia, :antlr)
        path = write_package(
            """
              model 'M'
                Real 'x'(fixed = true, start = 1.0);
              equation
                for 'i' in 1:1 loop
                  der('x') = -2.0 * 'i' * 'x';
                end for;
              end 'M';
            """
        )
        sys = parse_basemodelica(path; parser)
        sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5(); reltol = 1.0e-8)
        @test sol(1.0; idxs = sys.x) ≈ exp(-2.0) rtol = 1.0e-5
    end
end
