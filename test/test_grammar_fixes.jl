using Test
using BaseModelica
using ModelingToolkit

BM = BaseModelica

grammar_package(body) = "//! base 0.1.0\npackage 'Grammar'\n$body\nend 'Grammar';\n"
grammar_ast(source) = BM.antlr_tree_to_ast(BM.parse_with_antlr(source))
grammar_composition(pkg) = pkg.model.long_class_specifier.composition
grammar_names(composition) = [
    decl.declaration.ident[1].name
        for component in composition.components for decl in component.component_list
]

@testset "ANTLR grammar fixes" begin
    @testset "each modifiers retain names, values and nesting" begin
        pkg = grammar_ast(
            grammar_package(
                """
                model 'M'
                  Real 'x'[3](each start = 2.0, each fixed = true, each unit = "1");
                  Real 'y'[3](start = {1, 2, 3}, each nominal = 4.0);
                  Real 'z'[2](each outer(each start = 5.0 "nested"));
                equation
                  der('x') = -'x';
                  der('y') = -'y';
                  der('z') = -'z';
                end 'M';
                """
            )
        )
        composition = grammar_composition(pkg)
        @test grammar_names(composition) == ["x", "y", "z"]
        x, y, z = [only(c.component_list).declaration for c in composition.components]
        @test [arg.name.name for arg in only(x.modification).class_modifications] ==
            ["start", "fixed", "unit"]
        @test BM.get_class_modification_value(x.modification, "start") == 2.0
        @test BM.get_class_modification_value(x.modification, "fixed") === true
        @test BM.get_class_modification_value(x.modification, "unit") == "1"
        @test BM.get_class_modification_value(y.modification, "start") == [1, 2, 3]
        @test BM.get_class_modification_value(y.modification, "nominal") == 4.0
        outer = only(only(z.modification).class_modifications)
        @test outer.name.name == "outer"
        @test BM.get_class_modification_value([outer.modification], "start") == 5.0
    end

    @testset "public and protected declarations remain in source order" begin
        pkg = grammar_ast(
            grammar_package(
                """
                model 'M'
                  Real 'before';
                protected
                  parameter Real 'gain' = 2;
                  Real 'hidden';
                public
                  Real 'after';
                equation
                  'before' = 'gain';
                  'hidden' = 'before';
                protected
                  Real 'later';
                equation
                  'later' = 'hidden';
                  'after' = 'later';
                public
                protected
                end 'M';
                """
            )
        )
        composition = grammar_composition(pkg)
        @test grammar_names(composition) == ["before", "gain", "hidden", "after", "later"]
        @test composition.components[2].type_prefix.dpc == "parameter"
        @test length(composition.equations) == 4
    end

    @testset "visibility sections around function algorithms" begin
        pkg = grammar_ast(
            grammar_package(
                """
                function 'f'
                public
                  input Real 'x';
                  output Real 'y';
                protected
                  Real 'tmp';
                algorithm
                  'tmp' := 'x' + 1;
                  'y' := 'tmp';
                public
                end 'f';
                model 'M'
                public
                  Real 'x';
                initial equation
                  'x' = 1;
                protected
                  Real 'hidden';
                equation
                  der('x') = -'x';
                  'hidden' = 'x';
                end 'M';
                """
            )
        )
        function_composition = only(pkg.class_defs).class.composition
        @test grammar_names(function_composition) == ["x", "y", "tmp"]
        algorithm = only(function_composition.equations)
        @test algorithm isa BM.BaseModelicaAlgorithmSection
        @test !algorithm.initial
        @test length(algorithm.statements) == 2
        @test length(grammar_composition(pkg).initial_equations) == 1
        @test length(grammar_composition(pkg).equations) == 2
    end

    @testset "each starts and protected states reach ModelingToolkit" begin
        source = grammar_package(
            """
            model 'M'
            protected
              Real 'x'[3](each start = 2.0, each fixed = true, each unit = "1");
            public
              Real 'y';
            equation
              der('x') = -'x';
              'y' = sum('x');
            end 'M';
            """
        )
        mktemp() do path, io
            write(io, source)
            close(io)
            sys = parse_basemodelica(path; parser = :antlr, simplify = false)
            @test sys isa System
            @test length(ModelingToolkit.unknowns(sys)) == 4
            @test length(ModelingToolkit.equations(sys)) == 4
            initial_conditions = Dict(
                ModelingToolkit.getname(var) => value
                    for (var, value) in ModelingToolkit.initial_conditions(sys)
            )
            for i in 1:3
                @test BM.SymbolicUtils.unwrap_const(initial_conditions[Symbol("x[$i]")]) == 2.0
            end
        end
    end

    @testset "quoted keywords and malformed syntax" begin
        pkg = grammar_ast(
            grammar_package(
                """
                model 'M'
                  Real 'each', 'protected', 'public';
                equation
                  'each' = 1;
                  'protected' = 2;
                  'public' = 3;
                end 'M';
                """
            )
        )
        @test grammar_names(grammar_composition(pkg)) == ["each", "protected", "public"]
        for declaration in (
                "Real 'x'[2](each = 1);",
                "Real 'x'[2](each each start = 1);",
                "protected; Real 'x';",
            )
            @test_throws BM.BaseModelicaParseError grammar_ast(
                grammar_package("model 'M'\n$declaration\nend 'M';")
            )
        end
    end
end


@testset "Visibility and each agree between parsers ($parser)" for parser in (:julia, :antlr)
    mktemp() do path, io
        write(
            io, grammar_package(
                """
                model M
                protected
                  Real x[2](each start=1, each fixed=true);
                public
                  Real y;
                equation
                  der(x) = -x;
                  y = sum(x);
                initial algorithm
                  assert(y >= 0, "initial");
                annotation(experiment(StopTime=2));
                end M;
                """
            )
        )
        close(io)
        package = BM.parse_package(path, parser)
        composition = grammar_composition(package)
        @test grammar_names(composition) == ["x", "y"]
        section = only(filter(x -> x isa BM.BaseModelicaAlgorithmSection, composition.equations))
        @test length(section.statements) == 1
        @test BM.function_call_name(only(section.statements)) == "assert"
        sys = BM.baseModelica_to_ModelingToolkit(package; simplify = false)
        @test length(ModelingToolkit.unknowns(sys)) == 3
        @test length(ModelingToolkit.equations(sys)) == 3
        @test experiment_settings(sys).StopTime == 2
    end
end
