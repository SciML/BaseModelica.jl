using Test
using BaseModelica
using ModelingToolkit

BM = BaseModelica

@testset "ANTLR Parser Tests" begin
    @testset "Newton Cooling" begin
        newton_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "NewtonCoolingBase.bmo")
        newton_cooling = BM.parse_file_antlr(newton_path)
        @test newton_cooling isa BM.BaseModelicaPackage
        newton_system = BM.baseModelica_to_ModelingToolkit(newton_cooling)
        @test newton_system isa System
        @test parse_basemodelica(newton_path, parser=:antlr) isa System
    end

    @testset "Negative Variables" begin
        negative_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "NegativeVariable.bmo")
        negative_package = BM.parse_file_antlr(negative_path)
        @test negative_package isa BM.BaseModelicaPackage
        negative_system = BM.baseModelica_to_ModelingToolkit(negative_package)
        @test negative_system isa System
        @test parse_basemodelica(negative_path, parser=:antlr) isa System
    end

    @testset "Experiment Annotation" begin
        experiment_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "Experiment.bmo")
        experiment_package = BM.parse_file_antlr(experiment_path)
        @test experiment_package isa BM.BaseModelicaPackage
        experiment_system = BM.baseModelica_to_ModelingToolkit(experiment_package)
        @test experiment_system isa System
        @test parse_basemodelica(experiment_path, parser=:antlr) isa System
    end

    @testset "Parameter with Modifiers" begin
        param_modifiers_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "ParameterWithModifiers.bmo")
        param_modifiers_package = BM.parse_file_antlr(param_modifiers_path)
        @test param_modifiers_package isa BM.BaseModelicaPackage
        param_modifiers_system = BM.baseModelica_to_ModelingToolkit(param_modifiers_package)
        @test param_modifiers_system isa ODESystem
        @test parse_basemodelica(param_modifiers_path, parser=:antlr) isa System
    end

    @testset "If Equations" begin
        if_equations_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "IfEquation.bmo")
        if_equations_package = BM.parse_file_antlr(if_equations_path)
        @test if_equations_package isa BM.BaseModelicaPackage
        if_equations_system = BM.baseModelica_to_ModelingToolkit(if_equations_package)
        @test if_equations_system isa System
        @test parse_basemodelica(if_equations_path, parser=:antlr) isa System
    end

    @testset "Cauer Low Pass Filters" begin
        # Test CauerLowPassAnalog
        cauer_analog_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "CauerLowPassAnalog.bmo")
        cauer_analog_package = BM.parse_file_antlr(cauer_analog_path)
        @test cauer_analog_package isa BM.BaseModelicaPackage
        cauer_analog_system = BM.baseModelica_to_ModelingToolkit(cauer_analog_package)
        @test cauer_analog_system isa System
        @test parse_basemodelica(cauer_analog_path, parser=:antlr) isa System

        # Test that initial conditions (fixed=true) are set correctly
        @test !isempty(ModelingToolkit.defaults(cauer_analog_system))

        # Test that guess values (fixed=false or no fixed) are set correctly
        @test !isempty(ModelingToolkit.guesses(cauer_analog_system))

        # Test CauerLowPassAnalogSine
        cauer_sine_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "CauerLowPassAnalogSine.bmo")
        cauer_sine_package = BM.parse_file_antlr(cauer_sine_path)
        @test cauer_sine_package isa BM.BaseModelicaPackage
        cauer_sine_system = BM.baseModelica_to_ModelingToolkit(cauer_sine_package)
        @test cauer_sine_system isa System
        @test parse_basemodelica(cauer_sine_path, parser=:antlr) isa System

        # Test CauerLowPassAnalogSineNoAssert
        cauer_sine_noassert_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "CauerLowPassAnalogSineNoAssert.bmo")
        cauer_sine_noassert_package = BM.parse_file_antlr(cauer_sine_noassert_path)
        @test cauer_sine_noassert_package isa BM.BaseModelicaPackage
        cauer_sine_noassert_system = BM.baseModelica_to_ModelingToolkit(cauer_sine_noassert_package)
        @test cauer_sine_noassert_system isa System
        @test parse_basemodelica(cauer_sine_noassert_path, parser=:antlr) isa System
    end

    @testset "Chua Circuits" begin
        # Test ChuaCircuit
        chua_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "ChuaCircuit.bmo")
        chua_package = BM.parse_file_antlr(chua_path)
        @test chua_package isa BM.BaseModelicaPackage
        chua_system = BM.baseModelica_to_ModelingToolkit(chua_package)
        @test chua_system isa System
        @test parse_basemodelica(chua_path, parser=:antlr) isa System

        # Test ChuaCircuitNoAssert
        chua_noassert_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "ChuaCircuitNoAssert.bmo")
        chua_noassert_package = BM.parse_file_antlr(chua_noassert_path)
        @test chua_noassert_package isa BM.BaseModelicaPackage
        chua_noassert_system = BM.baseModelica_to_ModelingToolkit(chua_noassert_package)
        @test chua_noassert_system isa System
        @test parse_basemodelica(chua_noassert_path, parser=:antlr) isa System
    end

    @testset "Minimal Valid File" begin
        minimal_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "MinimalValid.bmo")
        minimal_package = BM.parse_file_antlr(minimal_path)
        @test minimal_package isa BM.BaseModelicaPackage
        # don't want to evaluate since there are no equations
    end

    @testset "Create ODEProblem with ANTLR Parser" begin
        # Test create_odeproblem with Experiment annotation
        experiment_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "Experiment.bmo")

        prob = BM.create_odeproblem(experiment_path, parser=:antlr)
        @test prob isa ODEProblem

        # Check that tspan was set from annotation
        @test prob.tspan[1] == 0.0  # StartTime
        @test prob.tspan[2] == 2.0  # StopTime

        # Check that reltol and saveat were set from annotation
        @test prob.kwargs[:reltol] == 1e-06  # Tolerance
        @test prob.kwargs[:saveat] == 0.004  # Interval

        # Test parse_experiment_annotation directly with ANTLR parser
        experiment_package = BM.parse_file_antlr(experiment_path)
        annotation = experiment_package.model.long_class_specifier.composition.annotation
        @test !isnothing(annotation)
        @test annotation isa BM.BaseModelicaAnnotation

        exp_params = BM.parse_experiment_annotation(annotation)
        @test !isnothing(exp_params)
        @test exp_params.StartTime == 0.0
        @test exp_params.StopTime == 2.0
        @test exp_params.Tolerance == 1e-06
        @test exp_params.Interval == 0.004

        # Test with model without annotation
        newton_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "NewtonCoolingBase.bmo")
        prob_no_annotation = BM.create_odeproblem(newton_path, parser=:antlr)
        @test prob_no_annotation isa ODEProblem
        # Should use default tspan
        @test prob_no_annotation.tspan[1] == 0.0
        @test prob_no_annotation.tspan[2] == 1.0

        # Verify annotation field is nothing for models without annotation
        newton_package = BM.parse_file_antlr(newton_path)
        newton_annotation = newton_package.model.long_class_specifier.composition.annotation
        @test isnothing(newton_annotation)

        # Test that user can override annotation values
        prob_override = BM.create_odeproblem(experiment_path, parser=:antlr, reltol=1e-8, saveat=0.01)
        @test prob_override isa ODEProblem
        @test prob_override.kwargs[:reltol] == 1e-8  # User override
        @test prob_override.kwargs[:saveat] == 0.01  # User override
        @test prob_override.tspan[2] == 2.0  # Still from annotation
    end
end
