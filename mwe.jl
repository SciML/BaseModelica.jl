import BaseModelica as BM
using ModelingToolkit
using ModelingToolkitBase
using OrdinaryDiffEq
using Plots

diode_path = joinpath(dirname(pathof(BM)), "..", "test", "testfiles", "CharacteristicIdealDiodes.bmo")

diode_package = BM.parse_file_antlr(diode_path)
diode_system = BM.baseModelica_to_ModelingToolkit(diode_package)

prob = ODEProblem(diode_system, [], (0.0, 1.0);
    missing_guess_value = ModelingToolkitBase.MissingGuessValue.Constant(0.0))

sol = solve(prob)

println("Retcode: ", sol.retcode)

plot(sol, idxs = [
    diode_system.var"Ideal.v",
    diode_system.var"With_Ron_Goff.v",
    diode_system.var"With_Ron_Goff_Vknee.v",
], label = ["Ideal v" "With_Ron_Goff v" "With_Ron_Goff_Vknee v"],
    title = "Diode Voltages", xlabel = "time (s)", ylabel = "V")
