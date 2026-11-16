using SafeTestsets
using SciMLTesting

function qa_group()
    @safetestset "Quality Assurance" include(joinpath(@__DIR__, "qa", "qa.jl"))
    return nothing
end

run_tests(;
    core = function ()
        @safetestset "Julia Parser Tests" include("test_julia_parser.jl")
        @safetestset "ANTLR Parser Tests" include("test_antlr_parser.jl")
        @safetestset "Error Message Tests" include("test_error_messages.jl")
        @safetestset "Event Tests" include("test_events.jl")
        @safetestset "Event Regression Tests" include("test_event_regressions.jl")
        @safetestset "Event Iteration Regression Tests" include("test_event_iteration_regressions.jl")
        @safetestset "Event Step Value Tests" include("test_event_step_values.jl")
        @safetestset "Initialization Regression Tests" include("test_initialization_regressions.jl")
        @safetestset "Discrete Backend Tests" include("test_discrete_backends.jl")
        @safetestset "Function Tests" include("test_functions.jl")
        @safetestset "Array Tests" include("test_arrays.jl")
        @safetestset "Constants and Structural Parameter Tests" include("test_parameters.jl")
        @safetestset "Precompile Workload Tests" include("test_precompile_workload.jl")
        return nothing
    end,
    qa = (; env = joinpath(@__DIR__, "qa"), body = qa_group),
    umbrellas = Dict("Quality" => ["QA"]),
    all = ["Core", "QA"],
)
