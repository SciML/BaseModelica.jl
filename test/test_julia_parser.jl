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
            dirname(dirname(pathof(BM))), "test", "testfiles", "NewtonCoolingBase.mo")
        newton_cooling = BM.parse_file(newton_path)
        @test newton_cooling isa BM.BaseModelicaPackage
        newton_system = BM.baseModelica_to_ModelingToolkit(newton_cooling)
        @test newton_system isa System
        @test parse_basemodelica(newton_path, parser=:julia) isa System
    end

    @testset "Negative Variables" begin
        # Test parsing with negative variables (issue #35)
        negative_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "NegativeVariable.mo")
        negative_package = BM.parse_file(negative_path)
        @test negative_package isa BM.BaseModelicaPackage
        negative_system = BM.baseModelica_to_ModelingToolkit(negative_package)
        @test negative_system isa System
        @test parse_basemodelica(negative_path, parser=:julia) isa System
    end

    @testset "Experiment Annotation" begin
        # Test experiment annotation parsing (issue #38)
        experiment_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "Experiment.mo")
        experiment_package = BM.parse_file(experiment_path)
        @test experiment_package isa BM.BaseModelicaPackage
        experiment_system = BM.baseModelica_to_ModelingToolkit(experiment_package)
        @test experiment_system isa System
        @test parse_basemodelica(experiment_path, parser=:julia) isa System
    end

    @testset "Parameter with Modifiers" begin
        # Test parameter with modifiers (issue #49)
        param_modifiers_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "ParameterWithModifiers.mo")
        param_modifiers_package = BM.parse_file(param_modifiers_path)
        @test param_modifiers_package isa BM.BaseModelicaPackage
        param_modifiers_system = BM.baseModelica_to_ModelingToolkit(param_modifiers_package)
        @test param_modifiers_system isa ODESystem
        @test parse_basemodelica(param_modifiers_path, parser=:julia) isa System
    end

    @testset "If Equations" begin
        if_equations_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "IfEquation.mo")
        if_equations_package = BM.parse_file(if_equations_path)
        @test if_equations_package isa BM.BaseModelicaPackage
        if_equations_system = BM.baseModelica_to_ModelingToolkit(if_equations_package)
        @test if_equations_system isa System
        @test parse_basemodelica(if_equations_path, parser=:julia) isa System
    end

    @testset "Cauer Low Pass Filters" begin
        # Test CauerLowPassAnalog
        cauer_analog_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "CauerLowPassAnalog.bmo")
        cauer_analog_package = BM.parse_file(cauer_analog_path)
        @test cauer_analog_package isa BM.BaseModelicaPackage
        cauer_analog_system = BM.baseModelica_to_ModelingToolkit(cauer_analog_package)
        @test cauer_analog_system isa System
        @test parse_basemodelica(cauer_analog_path, parser=:julia) isa System

        # Test CauerLowPassAnalogSine
        cauer_sine_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "CauerLowPassAnalogSine.bmo")
        cauer_sine_package = BM.parse_file(cauer_sine_path)
        @test cauer_sine_package isa BM.BaseModelicaPackage
        cauer_sine_system = BM.baseModelica_to_ModelingToolkit(cauer_sine_package)
        @test cauer_sine_system isa System
        @test parse_basemodelica(cauer_sine_path, parser=:julia) isa System

        # Test CauerLowPassAnalogSineNoAssert
        cauer_sine_noassert_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "CauerLowPassAnalogSineNoAssert.bmo")
        cauer_sine_noassert_package = BM.parse_file(cauer_sine_path)
        @test cauer_sine_noassert_package isa BM.BaseModelicaPackage
        cauer_sine_noassert_system = BM.baseModelica_to_ModelingToolkit(cauer_sine_noassert_package)
        @test cauer_sine_noassert_system isa System
        @test parse_basemodelica(cauer_sine_noassert_path, parser=:julia) isa System
    end
end
