using Test
using BaseModelica
using ModelingToolkit
using OrdinaryDiffEq

function step_model(body)
    path = tempname() * ".bmo"
    write(
        path, """//! base 0.1.0
        package 'Step'
          model 'Step'
        $body
          end 'Step';
        end 'Step';
        """
    )
    return path
end

function step_solution(body, parser; start = 0.0, stop = 1.0, alg = Tsit5())
    sys = parse_basemodelica(step_model(body); parser, discrete_backend = :mtk)
    prob = ODEProblem(sys, [], (start, stop))
    sol = isnothing(alg) ? solve(prob) : solve(prob, alg)
    @test sol.retcode == ReturnCode.Success
    return sys, sol
end

# A1-A3/B1-B2 are valid Modelica. Until the backend separates algebraic solves
# from reinit copies, reject them instead of returning the stale values from round 7.
function reject_step(body, parser, unknown; message = "plain read of non-state unknown `$unknown`")
    err = try
        parse_basemodelica(step_model(body); parser, discrete_backend = :mtk)
    catch e
        e
    end
    @test err isa BaseModelica.UnsupportedFeatureError
    @test occursin(message, sprint(showerror, err))
    return err
end
