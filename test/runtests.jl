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
        @safetestset "Precompile Workload Tests" include("test_precompile_workload.jl")
        return nothing
    end,
    qa = (; env = joinpath(@__DIR__, "qa"), body = qa_group),
    umbrellas = Dict("Quality" => ["QA"]),
    all = ["Core", "QA"],
)
