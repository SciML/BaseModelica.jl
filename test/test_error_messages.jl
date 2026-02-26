using Test
using BaseModelica
using ParserCombinator

# Note: These tests are specific to the Julia ParserCombinator parser
# They test error message formatting and location reporting
# ANTLR parser has its own error reporting mechanism

@testset "Error Message Improvements (Julia Parser)" begin
    # Test that error messages include line and column information
    @testset "Basic Error Location" begin
        invalid_modelica = """package Test
          model TestModel
            Real x;
          equation
            x = invalid syntax here;
          end TestModel;
        end Test;"""

        # This should throw an error during parsing
        error_thrown = false
        try
            BaseModelica.julia_parse_str(invalid_modelica)
        catch e
            error_thrown = true
            @test isa(e, ParserCombinator.ParserException)
            @test occursin("Failed to parse BaseModelica at line", e.msg)
            @test occursin("column", e.msg)
            @test occursin("Error context:", e.msg)
            @test occursin("→", e.msg)  # Check for the arrow pointing to error line
            @test occursin("^", e.msg)  # Check for the caret pointer
        end
        @test error_thrown
    end

    # Test with annotation parsing (from issue #45 - now fixed, should parse successfully)
    @testset "Annotation Parsing" begin
        annotation_modelica = """package 'Experiment'
          model 'Experiment'
            Real 'x';
          equation
            der('x') = 'x';
            annotation(experiment(StartTime = 0, StopTime = 2.0, Tolerance = 1e-06, Interval = 0.004));
          end 'Experiment';
        end 'Experiment';"""

        # This should now parse successfully since annotation support was added
        result = BaseModelica.julia_parse_str(annotation_modelica)
        @test isa(result, BaseModelica.BaseModelicaPackage)
    end

    # Test error at the beginning of file
    @testset "Error at Beginning" begin
        beginning_error = """invalid_start
        package Test
          model TestModel
            Real x;
          end TestModel;
        end Test;"""

        error_thrown = false
        try
            BaseModelica.julia_parse_str(beginning_error)
        catch e
            error_thrown = true
            @test occursin("line 1", e.msg)
        end
        @test error_thrown
    end

    # Test error in equation section
    @testset "Equation Section Error" begin
        equation_error = """package Test
          model TestModel
            Real x;
            Real y;
          equation
            x = y +;  // Missing right operand
          end TestModel;
        end Test;"""

        error_thrown = false
        try
            BaseModelica.julia_parse_str(equation_error)
        catch e
            error_thrown = true
            # Should show error location and context
            @test occursin("Failed to parse BaseModelica at line", e.msg)
            @test occursin("Error context:", e.msg)
        end
        @test error_thrown
    end

    # Test that parse_file_julia includes filename
    @testset "File Error Messages" begin
        # Create a temporary file with invalid content
        temp_file = tempname() * ".bmo"
        error_thrown = false
        try
            open(temp_file, "w") do f
                write(
                    f, """package Test
                      model TestModel
                        Real x
                        // Missing semicolon above
                      end TestModel;
                    end Test;"""
                )
            end

            try
                BaseModelica.parse_file_julia(temp_file)
            catch e
                error_thrown = true
                @test occursin("Error in file:", e.msg)
                @test occursin(temp_file, e.msg)
            end
            @test error_thrown
        finally
            rm(temp_file, force = true)
        end
    end

    # Test helper functions directly
    @testset "Helper Functions" begin
        test_string = "line one\nline two\nline three"

        # Test get_position_info
        line, col = BaseModelica.get_position_info(test_string, 1)
        @test line == 1
        @test col == 2  # Position 1 is second character of first line

        line, col = BaseModelica.get_position_info(test_string, 10)  # Just after newline
        @test line == 2
        @test col == 2  # Position 10 is at 'i' in "line two"

        # Test format_error_context
        context = BaseModelica.format_error_context(test_string, 10)
        @test occursin("line one", context)
        @test occursin("→ line two", context)
        @test occursin("line three", context)
        @test occursin("^", context)  # Should have error pointer
    end

    # Test that valid code doesn't trigger error messages
    @testset "Valid Code Parsing" begin
        valid_modelica = """package Test
          model TestModel
            Real x;
          equation
            der(x) = -x;
          end TestModel;
        end Test;"""

        # Should not throw any exceptions
        result = BaseModelica.julia_parse_str(valid_modelica)
        @test isa(result, BaseModelica.BaseModelicaPackage)
    end
end
