using Test
using BaseModelica
using ModelingToolkit
using ModelingToolkit: Pre
using OrdinaryDiffEq
import Symbolics
import ModelingToolkitBase

BM = BaseModelica

testfile(name) = joinpath(dirname(dirname(pathof(BM))), "test", "testfiles", name * ".bmo")

function write_model(body)
    path = tempname() * ".bmo"
    write(
        path, """//! base 0.1.0
        package 'M'
          model 'M'
        $body
          end 'M';
        end 'M';
        """
    )
    return path
end

# Records the DiscreteModel BaseModelica hands over and lowers it with the MTK backend.
struct RecordingBackend <: BM.AbstractDiscreteBackend
    seen::Vector{BM.DiscreteModel}
end
RecordingBackend() = RecordingBackend(BM.DiscreteModel[])
function BM.lower_discrete(backend::RecordingBackend, model::BM.DiscreteModel)
    push!(backend.seen, model)
    return BM.lower_discrete(BM.MTKEventsBackend(), model)
end

# Overrides the optional hooks too.
struct HookBackend <: BM.AbstractDiscreteBackend
    declared::Vector{Symbol}
    compiled::Base.RefValue{Int}
end
HookBackend() = HookBackend(Symbol[], Ref(0))
function BM.declare_discrete(backend::HookBackend, name::Symbol)
    push!(backend.declared, name)
    return BM.declare_discrete(BM.MTKEventsBackend(), name)
end
BM.lower_discrete(::HookBackend, model::BM.DiscreteModel) =
    BM.lower_discrete(BM.MTKEventsBackend(), model)
function BM.compile_system(backend::HookBackend, sys)
    backend.compiled[] += 1
    return mtkcompile(sys)
end

# Implements nothing
struct IncompleteBackend <: BM.AbstractDiscreteBackend end

names_of(xs) = [ModelingToolkit.getname(x) for x in xs]
error_message(f) = try
    f()
    ""
catch e
    sprint(showerror, e)
end

# Third-party backends must get a useful error for iteration clocks, rather than
# failures converting vectors to Num or applying | to Bool and Float64.
struct IterationClockBackend <: BM.AbstractDiscreteBackend
    condition::Any
end
function BM.lower_discrete(backend::IterationClockBackend, model::BM.DiscreteModel)
    return BM.LoweredDiscrete(;
        equations = model.equations,
        event_iteration = [ModelingToolkitBase.SymbolicDiscreteCallback(backend.condition)]
    )
end

@testset "Discrete backend interface" begin
    @testset "Iteration callbacks require Boolean conditions" begin
        path = write_model("""
            Real 'x'(start = 0.0, fixed = true);
          equation
            der('x') = 1.0;
        """)
        for condition in ([0.5], 0.1)
            err = try
                parse_basemodelica(path; discrete_backend = IterationClockBackend(condition))
            catch e
                e
            end
            @test err isa ArgumentError
            @test occursin("event_iteration callbacks require symbolic Boolean conditions", sprint(showerror, err))
            @test occursin("discrete_events", sprint(showerror, err))
        end
        @test parse_basemodelica(path; discrete_backend = IterationClockBackend(Float64[])) isa System
    end

    @testset "Registered backend receives the DiscreteModel" begin
        backend = RecordingBackend()
        BM.register_discrete_backend!(:recording, backend)
        try
            prob = create_odeproblem(testfile("BouncingBallCounter"); discrete_backend = :recording)
            model = only(backend.seen)
            @test length(model.equations) == 2
            @test names_of(model.variables) == [:h, :v]
            @test names_of(model.states) == [:h, :v]
            bounces, start = only(model.discretes)
            @test ModelingToolkit.getname(bounces) == :bounces
            @test start == 0
            @test ModelingToolkit.isparameter(bounces)   # default declare_discrete: @discretes

            block = only(model.when_blocks)
            @test isnothing(block.sample)
            h, v = model.variables
            @test isequal(block.condition, h < 0.0)
            # crosses zero upwards when h < 0 becomes true
            @test Symbolics.value(Symbolics.substitute(block.crossing, Dict(h => -0.5))) > 0
            @test Symbolics.value(Symbolics.substitute(block.crossing, Dict(h => 0.5))) < 0
            # pre(bounces) + 1, with pre as ModelingToolkit.Pre
            assigned, rhs = only(block.assignments)
            @test isequal(assigned, bounces)
            @test isequal(rhs, Pre(bounces) + 1)
            target, reinit_rhs = only(block.reinits)
            @test isequal(target, v)
            @test occursin("Pre(v(t))", string(reinit_rhs))

            # Same solution as the built-in backend
            sol = solve(prob, Tsit5())
            ref_prob = create_odeproblem(testfile("BouncingBallCounter"); discrete_backend = :mtk)
            ref = solve(ref_prob, Tsit5())
            @test sol.retcode == ReturnCode.Success
            @test sol(2.5; idxs = prob.f.sys.h) ≈ ref(2.5; idxs = ref_prob.f.sys.h)
            @test last(sol.ps[prob.f.sys.bounces]) == last(ref.ps[ref_prob.f.sys.bounces]) == 6
        finally
            BM.unregister_discrete_backend!(:recording)
        end
    end

    @testset "Sample triggers, elsewhen and shared triggers" begin
        backend = RecordingBackend()

        parse_basemodelica(testfile("SampledCounter"); discrete_backend = backend)
        model = only(backend.seen)
        block = only(model.when_blocks)
        @test block.sample == (0.0, 0.25)
        @test isnothing(block.condition) && isnothing(block.crossing)
        @test names_of(first.(block.assignments)) == [:n, :xs]
        @test isequal(last(block.assignments[2]), only(model.variables))   # xs = x

        parse_basemodelica(testfile("WhenElsewhen"); discrete_backend = backend)
        @test length(backend.seen[end].when_blocks) == 2
        @test [b.chain for b in backend.seen[end].when_blocks] == [1, 1]
        @test [b.priority for b in backend.seen[end].when_blocks] == [1, 2]

        # Two independent when-equations keep their identities and fire together
        shared = write_model(
            """
                Real 'x'(fixed = true, start = 0.0);
                discrete Real 'a';
                discrete Real 'b'(start = 3.0);
              equation
                der('x') = 1.0;
                when 'x' > 0.5 then
                  'a' = 1.0;
                end when;
                when 'x' > 0.5 then
                  'b' = pre('b') + 1.0;
                end when;
            """
        )
        sys = parse_basemodelica(shared; discrete_backend = backend)
        model = backend.seen[end]
        @test [b.chain for b in model.when_blocks] == [1, 2]
        @test [b.priority for b in model.when_blocks] == [1, 1]
        @test names_of([first(only(b.assignments)) for b in model.when_blocks]) == [:a, :b]
        @test Dict(ModelingToolkit.getname(v) => s for (v, s) in model.discretes) == Dict(:a => 0.0, :b => 3.0)
        sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5())
        @test last(sol.ps[sys.a]) == 1.0
        @test last(sol.ps[sys.b]) == 4.0
    end

    @testset "Backend instance and optional hooks" begin
        backend = HookBackend()
        sys = parse_basemodelica(testfile("DiscreteCounter"); discrete_backend = backend)
        @test backend.declared == [:n]
        @test backend.compiled[] == 1
        @test ModelingToolkit.iscomplete(sys)
        raw = parse_basemodelica(testfile("DiscreteCounter"); discrete_backend = backend, simplify = false)
        @test backend.compiled[] == 1
        @test !ModelingToolkit.iscomplete(raw)
    end

    @testset ":auto selection" begin
        @test BM.select_backend(:auto) isa BM.MTKEventsBackend
        @test BM.select_backend(:mtk) isa BM.MTKEventsBackend
        first_backend = RecordingBackend()
        BM.register_discrete_backend!(:first, first_backend; auto = true)
        try
            @test BM.select_backend(:auto) === first_backend
            parse_basemodelica(testfile("DiscreteCounter"))   # default discrete_backend = :auto
            @test length(first_backend.seen) == 1

            BM.register_discrete_backend!(:second, RecordingBackend(); auto = true)
            @test occursin("ambiguous", error_message(() -> BM.select_backend(:auto)))
            @test_throws ArgumentError BM.select_backend(:auto)
            # Registering again without `auto` withdraws from automatic selection
            BM.register_discrete_backend!(:second, RecordingBackend())
            @test BM.select_backend(:auto) === first_backend
        finally
            BM.unregister_discrete_backend!(:first)
            BM.unregister_discrete_backend!(:second)
        end
        @test BM.select_backend(:auto) isa BM.MTKEventsBackend
    end

    @testset "Errors" begin
        # SynchToolkit is not a test dependency, so its backend is never registered here
        msg = error_message(() -> parse_basemodelica(testfile("DiscreteCounter"); discrete_backend = :synchtoolkit))
        @test occursin("No discrete backend is registered as discrete_backend = :synchtoolkit", msg)
        @test occursin("load SynchToolkit to enable it", msg)
        @test_throws ArgumentError parse_basemodelica(testfile("DiscreteCounter"); discrete_backend = :synchtoolkit)

        msg = error_message(() -> BM.select_backend(:bogus))
        @test occursin("load the package that provides it", msg)
        @test occursin("Registered backends: :mtk", msg)
        @test_throws ArgumentError BM.select_backend("mtk")

        @test_throws ArgumentError BM.register_discrete_backend!(:mtk, RecordingBackend())
        @test_throws ArgumentError BM.register_discrete_backend!(:auto, RecordingBackend())
        @test_throws ArgumentError BM.unregister_discrete_backend!(:mtk)

        # A backend must implement lower_discrete
        @test_throws MethodError parse_basemodelica(testfile("DiscreteCounter"); discrete_backend = IncompleteBackend())
    end

    @testset "MTK backend: sample with a phase is unsupported" begin
        phased = write_model(
            """
                Real 'x'(fixed = true, start = 0.0);
                discrete Real 'n';
              equation
                der('x') = 1.0;
                when sample(0.1, 0.25) then
                  'n' = pre('n') + 1.0;
                end when;
            """
        )
        @test_throws BM.UnsupportedFeatureError parse_basemodelica(phased; discrete_backend = :mtk)
    end
end

# An independent backend that represents each discrete as a held continuous unknown.
# This exercises the extension interface without delegating to MTKEventsBackend.
struct HeldStateBackend <: BM.AbstractDiscreteBackend end
function BM.declare_discrete(::HeldStateBackend, name::Symbol)
    t = ModelingToolkit.t_nounits
    return only(@variables($name(t)))
end
function BM.lower_discrete(::HeldStateBackend, model::BM.DiscreteModel)
    eqs = copy(model.equations)
    for (var, _) in model.discretes
        push!(eqs, ModelingToolkit.D_nounits(var) ~ 0.0)
    end
    callbacks = Any[]
    iteration = Any[]
    parameters = Num[]
    starts = Pair[model.discretes...]
    for block in model.when_blocks
        if isnothing(block.sample)
            # Relation-defined Booleans have no continuous crossing. This backend
            # independently implements their edge history using the public helper.
            @assert isnothing(block.crossing)
            previous = only(@discretes($(gensym(:previous))(ModelingToolkit.t_nounits)))
            push!(parameters, previous)
            push!(starts, previous => 0.0)
            condition = Pre(block.condition)
            edge = BM.when_edge(condition, Pre(previous) > 0.5)
            affects = Equation[
                var ~ ifelse(edge, rhs, Pre(var)) for (var, rhs) in block.assignments
            ]
            push!(affects, previous ~ ifelse(condition, 1.0, 0.0))
            append!(affects, [state ~ Pre(state) for state in model.states])
            initialize = Equation[previous ~ ifelse(condition, 1.0, 0.0)]
            append!(initialize, [state ~ Pre(state) for state in model.states])
            append!(initialize, [var ~ Pre(var) for (var, _) in model.discretes])
            push!(
                iteration, ModelingToolkitBase.SymbolicDiscreteCallback(
                    Symbolics.unwrap(Num(block.condition) != (previous > 0.5)), affects;
                    initialize, discrete_parameters = [previous]
                )
            )
            continue
        end
        @assert block.sample == (0.0, 0.25)
        affects = Equation[var ~ rhs for (var, rhs) in block.assignments]
        append!(affects, [state ~ Pre(state) for state in model.states])
        push!(
            callbacks, ModelingToolkitBase.SymbolicDiscreteCallback(
                block.sample[2], affects; initialize = affects
            )
        )
    end
    return BM.LoweredDiscrete(;
        equations = eqs, discrete_events = callbacks, event_iteration = iteration,
        parameters, initial_conditions = starts
    )
end

@testset "Independent public backend solves a sampled model ($parser)" for parser in (:julia, :antlr)
    BM.register_discrete_backend!(:held_state_test, HeldStateBackend())
    try
        sys = parse_basemodelica(testfile("SampledCounter"); parser, discrete_backend = :held_state_test)
        @test !ModelingToolkit.isparameter(sys.n)
        raw = parse_basemodelica(testfile("SampledCounter"); parser, discrete_backend = :held_state_test, simplify = false)
        @test :n in names_of(unknowns(raw))
        sol = solve(ODEProblem(sys, [], (0.0, 0.9)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        @test sol(0.1; idxs = sys.n) == 1
        @test sol(0.9; idxs = sys.n) == 4
        @test sol(0.9; idxs = sys.xs) ≈ 0.75
        @test sol(0.9; idxs = sys.x) ≈ 0.9
    finally
        BM.unregister_discrete_backend!(:held_state_test)
    end
end

@testset "Backend Boolean edges and legacy block constructor ($parser)" for parser in (:antlr, :julia)
    path = write_model(
        """
            Real 'x'(start = 0.0, fixed = true);
            Boolean 'b';
            Boolean 'already';
            discrete Real 'n'(start = 0.0);
            discrete Real 'm'(start = 0.0);
          equation
            der('x') = 1.0;
            'b' = 'x' > 0.5;
            'already' = 'x' > -1.0;
            when 'b' then 'n' = pre('n') + 1.0; end when;
            when 'already' then 'm' = pre('m') + 1.0; end when;
        """
    )
    recording = RecordingBackend()
    parse_basemodelica(path; parser, discrete_backend = recording)
    blocks = only(recording.seen).when_blocks
    @test length(blocks) == 2
    @test all(b -> isnothing(b.crossing) && isnothing(b.sample), blocks)
    for b in blocks
        legacy = BM.WhenBlock(b.condition, b.crossing, b.sample, b.assignments, b.reinits)
        @test legacy.chain == 0 && legacy.priority == 1
        @test isequal(legacy.condition, b.condition)
    end
    @test !BM.when_edge(true, true)
    @test BM.when_edge(true, false)
    @test !BM.when_edge(false, true)
    @test !BM.when_edge(true, false; initialize = true)
    sys = parse_basemodelica(path; parser, discrete_backend = HeldStateBackend())
    sol = solve(ODEProblem(sys, [], (0.0, 0.9)), Tsit5())
    @test sol.retcode == ReturnCode.Success
    @test sol(0.0; idxs = sys.n) == sol(0.4; idxs = sys.n) == 0
    @test sol(0.5 + 1.0e-6; idxs = sys.n) == sol(0.9; idxs = sys.n) == 1
    @test all(iszero, sol[sys.m])
end
