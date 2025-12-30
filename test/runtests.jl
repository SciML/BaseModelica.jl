using Test, SafeTestsets

const GROUP = get(ENV, "GROUP", "All")

if GROUP == "All" || GROUP == "Quality"
    @testset "Quality Assurance" begin
        @safetestset "Quality Assurance" include("qa.jl")
        @safetestset "JET Static Analysis" include("test_jet.jl")
    end
end

if GROUP == "All" || GROUP == "Core"
    @testset "BaseModelica" begin
        @safetestset "Julia Parser Tests" begin
            include("test_julia_parser.jl")
        end

        @safetestset "ANTLR Parser Tests" begin
            include("test_antlr_parser.jl")
        end

        @safetestset "Error Message Tests" begin
            include("test_error_messages.jl")
        end
    end
end
