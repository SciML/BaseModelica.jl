using Test
using BaseModelica
using ModelingToolkit

BM = BaseModelica
PC = BM.ParserCombinator

@testset "Julia ParserCombinator Tests" begin
    @testset "Arithmetic Expression Parsing" begin
        arith_test = only(PC.parse_one("5 + 6*(45 + 9^2)^2", BM.arithmetic_expression))
        @test arith_test isa BM.BaseModelicaSum
        @test BM.eval_AST(arith_test) == 95261.0

        # Test unary minus parsing (issue #35)
        unary_minus_test = only(PC.parse_one("-5", BM.arithmetic_expression))
        @test unary_minus_test isa BM.BaseModelicaUnaryMinus
        @test BM.eval_AST(unary_minus_test) == -5.0
    end

    @testset "Annotation Parsing" begin
        # Test annotation parsing (issue #38)
        annotation_test = only(PC.parse_one("annotation(experiment(StartTime = 0, StopTime = 2.0))", BM.annotation_comment))
        @test annotation_test isa BM.BaseModelicaAnnotation
        @test BM.eval_AST(annotation_test) === nothing
    end

    @testset "Newton Cooling" begin
        newton_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "NewtonCoolingBase.bmo")
        newton_cooling = BM.parse_file_julia(newton_path)
        @test newton_cooling isa BM.BaseModelicaPackage
        newton_system = BM.baseModelica_to_ModelingToolkit(newton_cooling)
        @test newton_system isa System
        @test parse_basemodelica(newton_path, parser=:julia) isa System
    end

    @testset "Negative Variables" begin
        # Test parsing with negative variables (issue #35)
        negative_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "NegativeVariable.bmo")
        negative_package = BM.parse_file_julia(negative_path)
        @test negative_package isa BM.BaseModelicaPackage
        negative_system = BM.baseModelica_to_ModelingToolkit(negative_package)
        @test negative_system isa System
        @test parse_basemodelica(negative_path, parser=:julia) isa System
    end

    @testset "Experiment Annotation" begin
        # Test experiment annotation parsing (issue #38)
        experiment_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "Experiment.bmo")
        experiment_package = BM.parse_file_julia(experiment_path)
        @test experiment_package isa BM.BaseModelicaPackage
        experiment_system = BM.baseModelica_to_ModelingToolkit(experiment_package)
        @test experiment_system isa System
        @test parse_basemodelica(experiment_path, parser=:julia) isa System
    end

    @testset "Parameter with Modifiers" begin
        # Test parameter with modifiers (issue #49)
        param_modifiers_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "ParameterWithModifiers.bmo")
        param_modifiers_package = BM.parse_file_julia(param_modifiers_path)
        @test param_modifiers_package isa BM.BaseModelicaPackage
        param_modifiers_system = BM.baseModelica_to_ModelingToolkit(param_modifiers_package)
        @test param_modifiers_system isa ODESystem
        @test parse_basemodelica(param_modifiers_path, parser=:julia) isa System
    end

    @testset "If Equations" begin
        if_equations_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "IfEquation.bmo")
        if_equations_package = BM.parse_file_julia(if_equations_path)
        @test if_equations_package isa BM.BaseModelicaPackage
        if_equations_system = BM.baseModelica_to_ModelingToolkit(if_equations_package)
        @test if_equations_system isa System
        @test parse_basemodelica(if_equations_path, parser=:julia) isa System
    end

    @testset "Create ODEProblem" begin
        # Test create_odeproblem with Experiment annotation
        experiment_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "Experiment.bmo")

        prob = BM.create_odeproblem(experiment_path, parser=:julia)
        @test prob isa ODEProblem

        # Check that tspan was set from annotation
        @test prob.tspan[1] == 0.0  # StartTime
        @test prob.tspan[2] == 2.0  # StopTime

        # Check that reltol and saveat were set from annotation
        @test prob.kwargs[:reltol] == 1e-06  # Tolerance
        @test prob.kwargs[:saveat] == 0.004  # Interval

        # Test parse_experiment_annotation directly
        experiment_package = BM.parse_file_julia(experiment_path)
        annotation = experiment_package.model.long_class_specifier.composition.annotation
        @test !isnothing(annotation)

        exp_params = BM.parse_experiment_annotation(annotation)
        @test !isnothing(exp_params)
        @test exp_params.StartTime == 0.0
        @test exp_params.StopTime == 2.0
        @test exp_params.Tolerance == 1e-06
        @test exp_params.Interval == 0.004

        # Test with model without annotation
        newton_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "NewtonCoolingBase.bmo")
        prob_no_annotation = BM.create_odeproblem(newton_path, parser=:julia)
        @test prob_no_annotation isa ODEProblem
        # Should use default tspan
        @test prob_no_annotation.tspan[1] == 0.0
        @test prob_no_annotation.tspan[2] == 1.0

        # Test that user can override annotation values
        prob_override = BM.create_odeproblem(experiment_path, parser=:julia, reltol=1e-8, saveat=0.01)
        @test prob_override isa ODEProblem
        @test prob_override.kwargs[:reltol] == 1e-8  # User override
        @test prob_override.kwargs[:saveat] == 0.01  # User override
        @test prob_override.tspan[2] == 2.0  # Still from annotation
    end

    @testset "Cauer Low Pass Filters" begin
        # Test CauerLowPassAnalog
        cauer_analog_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "CauerLowPassAnalog.bmo")
        cauer_analog_package = BM.parse_file_julia(cauer_analog_path)
        @test cauer_analog_package isa BM.BaseModelicaPackage
        cauer_analog_system = BM.baseModelica_to_ModelingToolkit(cauer_analog_package)
        @test cauer_analog_system isa System
        @test parse_basemodelica(cauer_analog_path, parser=:julia) isa System

        # Test CauerLowPassAnalogSine
        cauer_sine_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "CauerLowPassAnalogSine.bmo")
        cauer_sine_package = BM.parse_file_julia(cauer_sine_path)
        @test cauer_sine_package isa BM.BaseModelicaPackage
        cauer_sine_system = BM.baseModelica_to_ModelingToolkit(cauer_sine_package)
        @test cauer_sine_system isa System
        @test parse_basemodelica(cauer_sine_path, parser=:julia) isa System

        # Test CauerLowPassAnalogSineNoAssert
        cauer_sine_noassert_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "CauerLowPassAnalogSineNoAssert.bmo")
        cauer_sine_noassert_package = BM.parse_file_julia(cauer_sine_path)
        @test cauer_sine_noassert_package isa BM.BaseModelicaPackage
        cauer_sine_noassert_system = BM.baseModelica_to_ModelingToolkit(cauer_sine_noassert_package)
        @test cauer_sine_noassert_system isa System
        @test parse_basemodelica(cauer_sine_noassert_path, parser=:julia) isa System
    end
end
