using SciMLTesting, BaseModelica, Test
using JET

run_qa(
    BaseModelica;
    explicit_imports = true,
    # MLStyle's @match expands to ambiguous-looking method tables; the original QA
    # ran ambiguities non-recursively, so keep that.
    aqua_kwargs = (; ambiguities = (; recursive = false)),
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
            # Non-public names of upstream deps; will go public as those base libs
            # mark their API.
            ignore = (
                :Constant,                    # ModelingToolkitBase.MissingGuessValue
                :ImperativeAffect,            # ModelingToolkitBase
                :isparameter,                 # ModelingToolkitBase
                :SymbolicContinuousCallback,  # ModelingToolkit (-> ModelingToolkitBase)
                :SymbolicDiscreteCallback,    # ModelingToolkit (-> ModelingToolkitBase)
                :getname,                     # ModelingToolkit (-> SymbolicIndexingInterface)
                :setdefault,                  # ModelingToolkit (-> ModelingToolkitBase)
                :setguess,                    # ModelingToolkit (-> ModelingToolkitBase)
                :unwrap,                      # Symbolics (-> SymbolicUtils)
                :value,                       # Symbolics
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
