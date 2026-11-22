using Test
using BaseModelica
using ModelingToolkit
using OrdinaryDiffEq
using SciMLBase: remake

# Observe the pre-scan through the public discrete-backend declaration hook.
struct InitializationScanBackend <: BaseModelica.AbstractDiscreteBackend
    declared::Vector{Symbol}
end

function BaseModelica.declare_discrete(backend::InitializationScanBackend, name::Symbol)
    push!(backend.declared, name)
    return BaseModelica.declare_discrete(BaseModelica.MTKEventsBackend(), name)
end

function initialization_model(body)
    path = tempname() * ".bmo"
    write(
        path, """//! base 0.1.0
        package 'InitializationRegression'
          model 'InitializationRegression'
        $body
          end 'InitializationRegression';
        end 'InitializationRegression';
        """
    )
    return path
end

@testset "Initialization regressions ($parser)" for parser in (:antlr, :julia)
    @testset "Initial algorithm array reads observe earlier element writes" begin
        path = initialization_model(
            """
                Real 'x'[2];
                Real 'total';
              equation
                der('x') = -'x';
                der('total') = -'total';
              initial algorithm
                'x'[1] := 1.0;
                'x'[1] := 'x'[1] + 1.0;
                'x'[2] := 3.0;
                'total' := sum('x');
                assert(sum('x'[1:1]) > 1.5, "slice must see the second write");
            """
        )
        sys = parse_basemodelica(path; parser)
        sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5(); reltol = 1.0e-9, abstol = 1.0e-11)
        @test sol.retcode == ReturnCode.Success
        for (name, start) in (("x[1]", 2.0), ("x[2]", 3.0), ("total", 5.0))
            var = getproperty(sys, Symbol(name))
            @test sol(0.0; idxs = var) ≈ start
            @test sol(1.0; idxs = var) ≈ start * exp(-1) rtol = 1.0e-7
        end
    end

    @testset "Only the assigned vector element becomes discrete ($index)" for index in ("2", "'k'", "end")
        path = initialization_model(
            """
                Real 'x'[2](start = {0.0, 4.0}, fixed = true);
                parameter Integer 'k' = 2;
              equation
                der('x'[1]) = 1.0;
                when time > 0.5 then
                  'x'[$index] = pre('x'[$index]) + 2.0;
                end when;
            """
        )
        sys = parse_basemodelica(path; parser, discrete_backend = :mtk)
        x1, x2 = getproperty(sys, Symbol("x[1]")), getproperty(sys, Symbol("x[2]"))
        sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        @test sol(0.0; idxs = x1) ≈ 0.0 atol = 1.0e-10
        @test sol(1.0; idxs = x1) ≈ 1.0
        @test first(sol.ps[x2]) == 4.0
        @test last(sol.ps[x2]) == 6.0
    end

    @testset "Only the assigned matrix slice becomes discrete" begin
        path = initialization_model(
            """
                Real 'A'[2,2](start = {{0.0, 0.0}, {4.0, 5.0}}, fixed = true);
              equation
                der('A'[1,:]) = {1.0, 2.0};
                when time > 0.5 then
                  'A'[2,:] = pre('A'[2,:]) + {2.0, 3.0};
                end when;
            """
        )
        sys = parse_basemodelica(path; parser, discrete_backend = :mtk)
        sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        for (name, value) in (("A[1,1]", 1.0), ("A[1,2]", 2.0))
            @test sol(1.0; idxs = getproperty(sys, Symbol(name))) ≈ value
        end
        for (name, start, value) in (("A[2,1]", 4.0, 6.0), ("A[2,2]", 5.0, 8.0))
            var = getproperty(sys, Symbol(name))
            @test first(sol.ps[var]) == start
            @test last(sol.ps[var]) == value
        end
    end

    @testset "Dynamic subscripts conservatively declare every element discrete" begin
        path = initialization_model(
            """
                Real 'i'(start = 0.0, fixed = true);
                Real 'x'[2];
              equation
                der('i') = 1.0;
                when time > 0.5 then
                  'x'['i' + 1] = 2.0;
                end when;
            """
        )
        backend = InitializationScanBackend(Symbol[])
        # Runtime indexing is unsupported, but the pre-scan must still declare every
        # possible target before the evaluator reports that limitation.
        @test_throws BaseModelica.UnsupportedFeatureError parse_basemodelica(
            path; parser, discrete_backend = backend
        )
        @test backend.declared == [Symbol("x[1]"), Symbol("x[2]")]
    end

    @testset "Boolean starts retain parameter expressions ($forward_reference)" for forward_reference in (false, true)
        parameter = "parameter Boolean 'p' = true;"
        booleans = """
            Boolean 'b'(start = 'p');
            Boolean 'literal'(start = true);
            Boolean 'default';
        """
        declarations = forward_reference ? booleans * parameter : parameter * booleans
        path = initialization_model(
            """
                $declarations
                Real 'x'(start = 0.0, fixed = true);
                Real 'literalValue';
                Real 'defaultValue';
              equation
                der('x') = if 'b' then 1.0 else -1.0;
                'literalValue' = if 'literal' then 10.0 else 20.0;
                'defaultValue' = if 'default' then 30.0 else 40.0;
            """
        )
        sys = @test_logs (:warn, r"Booleans .* have no defining equation and keep their start value") parse_basemodelica(
            path; parser, discrete_backend = :mtk
        )
        prob = ODEProblem(sys, [], (0.0, 1.0))
        sol = solve(prob, Tsit5())
        @test sol.retcode == ReturnCode.Success
        @test sol(1.0; idxs = sys.x) ≈ 1.0
        @test sol(0.0; idxs = sys.literalValue) == 10.0
        @test sol(0.0; idxs = sys.defaultValue) == 40.0
        changed = solve(remake(prob; p = [sys.p => false]), Tsit5())
        @test changed.retcode == ReturnCode.Success
        @test changed(1.0; idxs = sys.x) ≈ -1.0
    end
end

@testset "Defined Boolean pre-start survives remake ($parser)" for parser in (:antlr, :julia)
    path = initialization_model(
        """
            parameter Boolean 'startOn' = true;
            Boolean 'b'(start = 'startOn');
            Real 'y';
            Real 'x'(start = 0.0, fixed = true);
          equation
            der('x') = 1.0;
            'b' = pre('b') and time < 1.0;
            'y' = if 'b' then 1.0 else 0.0;
        """
    )
    sys = parse_basemodelica(path; parser)
    prob = ODEProblem(sys, [], (0.0, 1.5))
    for (p, expected) in ((prob, 1.0), (remake(prob; p = [sys.startOn => false]), 0.0))
        sol = solve(p, Tsit5())
        @test sol.retcode == ReturnCode.Success
        @test sol(0.0; idxs = sys.y) == expected
        @test sol(0.5; idxs = sys.y) == expected
        @test sol(1.25; idxs = sys.y) == 0.0
    end
end

@testset "Initial-section pre reads ($parser)" for parser in (:julia, :antlr)
    @testset "$case: pre(discrete) initializes a state" for case in (:I1, :I2, :I4)
        initial = case === :I4 ? "initial algorithm 'x' := pre('k');" :
            "initial equation 'x' = pre('k')$(case === :I2 ? " + 1.0" : "");"
        path = initialization_model(
            """
                Real 'x'(fixed = false); discrete Real 'k'(start = 2.0);
              equation
                der('x') = 1.0;
                when time > 0.5 then 'k' = pre('k') + 1.0; end when;
              $initial
            """
        )
        sys = parse_basemodelica(path; parser, discrete_backend = :mtk)
        sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5())
        start = case === :I2 ? 3.0 : 2.0
        @test sol.retcode == ReturnCode.Success
        @test sol(0.0; idxs = sys.x) == start
        @test sol(1.0; idxs = sys.x) ≈ start + 1.0
        @test sol(0.0; idxs = sys.k) == 2.0
        @test sol(1.0; idxs = sys.k) == 3.0
    end

    @testset "Relation Boolean pre in an initial section is diagnosed" begin
        path = initialization_model(
            """
                Real 'x'(fixed = false); Boolean 'b';
              equation
                der('x') = 1.0; 'b' = time > 0.5;
              initial equation
                'x' = if pre('b') then 1.0 else 0.0;
            """
        )
        err = try
            parse_basemodelica(path; parser, discrete_backend = :mtk)
        catch e
            e
        end
        @test err isa BaseModelica.UnsupportedFeatureError
        @test occursin("pre() in initial sections is only supported for discrete variables", sprint(showerror, err))
    end

    @testset "Discrete pre target with a pre RHS" begin
        path = initialization_model(
            """
                Real 'x'(start = 0.0, fixed = true);
                discrete Real 'k'(start = 0.0); discrete Real 'w'(start = 2.0);
              equation
                der('x') = 1.0;
                when time > 0.5 then 'k' = pre('k') + 1.0; 'w' = pre('w') + 3.0; end when;
              initial equation
                pre('k') = pre('w');
            """
        )
        sys = parse_basemodelica(path; parser, discrete_backend = :mtk)
        sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        @test sol(0.0; idxs = sys.k) == 2.0
        @test sol(1.0; idxs = sys.k) == 3.0
        @test sol(0.0; idxs = sys.w) == 2.0
        @test sol(1.0; idxs = sys.w) == 5.0
    end
end
