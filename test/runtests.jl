using Pkg
using SafeTestsets
using SciMLTesting

# The QA group runs Aqua/JET in the test/QA sub-env, but only on a non-prerelease
# Julia: those tools produce spurious reports on prerelease builds, so the whole group
# (env activation included) is a no-op on a `pre` matrix entry. A folder-discovery body
# cannot express this guard, so QA stays an explicit thunk. "Quality" is a legacy
# alias for QA.
function qa_group()
    isempty(VERSION.prerelease) || return nothing
    Pkg.activate(joinpath(@__DIR__, "qa"))
    Pkg.develop(PackageSpec(path = dirname(@__DIR__)))
    Pkg.instantiate()
    @safetestset "Quality Assurance" include(joinpath(@__DIR__, "qa", "qa.jl"))
    @safetestset "JET Static Analysis" include(joinpath(@__DIR__, "qa", "test_jet.jl"))
    return nothing
end

run_tests(;
    core = function ()
        @safetestset "Julia Parser Tests" include("test_julia_parser.jl")
        @safetestset "ANTLR Parser Tests" include("test_antlr_parser.jl")
        return @safetestset "Error Message Tests" include("test_error_messages.jl")
    end,
    qa = qa_group,
    umbrellas = Dict("Quality" => ["QA"]),
    # Original runtests ran QA/Quality only for those explicit GROUPs, never under
    # "All"; curate "All" to Core only to preserve that.
    all = ["Core"],
)
