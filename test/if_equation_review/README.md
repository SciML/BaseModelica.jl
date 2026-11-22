These fixtures cover the if-equation probes from reviews `6ca1b4a3`,
`ac4593fe` and the re-review at `9d51c3e8`. The available review snapshots are
`5640278420bc74040928d01eaa0115782f5114a7:outputs/REVIEW.md` and
`e6718305:outputs/REVIEW.md`, followed by
`9d51c3e8b9be4013afd26842163e62041b61b813:outputs/REVIEW.md`.

All 41 `outputs/repros/*.bmo` files from the first snapshot are copied byte for
byte. Another 18 files (I1–I4, I11–I14, I16–I17, I19–I20, P1 variants/controls,
K1/K3) are copied from the second snapshot. I10, I15, K2, K4 and R7 were listed
in its review/results but absent from its tree; their minimal shapes are
reconstructed here. S1d, U1, U2, U5 and N11 are copied byte for byte from the
third snapshot. D1–D4 and S6–S9 are additional focused controls. There are 77
fixtures in this directory. Nothing replaces
or modifies the 15 existing accepted fixtures in `../if_equations`.

Reference provenance
--------------------

References were rerun using OpenModelica 1.27.1~2-g6db4671, DASSL,
tolerance 1e-10, t=0..1, 1000 intervals. Each fixture was loaded in a separate
OMC invocation with `loadFile("<absolute fixture path>")`, then
`simulate(P.M, stopTime=1, numberOfIntervals=1000, tolerance=1e-10,
outputFormat="csv")` and `getErrorString()`. The checks sample t=0, .1, .375,
.75 and 1, avoiding the event-side ambiguity at t=.25/.5. Formulae below match
those CSV samples. Logs/CSV files are rebuildable scratch under `outputs/`;
they are not test dependencies. B13 was additionally translated with p=false
(500 intervals), giving r.a(0)=1 and r.b(0)=2. The N1 variant with additional
unreachable elseif/else rows after the first literal true was also accepted
by OMC and produced the same y: 1 → 2 result.

In regular probes with an independent x, x(t)=exp(-t). In the following table,
`before → after` means t<.5 versus t>.5; e means exp(-t).

| Probe | OMC result / test expectation |
| --- | --- |
| B1, B9, N1 | y: 1 → 2 |
| B2 | y: exp(-t) → 2 |
| B2b | x=exp(-t) until .5, then exp(-.5)+t-.5 |
| B3, B7 | y: {1,2} → {3,4} |
| B4 | y: {1,2,5} → {3,4,6} |
| B4b | y={3,7}; its default parameter value is the valid branch; select at load with one warning naming b, and retain no b in the raw equations; loading b=true rejects the conflicting y[2] constraints |
| B5, B5b | {r.a,r.b}: {1,2} → {3,4}, including swapped field order |
| B6 | y=1 before .25, 2 from .25 to .5, 3 afterward |
| B6b, B6c | y: 1 → 3; z: 6 → 7 |
| B8, B8b | OMC accepts, d: 0 → 1; nested when deliberately UnsupportedFeatureError here |
| B8c | OMC rejects dynamic if around when; UnsupportedFeatureError |
| B10 | y=2, z=1; unequal counts require parameter selection |
| B11 | OMC rejects overdetermined system, even though duplicate z=6 agrees; raw system retains all 4 rows and compilation rejects |
| B11b | OMC rejects overdetermined system; unequal dynamic counts reject before simplification |
| B12 | y[i]=e until .5, then exp(-.5)+i*(t-.5), i=1,2 |
| B13 | {r.a,r.b}={3,4}e; remake(p=false) gives {1,2}e, no structural warning |
| E1 | y=1, one structural warning naming p and q |
| E3, E4 | y=2 |
| E13 | y=2e, z=1; one structural warning naming initType and initType2 |
| E2, E5–E8, E10–E12 | OMC rejects underdetermined systems; UnsupportedFeatureError for unresolved unbalanced conditions |
| E9 | OMC uses parameter start p=1 (y=1), with missing-binding warning; intentionally unsupported here, never use a start as a binding |
| I21, I22 | x=2e, z=-1, including residual initial equations |
| I23 | x=2e, w=t-.5 |
| L3, L5 | y={1,2,4}e; inactive y[0] is never evaluated |
| L4 | y[i,i]=e; y[i,j]=10i+j for i≠j |
| S1d | x=y=e, including x(0)=1 without fixed=true; differing targets select at load with a warning naming b |
| U5 | x=e, y=exp(-2t), both starting at 1 without fixed=true; differing targets select at load with a warning naming b |
| U1, U2, D1 | x=e until .5, then exp(-.5)+t-.5; y: 1 → 2; raw der(x) stays explicit regardless of row order, side or linear coefficient |
| N11 | y: 1 → 2, z=1; a dead false branch with two rows cannot affect balancing |
| S6, S7 | x=e, y=2e; constant/Evaluate conditions select at load even with equal counts and targets; S7 keeps the existing Evaluate=true warning |
| S8 | x={1,1}e, y=e; structural size condition selects at load with equal counts and targets |
| S9 | x=y=e; same targets remain tunable without warning, remake(b=false) gives x=exp(-2t), y=2exp(-2t) |
| D2–D4 | Explicitly unsupported dynamic rows: missing derivative, nonlinear derivative, or coupled derivatives; rejection occurs before MTK compilation |

The third review's OMC output supplies the S1d/U1/U2/U5/N11 expectations.
The new D1 and S6–S9 controls were also run independently with OMC 1.27.1,
DASSL, tolerance 1e-10, using the same sample times above. S9 was additionally
translated with its source binding changed to b=false to check the remake
expectations. D2–D4 deliberately
reject forms outside the supported explicit derivative lowering. OMC simulates
D2/D3; D2 freezes after the switch rather than satisfying the changed branch,
and D3 follows the negative root of its squared derivative. D4's OMC simulation
times out after producing a partial CSV. None of these results supplies a
numeric expectation for this loader. Logs and CSVs remain rebuildable scratch
under `outputs/test-worker-omc/`.

Earlier-review inventory
------------------------

Every initial probe I1–I20 is accounted for below. These newly added checks
fill the exact-fixture gaps rather than relying on roughly similar synthetic
models. Existing accepted-fixture tests run both parsers and both array modes,
as do all new checks in `../test_if_equation_review.jl`.

| Probe(s) | Coverage and OMC reference |
| --- | --- |
| T1 | Existing `test_if_equation_semantics.jl` / `../if_equations`: p=-1 gives x(0)=2; remake(p=1) gives 1 |
| I1 | New exact dependent forward-reference fixture: x=3e |
| I2 | New exact Evaluate/elseif fixture: x=7e |
| I3 | New exact structural-size fixture: OMC x={3,5}e; inspect raw x[2]=5, x[1] has guess 3 and no default |
| I4 | New exact enum-alias NoInit fixture: y=1+e |
| I5, I7–I9, I18 | Existing `test_if_equation_semantics.jl` / `../if_equations`: x=e |
| I6 | Same existing coverage: x=2e |
| I10 | Reconstructed initial() no-else; OMC x=3e, BaseModelica explicitly unsupported |
| I11 | New exact fixed=false dependency: OMC x=3e; unbalanced unresolved parameter explicitly unsupported |
| I12 | New exact Boolean-array fixture: OMC x={3,2}e; inspect raw x[2]=2, x[1] guess 3, no invented default |
| I13 | New exact selected pre(b) fixture: x=t, b=false before .5 and true afterward |
| I14 | New exact array-parameter elseif fixture: x={7,8}e |
| I15 | Reconstructed unbound parameter, start=-1: OMC x=3e; unsupported here rather than evaluating a start |
| I16 | New exact nested fixture: x=3e, y=6e |
| I17 | New exact function-bound parameter fixture: x=3e |
| I19 | New exact discrete-enum fixture: OMC x=2e, s: E.b → E.a; current backend explicitly rejects non-time-dependent enum event parameter |
| I20 | New exact enum variable with constant binding: x=3e |
| P1 | New exact scalar no-else and no-if control: x=3e. Existing `test_initial_if_structural.jl` also covers variants |
| P1 zero derivative / array | New exact fixtures: OMC x=3 (each element). Inspect raw absence of initial equations, guesses=3, no default |
| K1–K4 | New controls: OMC K1={3,3}e, K2={3,2}e, K3=3, K4={3,2}e. K1/K2/K3 use raw initialization checks; K4 solves |
| L1, L2, R1–R6 | Existing `test_if_equation_semantics.jl` / `../if_equations`: L1={1,2,4}e; L2/R1/R2/R3/R6 y=2; R4 y={2,3}; R5 x=1+t |
| R7 | Reconstructed parameter elseif/no-else control: y=2, x=e |

The earlier review's C1 and D1–D4 concern function field access and dimension
conversion, outside this if-equation change. They already have coverage in
`test_call_field_access.jl` and `test_dimension_conversions.jl`. No initial or
regular if-equation probe is left unaccounted for.

Raw initialization assertions are intentional for underdetermined array/zero
derivative controls: the review documented MTK filling an unconstrained array element
with zero, and failing to initialize der(x)=0. These tests check preservation
of the selected constraints, starts and guesses, never those incorrect numeric
results. Ordinary scalar initial assignments may be represented as variable
defaults; residual assignments remain initialization equations.

Isolated validation
-------------------

Set `BASEMODELICA_IF_REVIEW_CASE` to a full fixture stem and run
`timeout 180 julia --project=<test environment> --startup-file=no
 test/test_if_equation_review.jl`. Each invocation handles exactly one model,
through julia/antlr × scalarize/keep on the main thread. Optional
`BASEMODELICA_IF_REVIEW_PARSER` and `BASEMODELICA_IF_REVIEW_ARRAYS` filters select
one combination. Invalid filter values throw, rather than silently running no
assertions. Without filters the file can be included by the normal test suite.
