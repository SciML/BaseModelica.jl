using Test, SafeTestsets

@testset "BaseModelica" begin
    @safetestset "Quality Assurance" include("qa.jl")
    @safetestset "Parsing and Conversion Tests" begin
        using BaseModelica
        using ModelingToolkit
        newton_path = joinpath(
            pathof(BaseModelica), "test", "testfiles", "NewtonCoolingBase.mo")
        newton_cooling = parse_file("testfiles/NewtonCoolingBase.mo")
        @test newton_cooling isa BaseModelica.BaseModelicaPackage
        newton_system = baseModelica_to_ModelingToolkit(newton_cooling.model)
        @test newton_system isa ODESystem
    end
end
