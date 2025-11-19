using Test
using BaseModelica
using ModelingToolkit

BM = BaseModelica

@testset "ANTLR Parser Tests" begin
    @testset "Newton Cooling" begin
        newton_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "NewtonCoolingBase.mo")
        newton_cooling = BM.parse_file_with_antlr(newton_path)
        @test newton_cooling isa BM.BaseModelicaPackage
        newton_system = BM.baseModelica_to_ModelingToolkit(newton_cooling)
        @test newton_system isa System
        @test parse_basemodelica(newton_path, parser=:antlr) isa System
    end

    @testset "Negative Variables" begin
        negative_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "NegativeVariable.mo")
        negative_package = BM.parse_file_with_antlr(negative_path)
        @test negative_package isa BM.BaseModelicaPackage
        negative_system = BM.baseModelica_to_ModelingToolkit(negative_package)
        @test negative_system isa System
        @test parse_basemodelica(negative_path, parser=:antlr) isa System
    end

    @testset "Experiment Annotation" begin
        experiment_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "Experiment.mo")
        experiment_package = BM.parse_file_with_antlr(experiment_path)
        @test experiment_package isa BM.BaseModelicaPackage
        experiment_system = BM.baseModelica_to_ModelingToolkit(experiment_package)
        @test experiment_system isa System
        @test parse_basemodelica(experiment_path, parser=:antlr) isa System
    end

    @testset "Parameter with Modifiers" begin
        param_modifiers_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "ParameterWithModifiers.mo")
        param_modifiers_package = BM.parse_file_with_antlr(param_modifiers_path)
        @test param_modifiers_package isa BM.BaseModelicaPackage
        param_modifiers_system = BM.baseModelica_to_ModelingToolkit(param_modifiers_package)
        @test param_modifiers_system isa ODESystem
        @test parse_basemodelica(param_modifiers_path, parser=:antlr) isa System
    end

    @testset "If Equations" begin
        if_equations_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "IfEquation.mo")
        if_equations_package = BM.parse_file_with_antlr(if_equations_path)
        @test if_equations_package isa BM.BaseModelicaPackage
        if_equations_system = BM.baseModelica_to_ModelingToolkit(if_equations_package)
        @test if_equations_system isa System
        @test parse_basemodelica(if_equations_path, parser=:antlr) isa System
    end

    @testset "Cauer Low Pass Filters" begin
        # Test CauerLowPassAnalog
        cauer_analog_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "CauerLowPassAnalog.bmo")
        cauer_analog_package = BM.parse_file_with_antlr(cauer_analog_path)
        @test cauer_analog_package isa BM.BaseModelicaPackage
        cauer_analog_system = BM.baseModelica_to_ModelingToolkit(cauer_analog_package)
        @test cauer_analog_system isa System
        @test parse_basemodelica(cauer_analog_path, parser=:antlr) isa System

        # Test CauerLowPassAnalogSine
        cauer_sine_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "CauerLowPassAnalogSine.bmo")
        cauer_sine_package = BM.parse_file_with_antlr(cauer_sine_path)
        @test cauer_sine_package isa BM.BaseModelicaPackage
        cauer_sine_system = BM.baseModelica_to_ModelingToolkit(cauer_sine_package)
        @test cauer_sine_system isa System
        @test parse_basemodelica(cauer_sine_path, parser=:antlr) isa System

        # Test CauerLowPassAnalogSineNoAssert
        cauer_sine_noassert_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "CauerLowPassAnalogSineNoAssert.bmo")
        cauer_sine_noassert_package = BM.parse_file_with_antlr(cauer_sine_noassert_path)
        @test cauer_sine_noassert_package isa BM.BaseModelicaPackage
        cauer_sine_noassert_system = BM.baseModelica_to_ModelingToolkit(cauer_sine_noassert_package)
        @test cauer_sine_noassert_system isa System
        @test parse_basemodelica(cauer_sine_noassert_path, parser=:antlr) isa System
    end

    @testset "Minimal Valid File" begin
        minimal_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "MinimalValid.bmo")
        minimal_package = BM.parse_file_with_antlr(minimal_path)
        @test minimal_package isa BM.BaseModelicaPackage
        @test parse_basemodelica(minimal_path, parser=:antlr) isa System
    end
end
