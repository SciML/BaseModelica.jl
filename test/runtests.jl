using Test, SafeTestsets

const GROUP = get(ENV, "GROUP", "All")

if GROUP == "All" || GROUP == "Quality"
    @testset "Quality Assurance" begin
        @safetestset "Quality Assurance" include("qa.jl")
    end
end

if GROUP == "All" || GROUP == "Core"
    @testset "BaseModelica" begin
        @safetestset "Parsing and Conversion Tests" begin
            using BaseModelica
            using ModelingToolkit
            BM = BaseModelica
            PC = BM.ParserCombinator

            arith_test = only(PC.parse_one("5 + 6*(45 + 9^2)^2", BM.arithmetic_expression))
            @test arith_test isa BM.BaseModelicaSum
            @test BM.eval_AST(arith_test) == 95261.0
            
            # Test unary minus parsing (issue #35)
            unary_minus_test = only(PC.parse_one("-5", BM.arithmetic_expression))
            @test unary_minus_test isa BM.BaseModelicaUnaryMinus
            @test BM.eval_AST(unary_minus_test) == -5.0

            newton_path = joinpath(
                dirname(dirname(pathof(BM))), "test", "testfiles", "NewtonCoolingBase.mo")
            newton_cooling = BM.parse_file(newton_path)
            @test newton_cooling isa BM.BaseModelicaPackage
            newton_system = BM.baseModelica_to_ModelingToolkit(newton_cooling)
            @test newton_system isa ODESystem
            @test parse_basemodelica("testfiles/NewtonCoolingBase.mo") isa ODESystem
            
            # Test parsing with negative variables (issue #35)
            negative_path = joinpath(
                dirname(dirname(pathof(BM))), "test", "testfiles", "NegativeVariable.mo")
            negative_package = BM.parse_file(negative_path)
            @test negative_package isa BM.BaseModelicaPackage
            negative_system = BM.baseModelica_to_ModelingToolkit(negative_package)
            @test negative_system isa ODESystem
            @test parse_basemodelica("testfiles/NegativeVariable.mo") isa ODESystem
            
            # Test if-expression parsing and evaluation (issue #39)
            if_expr_test = only(PC.parse_one("if 5 > 3 then 10 else 20", BM.if_expression))
            @test if_expr_test isa BM.BaseModelicaIfExpression
            @test BM.eval_AST(if_expr_test) == 10
            
            if_expr_false_test = only(PC.parse_one("if 3 > 5 then 10 else 20", BM.if_expression))
            @test BM.eval_AST(if_expr_false_test) == 20
            
            # Test parsing with if-expressions in full model (issue #39)
            inline_if_path = joinpath(
                dirname(dirname(pathof(BM))), "test", "testfiles", "InlineIf.mo")
            inline_if_package = BM.parse_file(inline_if_path)
            @test inline_if_package isa BM.BaseModelicaPackage
            inline_if_system = BM.baseModelica_to_ModelingToolkit(inline_if_package)
            @test inline_if_system isa ODESystem
            @test parse_basemodelica("testfiles/InlineIf.mo") isa ODESystem
            
            # Test nested if-expression (issue #39)
            nested_if_path = joinpath(
                dirname(dirname(pathof(BM))), "test", "testfiles", "InlineIfNested.mo")
            nested_if_package = BM.parse_file(nested_if_path)
            @test nested_if_package isa BM.BaseModelicaPackage
            nested_if_system = BM.baseModelica_to_ModelingToolkit(nested_if_package)  
            @test nested_if_system isa ODESystem
            @test parse_basemodelica("testfiles/InlineIfNested.mo") isa ODESystem
        end
    end
end
