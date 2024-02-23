using BaseModelica
using ModelingToolkit
using Test


@testset "BaseModelica.jl" begin
    # Write your tests here.
end

@testset "Parsing and Conversion Tests" begin
    newton_path = joinpath(pathof(BaseModelica), "test", "testfiles", "NewtonCoolingBase.mo")
    newton_cooling = parse_file("/home/jadonclugston/Documents/Work/dev/Modelica/BaseModelica.jl/test/testfiles/NewtonCoolingBase.mo")
    @test newton_cooling isa BaseModelica.BaseModelicaPackage
    newton_system = baseModelica_to_ModelingToolkit(newton_cooling.model)
    @test newton_system isa ODESystem
end
