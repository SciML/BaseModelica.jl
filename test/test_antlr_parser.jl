using Test
using BaseModelica
using ModelingToolkit
using OrdinaryDiffEq

BM = BaseModelica

@testset "ANTLR Parser Tests" begin
    @testset "Newton Cooling" begin
        newton_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "NewtonCoolingBase.bmo"
        )
        newton_cooling = BM.parse_file_antlr(newton_path)
        @test newton_cooling isa BM.BaseModelicaPackage
        newton_system = BM.baseModelica_to_ModelingToolkit(newton_cooling)
        @test newton_system isa System
        @test parse_basemodelica(newton_path, parser = :antlr) isa System
    end

    @testset "Negative Variables" begin
        negative_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "NegativeVariable.bmo"
        )
        negative_package = BM.parse_file_antlr(negative_path)
        @test negative_package isa BM.BaseModelicaPackage
        negative_system = BM.baseModelica_to_ModelingToolkit(negative_package)
        @test negative_system isa System
        @test parse_basemodelica(negative_path, parser = :antlr) isa System
    end

    @testset "Experiment Annotation" begin
        experiment_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "Experiment.bmo"
        )
        experiment_package = BM.parse_file_antlr(experiment_path)
        @test experiment_package isa BM.BaseModelicaPackage
        experiment_system = BM.baseModelica_to_ModelingToolkit(experiment_package)
        @test experiment_system isa System
        @test parse_basemodelica(experiment_path, parser = :antlr) isa System
    end

    @testset "Parameter with Modifiers" begin
        param_modifiers_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "ParameterWithModifiers.bmo"
        )
        param_modifiers_package = BM.parse_file_antlr(param_modifiers_path)
        @test param_modifiers_package isa BM.BaseModelicaPackage
        param_modifiers_system = BM.baseModelica_to_ModelingToolkit(param_modifiers_package)
        @test param_modifiers_system isa System
        @test parse_basemodelica(param_modifiers_path, parser = :antlr) isa System
    end

    @testset "If Equations" begin
        if_equations_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "IfEquation.bmo"
        )
        if_equations_package = BM.parse_file_antlr(if_equations_path)
        @test if_equations_package isa BM.BaseModelicaPackage
        if_equations_system = BM.baseModelica_to_ModelingToolkit(if_equations_package)
        @test if_equations_system isa System
        @test parse_basemodelica(if_equations_path, parser = :antlr) isa System
    end

    @testset "Inline If Expression (issue #39)" begin
        inline_if_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "InlineIf.bmo"
        )
        inline_if_package = BM.parse_file_antlr(inline_if_path)
        @test inline_if_package isa BM.BaseModelicaPackage
        inline_if_system = BM.baseModelica_to_ModelingToolkit(inline_if_package)
        @test inline_if_system isa System
        @test parse_basemodelica(inline_if_path, parser = :antlr) isa System
    end

    @testset "Nested Inline If Expression (issue #39)" begin
        nested_if_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "InlineIfNested.bmo"
        )
        nested_if_package = BM.parse_file_antlr(nested_if_path)
        @test nested_if_package isa BM.BaseModelicaPackage
        nested_if_system = BM.baseModelica_to_ModelingToolkit(nested_if_package)
        @test nested_if_system isa System
        @test parse_basemodelica(nested_if_path, parser = :antlr) isa System
    end

    @testset "Inline If-ElseIf Expression (issue #39)" begin
        elseif_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "InlineIfElseIf.bmo"
        )
        elseif_package = BM.parse_file_antlr(elseif_path)
        @test elseif_package isa BM.BaseModelicaPackage
        elseif_system = BM.baseModelica_to_ModelingToolkit(elseif_package)
        @test elseif_system isa System
        @test parse_basemodelica(elseif_path, parser = :antlr) isa System
    end

    @testset "If-ElseIf-Else Equation (issue #41)" begin
        ifeq_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "IfElseIfEquation.bmo"
        )
        ifeq_package = BM.parse_file_antlr(ifeq_path)
        @test ifeq_package isa BM.BaseModelicaPackage
        ifeq_system = BM.baseModelica_to_ModelingToolkit(ifeq_package)
        @test ifeq_system isa System
        @test parse_basemodelica(ifeq_path, parser = :antlr) isa System
    end

    @testset "No Else If Equation (issue #41)" begin
        noelse_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "NoElse.bmo"
        )
        noelse_package = BM.parse_file_antlr(noelse_path)
        @test noelse_package isa BM.BaseModelicaPackage
        noelse_system = BM.baseModelica_to_ModelingToolkit(noelse_package)
        @test noelse_system isa System
        @test parse_basemodelica(noelse_path, parser = :antlr) isa System
    end

    @testset "Cauer Low Pass Filters" begin
        # Test CauerLowPassAnalog
        cauer_analog_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "CauerLowPassAnalog.bmo"
        )
        cauer_analog_package = BM.parse_file_antlr(cauer_analog_path)
        @test cauer_analog_package isa BM.BaseModelicaPackage
        cauer_analog_system = BM.baseModelica_to_ModelingToolkit(cauer_analog_package)
        @test cauer_analog_system isa System
        @test parse_basemodelica(cauer_analog_path, parser = :antlr) isa System

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
        cauer_sine_package = BM.parse_file_antlr(cauer_sine_path)
        @test cauer_sine_package isa BM.BaseModelicaPackage
        cauer_sine_system = BM.baseModelica_to_ModelingToolkit(cauer_sine_package)
        @test cauer_sine_system isa System
        @test parse_basemodelica(cauer_sine_path, parser = :antlr) isa System

        # Test CauerLowPassAnalogSineNoAssert
        cauer_sine_noassert_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "CauerLowPassAnalogSineNoAssert.bmo"
        )
        cauer_sine_noassert_package = BM.parse_file_antlr(cauer_sine_noassert_path)
        @test cauer_sine_noassert_package isa BM.BaseModelicaPackage
        cauer_sine_noassert_system = BM.baseModelica_to_ModelingToolkit(cauer_sine_noassert_package)
        @test cauer_sine_noassert_system isa System
        @test parse_basemodelica(cauer_sine_noassert_path, parser = :antlr) isa System
    end

    @testset "Chua Circuits" begin
        # Test ChuaCircuit
        chua_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "ChuaCircuit.bmo"
        )
        chua_package = BM.parse_file_antlr(chua_path)
        @test chua_package isa BM.BaseModelicaPackage
        chua_system = BM.baseModelica_to_ModelingToolkit(chua_package)
        @test chua_system isa System
        @test parse_basemodelica(chua_path, parser = :antlr) isa System

        # Test ChuaCircuitNoAssert
        chua_noassert_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "ChuaCircuitNoAssert.bmo"
        )
        chua_noassert_package = BM.parse_file_antlr(chua_noassert_path)
        @test chua_noassert_package isa BM.BaseModelicaPackage
        chua_noassert_system = BM.baseModelica_to_ModelingToolkit(chua_noassert_package)
        @test chua_noassert_system isa System
        @test parse_basemodelica(chua_noassert_path, parser = :antlr) isa System
    end

    @testset "Math Functions" begin
        # Test model with cos, tanh, atan2
        math_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "MathFunctions.bmo"
        )
        math_package = BM.parse_file_antlr(math_path)
        @test math_package isa BM.BaseModelicaPackage
        math_system = BM.baseModelica_to_ModelingToolkit(math_package)
        @test math_system isa System
        @test parse_basemodelica(math_path, parser = :antlr) isa System
    end

    @testset "Math Functions Extended" begin
        # Test model with exp, sqrt, max, noEvent, sign, log, abs
        math_ext_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "MathFunctionsExtended.bmo"
        )
        math_ext_package = BM.parse_file_antlr(math_ext_path)
        @test math_ext_package isa BM.BaseModelicaPackage
        math_ext_system = BM.baseModelica_to_ModelingToolkit(math_ext_package)
        @test math_ext_system isa System
        @test parse_basemodelica(math_ext_path, parser = :antlr) isa System
    end

    @testset "Function Map Coverage" begin
        # Verify all expected BaseModelica built-in functions are in the map
        fmap = BM.function_map

        # Derivative operator
        @test haskey(fmap, :der)

        # Elementary math (Spec 3.7.3)
        for f in [
                :sin, :cos, :tan, :asin, :acos, :atan, :atan2,
                :sinh, :cosh, :tanh, :exp, :log, :log10,
            ]
            @test haskey(fmap, f)
        end

        # Numeric functions (Spec 3.7.1)
        for f in [:abs, :sign, :sqrt, :min, :max]
            @test haskey(fmap, f)
        end

        # Event-triggering math (Spec 3.7.2)
        for f in [:div, :mod, :rem, :ceil, :floor, :integer]
            @test haskey(fmap, f)
        end

        # Special operators (Spec 3.7.4)
        for f in [:semiLinear, :homotopy]
            @test haskey(fmap, f)
        end

        # Event-related (Spec 3.7.5)
        for f in [:noEvent, :smooth]
            @test haskey(fmap, f)
        end

        # Assertion/termination
        for f in [:assert, :terminate]
            @test haskey(fmap, f)
        end
    end

    @testset "Minimal Valid File" begin
        minimal_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "MinimalValid.bmo"
        )
        minimal_package = BM.parse_file_antlr(minimal_path)
        @test minimal_package isa BM.BaseModelicaPackage
        # don't want to evaluate since there are no equations
    end

    @testset "Create ODEProblem with ANTLR Parser" begin
        # Test create_odeproblem with Experiment annotation
        experiment_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "Experiment.bmo"
        )

        prob = BM.create_odeproblem(experiment_path, parser = :antlr)
        @test prob isa ODEProblem

        # Check that tspan was set from annotation
        @test prob.tspan[1] == 0.0  # StartTime
        @test prob.tspan[2] == 2.0  # StopTime

        # Check that reltol and saveat were set from annotation
        @test prob.kwargs[:reltol] == 1.0e-6  # Tolerance
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
        @test exp_params.Tolerance == 1.0e-6
        @test exp_params.Interval == 0.004

        # Test with model without annotation
        newton_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "NewtonCoolingBase.bmo"
        )
        prob_no_annotation = BM.create_odeproblem(newton_path, parser = :antlr)
        @test prob_no_annotation isa ODEProblem
        # Should use default tspan
        @test prob_no_annotation.tspan[1] == 0.0
        @test prob_no_annotation.tspan[2] == 1.0

        # Verify annotation field is nothing for models without annotation
        newton_package = BM.parse_file_antlr(newton_path)
        newton_annotation = newton_package.model.long_class_specifier.composition.annotation
        @test isnothing(newton_annotation)

        # Test that user can override annotation values
        prob_override = BM.create_odeproblem(experiment_path, parser = :antlr, reltol = 1.0e-8, saveat = 0.01)
        @test prob_override isa ODEProblem
        @test prob_override.kwargs[:reltol] == 1.0e-8  # User override
        @test prob_override.kwargs[:saveat] == 0.01  # User override
        @test prob_override.tspan[2] == 2.0  # Still from annotation
    end

    @testset "Boolean Variable in If Expression (IfBoolCondition)" begin
        if_bool_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "IfBoolCondition.bmo"
        )
        if_bool_package = BM.parse_file_antlr(if_bool_path)
        @test if_bool_package isa BM.BaseModelicaPackage

        # Verify the Boolean variable was declared with ::Bool type
        composition = if_bool_package.model.long_class_specifier.composition
        bool_comp = first(
            c for c in composition.components if
                c.component_list[1].declaration.ident[1].name == "active"
        )
        @test bool_comp.type_specifier.type == "Boolean"

        # The model is purely algebraic (no ODEs), so mtkcompile produces no unknowns
        if_bool_system = BM.baseModelica_to_ModelingToolkit(if_bool_package)
        @test if_bool_system isa System
        @test isempty(ModelingToolkit.unknowns(if_bool_system))
    end

    @testset "When Equations (WhenEquation)" begin
        when_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "WhenEquation.bmo"
        )
        when_package = BM.parse_file_antlr(when_path)
        @test when_package isa BM.BaseModelicaPackage

        # Verify the when-equation was parsed into the AST
        # ANTLR parser returns bare BaseModelicaWhenEquation (not wrapped)
        composition = when_package.model.long_class_specifier.composition
        @test any(eq -> eq isa BM.BaseModelicaWhenEquation, composition.equations)

        when_system = BM.baseModelica_to_ModelingToolkit(when_package)
        @test when_system isa System
        @test parse_basemodelica(when_path, parser = :antlr) isa System
    end

    @testset "Unknown Parameter (fixed = false)" begin
        unknown_param_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "UnknownParameter.bmo"
        )
        unknown_param_package = BM.parse_file_antlr(unknown_param_path)
        @test unknown_param_package isa BM.BaseModelicaPackage

        unknown_param_system = BM.baseModelica_to_ModelingToolkit(unknown_param_package)
        @test unknown_param_system isa System

        # Verify p is a parameter (fixed=false makes it a free parameter solved at init)
        param_names = ModelingToolkit.getname.(ModelingToolkit.parameters(unknown_param_system))
        @test :p in param_names

        # Verify initialization equations were generated (from der(x)=0 and y=5 initial eqs)
        init_eqs = ModelingToolkit.initialization_equations(unknown_param_system)
        @test !isempty(init_eqs)

        @test parse_basemodelica(unknown_param_path, parser = :antlr) isa System
    end

    @testset "Simple Triac Circuit (when-equation with discrete parameters)" begin
        triac_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "SimpleTriacCircuit.bmo"
        )
        triac_package = BM.parse_file_antlr(triac_path)
        @test triac_package isa BM.BaseModelicaPackage

        # Verify the when-equation was parsed
        composition = triac_package.model.long_class_specifier.composition
        @test any(eq -> eq isa BM.BaseModelicaWhenEquation, composition.equations)

        triac_system = BM.baseModelica_to_ModelingToolkit(triac_package)
        @test triac_system isa System

        # Verify the when-equation produces a continuous callback
        @test !isempty(ModelingToolkit.continuous_events(triac_system))

        @test parse_basemodelica(triac_path, parser = :antlr) isa System
    end

    @testset "Characteristic Ideal Diodes" begin
        diode_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "CharacteristicIdealDiodes.bmo"
        )
        diode_package = BM.parse_file_antlr(diode_path)
        @test diode_package isa BM.BaseModelicaPackage

        diode_system = BM.baseModelica_to_ModelingToolkit(diode_package)
        @test diode_system isa System

        prob = ODEProblem(diode_system, [], (0.0, 1.0);
            missing_guess_value = ModelingToolkitBase.MissingGuessValue.Constant(0.0))
        sol = solve(prob)
        @test sol.retcode == ReturnCode.Success
    end

    @testset "Parameter String" begin
        param_string_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "ParameterString.bmo"
        )
        param_string_package = BM.parse_file_antlr(param_string_path)
        @test param_string_package isa BM.BaseModelicaPackage
        param_string_system = BM.baseModelica_to_ModelingToolkit(param_string_package)
        @test param_string_system isa System
        @test parse_basemodelica(param_string_path, parser = :antlr) isa System
    end

    @testset "Boolean Expression" begin
        bool_expr_path = joinpath(
            dirname(dirname(pathof(BM))), "test", "testfiles", "BooleanExpression.bmo"
        )
        bool_expr_package = BM.parse_file_antlr(bool_expr_path)
        @test bool_expr_package isa BM.BaseModelicaPackage
        bool_expr_system = BM.baseModelica_to_ModelingToolkit(bool_expr_package)
        @test bool_expr_system isa System
        @test parse_basemodelica(bool_expr_path, parser = :antlr) isa System
    end

end
