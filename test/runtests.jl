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

            newton_path = joinpath(
                dirname(dirname(pathof(BM))), "test", "testfiles", "NewtonCoolingBase.mo")
            newton_cooling = BM.parse_file(newton_path)
            @test newton_cooling isa BM.BaseModelicaPackage
            newton_system = BM.baseModelica_to_ModelingToolkit(newton_cooling)
            @test newton_system isa ODESystem
            @test parse_basemodelica("testfiles/NewtonCoolingBase.mo") isa ODESystem
            
            # Test parsing with comments before package (issue #34)
            comment_path = joinpath(
                dirname(dirname(pathof(BM))), "test", "testfiles", "CommentBeforePackage.mo")
            comment_package = BM.parse_file(comment_path)
            @test comment_package isa BM.BaseModelicaPackage
            @test comment_package.name == "Comment"
        end
    end
end
