using BaseModelica, Aqua
@testset "Aqua" begin
    Aqua.find_persistent_tasks_deps(BaseModelica)
    Aqua.test_ambiguities(BaseModelica, recursive = false)
    Aqua.test_deps_compat(BaseModelica)
    Aqua.test_piracies(BaseModelica)
    Aqua.test_project_extras(BaseModelica)
    Aqua.test_stale_deps(BaseModelica)
    Aqua.test_unbound_args(BaseModelica)
    Aqua.test_undefined_exports(BaseModelica)
end
