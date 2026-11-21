using Test, BaseModelica, ModelingToolkit, OrdinaryDiffEq

function derivative_input_member(sys, name)
    hasproperty(sys, Symbol(name)) && return getproperty(sys, Symbol(name))
    m = match(r"^(.*)\[([0-9]+)\]$", name)
    return getproperty(sys, Symbol(m[1]))[parse(Int, m[2])]
end

@testset "If-equation derivative inputs" begin
    for parser in (:julia, :antlr), arrays in (:scalarize, :keep)
        for file in sort(readdir(joinpath(@__DIR__, "derivative_inputs")))
            path = joinpath(@__DIR__, "derivative_inputs", file)
            @testset "$file $parser $arrays" begin
                if startswith(file, "A13_")
                    @test_throws r"coefficient is zero" parse_basemodelica(path; parser, arrays)
                    continue
                end
                sys = parse_basemodelica(path; parser, arrays)
                sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Rodas5P();
                    reltol = 1e-10, abstol = 1e-12)
                @test sol.retcode == ReturnCode.Success
                expected = if startswith(file, "A3f")
                    Dict("v" => t -> exp(-t), "w" => t -> 2exp(-t),
                        "a" => t -> t < 0.5 ? -3exp(-t) : 0.0, "z" => t -> 0.0)
                elseif startswith(file, "A3d")
                    Dict("x" => sin, "y" => t -> (t < 0.5 ? 1 : 2) * cos(t))
                elseif startswith(file, "A3")
                    multiplier = startswith(file, "A3b") || startswith(file, "A3e") ? 2 : 0
                    tunable = startswith(file, "A3c")
                    Dict("v" => t -> exp(-t),
                        "a" => t -> -(t < 0.5 || tunable ? 1 : multiplier) * exp(-t))
                elseif startswith(file, "A4b")
                    Dict("x" => t -> 1 + 2max(t - 0.5, 0),
                        "y" => t -> t < 0.5 ? 2 - t : 1 + t)
                elseif startswith(file, "A4_")
                    Dict("x" => t -> 2 - exp(-min(t, 0.5)) + max(t - 0.5, 0),
                        "y" => t -> exp(-t))
                elseif startswith(file, "A6c")
                    Dict("x[1]" => t -> 1 - min(t, 0.5) + 2max(t - 0.5, 0),
                        "x[2]" => t -> 1 - 2min(t, 0.5) + max(t - 0.5, 0))
                elseif startswith(file, "A8_")
                    Dict("x" => t -> exp(-min(t, 0.5)) + max(t - 0.5, 0),
                        "y" => t -> t < 0.5 ? -exp(-t) : 0.0)
                else # A9: -x = der(x) - 1 after the switch
                    Dict("x" => t -> t < 0.5 ? exp(-t) : 1 + (exp(-0.5) - 1) * exp(0.5 - t),
                        "y" => t -> t < 0.5 ? 1.0 : 2.0)
                end
                for (name, value) in expected, t in (0.0, 0.375, 0.75, 1.0)
                    @test sol(t; idxs = derivative_input_member(sys, name)) ≈ value(t) atol = 2e-8 rtol = 2e-7
                end
                if startswith(file, "A3c")
                    other = solve(BaseModelica.SciMLBase.remake(sol.prob; p = [sys.b => false]),
                        Rodas5P(); reltol = 1e-10, abstol = 1e-12)
                    @test other.retcode == ReturnCode.Success
                    @test other(0.375; idxs = sys.a) ≈ 0 atol = 1e-10
                    @test other(0.375; idxs = sys.v) ≈ exp(-0.375) rtol = 2e-7
                end
            end
        end
    end
end
