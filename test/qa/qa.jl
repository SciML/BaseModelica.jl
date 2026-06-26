using SciMLTesting, BaseModelica, Test
using JET

run_qa(
    BaseModelica;
    explicit_imports = true,
    # MLStyle's @match expands to ambiguous-looking method tables; the original QA
    # ran ambiguities non-recursively, so keep that.
    #
    # persistent_tasks is disabled because Aqua's probe loads the package in a
    # freshly generated wrapper environment built from this Project.toml alone, and
    # `using BaseModelica` there drives PythonCall's `__init__` -> CondaPkg resolve.
    # That precompile takes far longer than the probe's load window, so the wrapper
    # subprocess exits before signalling and Aqua reports "done.log was not created,
    # but precompilation exited" — a false positive. The package defines no
    # `__init__`/`@async`/`Timer`, so it leaves no persistent tasks of its own. The
    # pre-run_qa qa.jl never asserted this check (it only called the non-asserting
    # `find_persistent_tasks_deps`); this keeps that scope.
    aqua_kwargs = (; ambiguities = (; recursive = false), persistent_tasks = false),
    ei_kwargs = (;
        all_qualified_accesses_via_owners = (;
            # All re-exported by ModelingToolkit/Symbolics from their base libs
            # (ModelingToolkitBase / SymbolicIndexingInterface / SymbolicUtils);
            # owner-vs-access mismatch only.
            ignore = (
                :SymbolicContinuousCallback,  # owned by ModelingToolkitBase
                :SymbolicDiscreteCallback,    # owned by ModelingToolkitBase
                :getname,                     # owned by SymbolicIndexingInterface
                :setdefault,                  # owned by ModelingToolkitBase
                :setguess,                    # owned by ModelingToolkitBase
                :unwrap,                      # owned by SymbolicUtils
            ),
        ),
        all_qualified_accesses_are_public = (;
            ignore = (
                :getname,                     # ModelingToolkit (re-export of SymbolicIndexingInterface, still non-public)
                :None,                        # PythonCall.pybuiltins
                :hasattr,                     # PythonCall.pybuiltins
                :len,                         # PythonCall.pybuiltins
            ),
        ),
    ),
    # The module relies on many implicit imports from heavy `using` of
    # ModelingToolkit/ParserCombinator/PythonCall/MLStyle/CondaPkg; making them
    # explicit is a large refactor tracked in
    # https://github.com/SciML/BaseModelica.jl/issues/139.
    ei_broken = (:no_implicit_imports,)
)
