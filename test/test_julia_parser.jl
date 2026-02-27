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
        annotation_test = only(
            PC.parse_one(
                "annotation(experiment(StartTime = 0, StopTime = 2.0))", BM.annotation_comment
            )
        )
        @test annotation_test isa BM.BaseModelicaAnnotation
        @test BM.eval_AST(annotation_test) === nothing
    end

    @testset "Newton Cooling" begin
        newton_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "NewtonCoolingBase.bmo"
        )
        newton_cooling = BM.parse_file_julia(newton_path)
        @test newton_cooling isa BM.BaseModelicaPackage
        newton_system = BM.baseModelica_to_ModelingToolkit(newton_cooling)
        @test newton_system isa System
        @test parse_basemodelica(newton_path, parser = :julia) isa System
    end

    @testset "Negative Variables" begin
        # Test parsing with negative variables (issue #35)
        negative_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "NegativeVariable.bmo"
        )
        negative_package = BM.parse_file_julia(negative_path)
        @test negative_package isa BM.BaseModelicaPackage
        negative_system = BM.baseModelica_to_ModelingToolkit(negative_package)
        @test negative_system isa System
        @test parse_basemodelica(negative_path, parser = :julia) isa System
    end

    @testset "Experiment Annotation" begin
        # Test experiment annotation parsing (issue #38)
        experiment_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "Experiment.bmo"
        )
        experiment_package = BM.parse_file_julia(experiment_path)
        @test experiment_package isa BM.BaseModelicaPackage
        experiment_system = BM.baseModelica_to_ModelingToolkit(experiment_package)
        @test experiment_system isa System
        @test parse_basemodelica(experiment_path, parser = :julia) isa System
    end

    @testset "Parameter with Modifiers" begin
        # Test parameter with modifiers (issue #49)
        param_modifiers_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "ParameterWithModifiers.bmo"
        )
        param_modifiers_package = BM.parse_file_julia(param_modifiers_path)
        @test param_modifiers_package isa BM.BaseModelicaPackage
        param_modifiers_system = BM.baseModelica_to_ModelingToolkit(param_modifiers_package)
        @test param_modifiers_system isa System
        @test parse_basemodelica(param_modifiers_path, parser = :julia) isa System
    end

    @testset "If Equations" begin
        if_equations_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "IfEquation.bmo"
        )
        if_equations_package = BM.parse_file_julia(if_equations_path)
        @test if_equations_package isa BM.BaseModelicaPackage
        if_equations_system = BM.baseModelica_to_ModelingToolkit(if_equations_package)
        @test if_equations_system isa System
        @test parse_basemodelica(if_equations_path, parser = :julia) isa System
    end

    @testset "Inline If Expression (issue #39)" begin
        inline_if_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "InlineIf.bmo"
        )
        inline_if_package = BM.parse_file_julia(inline_if_path)
        @test inline_if_package isa BM.BaseModelicaPackage
        inline_if_system = BM.baseModelica_to_ModelingToolkit(inline_if_package)
        @test inline_if_system isa System
        @test parse_basemodelica(inline_if_path, parser = :julia) isa System
    end

    @testset "Nested Inline If Expression (issue #39)" begin
        nested_if_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "InlineIfNested.bmo"
        )
        nested_if_package = BM.parse_file_julia(nested_if_path)
        @test nested_if_package isa BM.BaseModelicaPackage
        nested_if_system = BM.baseModelica_to_ModelingToolkit(nested_if_package)
        @test nested_if_system isa System
        @test parse_basemodelica(nested_if_path, parser = :julia) isa System
    end

    @testset "Inline If-ElseIf Expression (issue #39)" begin
        elseif_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "InlineIfElseIf.bmo"
        )
        elseif_package = BM.parse_file_julia(elseif_path)
        @test elseif_package isa BM.BaseModelicaPackage
        elseif_system = BM.baseModelica_to_ModelingToolkit(elseif_package)
        @test elseif_system isa System
        @test parse_basemodelica(elseif_path, parser = :julia) isa System
    end

    @testset "If-ElseIf-Else Equation (issue #41)" begin
        ifeq_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "IfElseIfEquation.bmo"
        )
        ifeq_package = BM.parse_file_julia(ifeq_path)
        @test ifeq_package isa BM.BaseModelicaPackage
        ifeq_system = BM.baseModelica_to_ModelingToolkit(ifeq_package)
        @test ifeq_system isa System
        @test parse_basemodelica(ifeq_path, parser = :julia) isa System
    end

    @testset "No Else If Equation (issue #41)" begin
        noelse_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "NoElse.bmo"
        )
        noelse_package = BM.parse_file_julia(noelse_path)
        @test noelse_package isa BM.BaseModelicaPackage
        noelse_system = BM.baseModelica_to_ModelingToolkit(noelse_package)
        @test noelse_system isa System
        @test parse_basemodelica(noelse_path, parser = :julia) isa System
    end

    @testset "When Equation" begin
        when_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "WhenEquation.bmo"
        )
        when_package = BM.parse_file_julia(when_path)
        @test when_package isa BM.BaseModelicaPackage
        when_system = BM.baseModelica_to_ModelingToolkit(when_package)
        @test when_system isa System
        @test !isempty(ModelingToolkit.continuous_events(when_system))
    end

    @testset "Declaration Equation" begin
        decl_eq_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "DeclarationEquation.bmo"
        )
        decl_eq_package = BM.parse_file_julia(decl_eq_path)
        @test decl_eq_package isa BM.BaseModelicaPackage
        decl_eq_system = BM.baseModelica_to_ModelingToolkit(decl_eq_package)
        @test decl_eq_system isa System
    end

    @testset "Create ODEProblem" begin
        # Test create_odeproblem with Experiment annotation
        experiment_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "Experiment.bmo"
        )

        prob = BM.create_odeproblem(experiment_path, parser = :julia)
        @test prob isa ODEProblem

        # Check that tspan was set from annotation
        @test prob.tspan[1] == 0.0  # StartTime
        @test prob.tspan[2] == 2.0  # StopTime

        # Check that reltol and saveat were set from annotation
        @test prob.kwargs[:reltol] == 1.0e-6  # Tolerance
        @test prob.kwargs[:saveat] == 0.004  # Interval

        # Test parse_experiment_annotation directly
        experiment_package = BM.parse_file_julia(experiment_path)
        annotation = experiment_package.model.long_class_specifier.composition.annotation
        @test !isnothing(annotation)

        exp_params = BM.parse_experiment_annotation(annotation)
        @test !isnothing(exp_params)
        @test exp_params.StartTime == 0.0
        @test exp_params.StopTime == 2.0
        @test exp_params.Tolerance == 1.0e-6
        @test exp_params.Interval == 0.004

        # Test with model without annotation
        newton_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "NewtonCoolingBase.bmo"
        )
        prob_no_annotation = BM.create_odeproblem(newton_path, parser = :julia)
        @test prob_no_annotation isa ODEProblem
        # Should use default tspan
        @test prob_no_annotation.tspan[1] == 0.0
        @test prob_no_annotation.tspan[2] == 1.0

        # Test that user can override annotation values
        prob_override = BM.create_odeproblem(experiment_path, parser = :julia, reltol = 1.0e-8, saveat = 0.01)
        @test prob_override isa ODEProblem
        @test prob_override.kwargs[:reltol] == 1.0e-8  # User override
        @test prob_override.kwargs[:saveat] == 0.01  # User override
        @test prob_override.tspan[2] == 2.0  # Still from annotation
    end

    @testset "Cauer Low Pass Filters" begin
        # Test CauerLowPassAnalog
        cauer_analog_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "CauerLowPassAnalog.bmo"
        )
        cauer_analog_package = BM.parse_file_julia(cauer_analog_path)
        @test cauer_analog_package isa BM.BaseModelicaPackage
        cauer_analog_system = BM.baseModelica_to_ModelingToolkit(cauer_analog_package)
        @test cauer_analog_system isa System
        @test parse_basemodelica(cauer_analog_path, parser = :julia) isa System

        # Test that initial conditions (fixed=true) are set correctly
        # MTK v11 replaced defaults with initial_conditions and bindings
        @test !isempty(ModelingToolkit.initial_conditions(cauer_analog_system)) ||
            !isempty(ModelingToolkit.bindings(cauer_analog_system))

        # Test that guess values (fixed=false or no fixed) are set correctly
        @test !isempty(ModelingToolkit.guesses(cauer_analog_system))

        # Test CauerLowPassAnalogSine
        cauer_sine_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "CauerLowPassAnalogSine.bmo"
        )
        cauer_sine_package = BM.parse_file_julia(cauer_sine_path)
        @test cauer_sine_package isa BM.BaseModelicaPackage
        cauer_sine_system = BM.baseModelica_to_ModelingToolkit(cauer_sine_package)
        @test cauer_sine_system isa System
        @test parse_basemodelica(cauer_sine_path, parser = :julia) isa System

        # Test CauerLowPassAnalogSineNoAssert
        cauer_sine_noassert_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "CauerLowPassAnalogSineNoAssert.bmo"
        )
        cauer_sine_noassert_package = BM.parse_file_julia(cauer_sine_path)
        @test cauer_sine_noassert_package isa BM.BaseModelicaPackage
        cauer_sine_noassert_system = BM.baseModelica_to_ModelingToolkit(cauer_sine_noassert_package)
        @test cauer_sine_noassert_system isa System
        @test parse_basemodelica(cauer_sine_noassert_path, parser = :julia) isa System
    end
end
