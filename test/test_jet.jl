using BaseModelica
using JET
using Test

@testset "JET static analysis" begin
    # Test that JET finds no errors in the BaseModelica module
    # This helps ensure type stability and catch potential runtime errors
    # Note: We use target_modules to filter reports to only BaseModelica code,
    # since dependencies like SymbolicUtils use union types that trigger false positives.
    @testset "Package analysis" begin
        result = JET.report_package(BaseModelica; target_modules=(BaseModelica,))
        @test length(JET.get_reports(result)) == 0
    end

    # Note: @test_opt tests are not included because the codebase intentionally
    # uses dynamic dispatch patterns from MLStyle.jl (@match) and ParserCombinator.jl
    # which result in expected runtime dispatch. These are design choices that enable
    # clean pattern matching syntax. Full type stability would require major refactoring
    # that's not practical for this domain-specific language parser.
end
