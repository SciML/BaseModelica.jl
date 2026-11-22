These fixtures preserve the if-equation repros from the review at
`e6718305:outputs/REVIEW.md`. R2 and R6 were absent from the extracted repros:
R2 replaces R1's separate Boolean-parameter-false branches with an elseif
chain without else; R6 expresses R1's constraints as residual equations.

Reference values were checked with OpenModelica 1.27.1~2-g6db4671, Modelica
3.6, DASSL, tolerance 1e-10, over t=0..1. All 15 fixtures initialized and
simulated successfully.

| Fixture | Expected result |
| --- | --- |
| T1 | p=-1: x(0)=2; p=1: x(0)=1; x(t)=x(0) exp(-t) |
| I5, I7, I8, I9, I18 | x(0)=1; x(t)=exp(-t) |
| I6 | x(0)=2; x(t)=2 exp(-t) |
| L1 | y={1,2,4} exp(-t) |
| L2, R1, R2, R3, R6 | y=2 |
| R4 | y={2,3} |
| R5 | x(t)=1+t |

For the T1 reference, compile once for each p value: OMC evaluates p during
translation and refuses a simulation override. BaseModelica's regression
also checks its supported `remake(prob; p=[sys.p => 1.0])` path without
reloading the model. The Julia tests run every fixture through both parsers
and both array modes.
