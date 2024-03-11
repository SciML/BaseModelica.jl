using Test, SafeTestsets

@testset "BaseModelica" begin
    @safetestset "Quality Assurance" include("qa.jl")
    @safetestset "Parsing and Conversion Tests" begin
        using BaseModelica
        using ModelingToolkit
        BM = BaseModelica
        PC = BM.ParserCombinator

        @test PC.parse_one("3+ 5 -3/ 4*5+787 -10", BM.arithmetic_expression) |> length == 13
        @test only(PC.parse_one("output Real 'juice' \"juicy\";",BM.component_clause)) isa BM.BaseModelicaVariable
        @test only(PC.parse_one("Real 'juice' \"the real juice\";",BM.component_clause)) isa BM.BaseModelicaVariable
        @test only(PC.parse_one("parameter Real 'juice' = 45",BM.component_clause)) isa BM.BaseModelicaParameter
        @test only(PC.parse_one("parameter Real 'juice' = 45 \"juice 45\"",BM.component_clause)) isa BM.BaseModelicaParameter
        @test only(PC.parse_one("'locomotive' + 'creepers' = 'jeepers' \"holy cheepers\";",BM.equation)) isa BM.BaseModelicaEquation
        @test only(PC.parse_one("der('T') = 'x'",BM.equation)) isa BM.BaseModelicaEquation
        @test only(PC.parse_one("otherfun('x') = 'func_arg'", BM.equation)) isa BM.BaseModelicaEquation
        @test PC.parse_one("""
                    Real 'juice.juice' \"juicy\"; 
                    Real 'fruit' \"fruity\";
                    output Real 'output_fruit';
                    parameter Real 'doop' = 60;
                    equation
                    ('juice'+'fruit')*'blade' = 'puree';
                    'juicy' * 'fruit' = 'juicyfruit';
        """, BM.composition) |> length == 7
        @test PC.parse_one("""JuiceModel
                    Real 'juice.juice' \"juicy\"; 
                    Real 'fruit' \"fruity\";
                    output Real 'output_fruit';
                    parameter Real 'doop' = 60;
                    equation
                    ('juice'+'fruit')*'blade' = 'puree';
                    'juicy' * 'fruit' = 'juicyfruit';
                    end JuiceModel;
        """, BM.long_class_specifier) |> length == 10

        @test only(PC.parse_one("""
                package JuiceModel
                    model JuiceModel
                    Real 'juice.juice' \"juicy\"; 
                    Real 'fruit' \"fruity\";
                    Real 'T';
                    output Real 'output_fruit';
                    parameter Real 'soap' = 59;
                    equation
                    ('juice'+'fruit' + 100.0)*'blade' = 'puree' "smoothie?";
                    'juicy' * 'fruit' = 'juicyfruit';
                    initial equation
                    'juicy' = 1000;
                    'fruit' = 2000;
                    end JuiceModel;
                end JuiceModel;""",BM.base_modelica)) isa BM.BaseModelicaPackage

        newton_path = joinpath(
            pathof(BM), "test", "testfiles", "NewtonCoolingBase.mo")
        newton_cooling = BM.parse_file("testfiles/NewtonCoolingBase.mo")
        @test newton_cooling isa BM.BaseModelicaPackage
        newton_system = BM.baseModelica_to_ModelingToolkit(newton_cooling.model)
        @test newton_system isa ODESystem
        @test parse_basemodelica("testfiles/NewtonCoolingBase.mo") isa ODESystem
    end
end
