using Test
using BaseModelica
using ModelingToolkit
using OrdinaryDiffEq
using ModelingToolkit: D_nounits as D
using SciMLBase: remake

BM = BaseModelica

testfile(name) = joinpath(dirname(dirname(pathof(BM))), "test", "testfiles", name * ".bmo")

parameter_names(sys) = Set(ModelingToolkit.getname.(ModelingToolkit.parameters(sys)))

@testset "Constants and structural parameters" begin
    @testset "Constants are inlined ($parser)" for parser in (:julia, :antlr)
        prob = @test_logs min_level = Base.CoreLogging.Warn create_odeproblem(
            testfile("Constants"); parser
        )
        sys = prob.f.sys
        # Constants are not parameters, so nothing can change them after loading
        @test parameter_names(sys) == Set([:m])
        @test isempty(ModelingToolkit.bound_parameters(sys))
        # ... but their values reach equations, bindings and start values
        @test prob.ps[sys.m] == 1.5                         # m = k * 0.5
        @test prob[sys.x] == 9.81                           # start = g
        rhs = string(only(e.rhs for e in equations(sys) if isequal(e.lhs, D(sys.v))))
        @test occursin("19.62", rhs)                        # g2 = 2 * g, declared before g
        @test occursin("v(t)", rhs)                         # useDamping = true picks the damping term
        @test solve(prob, Tsit5()).retcode == ReturnCode.Success
    end

    @testset "Unresolved constants keep public non-tunable metadata ($parser)" for parser in (:julia, :antlr)
        path = tempname() * ".bmo"
        write(
            path, """//! base 0.1.0
            package 'UnboundConstant'
              model 'UnboundConstant'
                constant Real 'c';
                Real 'x'(start = 1.0, fixed = true);
              equation
                der('x') = -'c' * 'x';
              end 'UnboundConstant';
            end 'UnboundConstant';
            """
        )
        sys = parse_basemodelica(path; parser, simplify = false)
        @test !ModelingToolkit.istunable(sys.c)
        @test :c in parameter_names(sys)
    end

    @testset "Evaluate = true parameters are not tunable ($parser)" for parser in (:julia, :antlr)
        sys = @test_logs (:warn, r"'n', 'useDamper', 'k' were evaluated at translation") min_level = Base.CoreLogging.Warn parse_basemodelica(
            testfile("EvaluatedParameters"); parser
        )
        @test parameter_names(sys) == Set([:n, :useDamper, :k, :d])
        for p in (sys.n, sys.useDamper, sys.k)
            @test !ModelingToolkit.istunable(p)
            @test occursin(
                "evaluated at translation (Evaluate=true); recompile to change it",
                ModelingToolkit.getdescription(p)
            )
        end
        # `annotation(Evaluate = false)` leaves a parameter tunable
        @test ModelingToolkit.istunable(sys.d)
        @test sys.d in Set(ModelingToolkit.tunable_parameters(sys))
        @test !(sys.k in Set(ModelingToolkit.tunable_parameters(sys)))

        prob = ODEProblem(sys, [], (0.0, 1.0))
        @test prob.ps[sys.n] == 3
        @test prob.ps[sys.useDamper] == false
        # The binding of an evaluated parameter is evaluated too: k is a value, not a binding
        @test prob.ps[sys.k] == 6.0
        @test isempty(ModelingToolkit.bound_parameters(sys))
    end

    @testset "Inert parameters ($parser)" for parser in (:julia, :antlr)
        # `c` is used by the binding of `unused` and `x0` by a start value: only `unused` and
        # `nElements` are referenced by nothing.
        sys = @test_logs (:warn, "BaseModelica model 'InertParameters': parameters 'unused', 'nElements' are not used by any equation, binding or start value; changing them has no effect") min_level = Base.CoreLogging.Warn parse_basemodelica(
            testfile("InertParameters"); parser
        )
        @test :nElements in parameter_names(sys)
    end

    @testset "Warnings stay one line for large models" begin
        @test BM.quoted_names(["a", "b"]) == "'a', 'b'"
        @test BM.quoted_names(string.('a':'l')) ==
            "'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j' and 2 more"
    end

    @testset "No warnings for models without structural parameters" begin
        @test_logs min_level = Base.CoreLogging.Warn parse_basemodelica(
            testfile("DependentBindings")
        )
    end

    @testset "Dependent bindings are recomputed by remake ($parser)" for parser in (:julia, :antlr)
        prob = create_odeproblem(testfile("DependentBindings"); parser)
        sys = prob.f.sys
        @test parameter_names(sys) == Set([:p, :q, :w])
        @test Set(ModelingToolkit.getname.(ModelingToolkit.bound_parameters(sys))) ==
            Set([:r, :s, :u])
        @test prob.ps[sys.r] == 6.0
        @test prob.ps[sys.s] == 7.0     # chained: s = r + 1
        @test prob.ps[sys.u] == 3.0     # forward reference: u = 2 w, w declared after u
        sol = solve(prob, Tsit5())
        @test sol(1.0; idxs = sys.x) ≈ exp(-1.0) rtol = 1.0e-4

        prob2 = remake(prob; p = [sys.p => 5.0])
        @test prob2.ps[sys.r] == 15.0
        @test prob2.ps[sys.s] == 16.0
        sol2 = solve(prob2, Tsit5())
        @test sol2(1.0; idxs = sys.x) ≈ exp(-34 / 16) rtol = 1.0e-4

        # A bound parameter is computed from its binding and cannot be set itself
        @test_throws Exception remake(prob; p = [sys.r => 7.0])
    end

    @testset "Bindings that refer to other parameters ($parser)" for parser in (:julia, :antlr)
        sys = parse_basemodelica(testfile("ParameterBindings"); parser, simplify = false)
        # Parameters reach ModelingToolkit in declaration order, whatever was parsed before
        declared = [
            Symbol(m.captures[1]) for m in eachmatch(
                    r"parameter Real '([^']+)'", read(testfile("ParameterBindings"), String)
                )
        ]
        @test ModelingToolkit.getname.(ModelingToolkit.parameters(sys)) == declared
        prob = create_odeproblem(testfile("ParameterBindings"); parser)
        csys = prob.f.sys
        @test prob.ps[csys.C] ≈ 1 / (2pi * 1.0 * 1000.0)            # C = 1/(2 pi fG R2)
        @test prob.ps[csys.var"c.C"] == prob.ps[csys.C]
        @test prob.ps[csys.var"vIn.startTime"] ≈ -(0.02 + 0.015)      # refers to later parameters
        @test prob.ps[csys.var"vIn.signalSource.startTime"] == prob.ps[csys.var"vIn.startTime"]
        sol = solve(prob, Rodas5P())
        @test sol.retcode == ReturnCode.Success
        @test sol.ps[csys.var"free.p"] == 2000.0                     # fixed = false, 2 * r2.R
        prob2 = remake(prob; p = [csys.R1 => 2000.0])
        @test prob2.ps[csys.var"r2.R"] == 2000.0
        @test prob2.ps[csys.C] ≈ 1 / (2pi * 1.0 * 2000.0)
    end

    @testset "Conversions on several threads" begin
        # The conversion state is global: concurrent conversions used to overwrite each
        # other's variables, so bindings lost the parameters they refer to.
        code = """
        using BaseModelica, ModelingToolkit
        files = joinpath.($(repr(joinpath(dirname(dirname(pathof(BM))), "test", "testfiles"))),
            ["ParameterBindings.bmo", "DependentBindings.bmo", "CauerLowPassAnalog.bmo"])
        convert(f) = parse_basemodelica(f; parser = :julia, simplify = false)
        canonical(sys) = sort([string(k, " => ", v) for (k, v) in ModelingToolkit.bindings(sys)])
        reference = Dict(f => canonical(convert(f)) for f in files)
        jobs = repeat(files, 8)
        results = Vector{Any}(undef, length(jobs))
        Threads.@threads for i in eachindex(jobs)
            results[i] = try
                canonical(convert(jobs[i])) == reference[jobs[i]]
            catch e
                sprint(showerror, e)
            end
        end
        # The ANTLR parser calls Python, which only works on the main thread
        antlr = fetch(Threads.@spawn try
            Threads.threadid() == 1 || parse_basemodelica(files[1]; simplify = false)
            "main thread"
        catch e
            sprint(showerror, e)
        end)
        println("THREADS ", Threads.nthreads(), " ", count(==(true), results), "/", length(jobs))
        println("ANTLR ", antlr)
        """
        julia = `$(Base.julia_cmd()) --startup-file=no -t 4 --project=$(Base.active_project())`
        output = read(pipeline(`$julia -e $code`; stderr = devnull), String)
        @test occursin("THREADS 4 24/24", output)
        @test occursin(r"ANTLR (main thread|.*must run on the main thread)", output)
    end
end
