using Test, BaseModelica, ModelingToolkit, OrdinaryDiffEq

# Inputs copied from the records review (9990bdfe), including invalid inputs which
# must fail explicitly rather than silently bind names in the enclosing model.
function review_record_member(sys, name)
    hasproperty(sys, Symbol(name)) && return getproperty(sys, Symbol(name))
    m = match(r"^(.*)\[([0-9,]+)\]$", name)
    return getproperty(sys, Symbol(m[1]))[parse.(Int, split(m[2], ','))...]
end

@testset "Record review regressions ($parser, $arrays)" for parser in (:julia, :antlr), arrays in (:scalarize, :keep)
    path(case) = joinpath(@__DIR__, "review_records", "$case.bmo")
    @testset "Unassigned locals cannot capture model variables" begin
        for case in ("A9", "A10", "B1", "B2")
            @test_throws BaseModelica.UnsupportedFeatureError parse_basemodelica(path(case); parser, arrays)
        end
        # Reading a declared local before any assignment must also be diagnosed.
        for algorithm in ("y := x;", "if u > 0.5 then x := 10; end if; y := x;", "for x in 1:2 loop y := x; end for; y := x;"), model_x in ("", "Real x = -1;")
            file = tempname() * ".bmo"
            write(file, """
            package P
              function f input Real u; output Real y; Real x;
              algorithm $algorithm end f;
              model M $model_x Real z; equation z = f(time); end M;
            end P;
            """)
            @test_throws BaseModelica.UnsupportedFeatureError parse_basemodelica(file; parser, arrays)
        end
    end
    @testset "A prior local value survives an untaken branch" begin
        file = tempname() * ".bmo"
        write(file, """
        package P
          function f input Real u; output Real y; Real x = 3;
          algorithm if u > 0.5 then x := 10; end if; y := x; end f;
          model M Real x = -1; Real z; equation z = f(time); end M;
        end P;
        """)
        sys = parse_basemodelica(file; parser, arrays)
        sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Rodas5P())
        @test sol(0.0; idxs = sys.z) ≈ 3
        @test sol(1.0; idxs = sys.z) ≈ 10
    end
    @testset "Unsupported records and functions fail only on use" begin
        for case in ("C1", "C2")
            sys = parse_basemodelica(path(case); parser, arrays)
            sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5(); reltol = 1e-9, abstol = 1e-11)
            @test sol.retcode == ReturnCode.Success
            @test sol(1.0; idxs = sys.z) ≈ exp(-1) atol = 1e-8
            text = read(path(case), String)
            used = case == "C1" ? replace(text, "Real 'z'(start" => "'R' 'r'; Real 'z'(start") :
                replace(text, "der('z') = -'z'" => "der('z') = 'g'({'R'(1)})")
            file = tempname() * ".bmo"
            write(file, used)
            @test_throws BaseModelica.UnsupportedFeatureError parse_basemodelica(file; parser, arrays)
        end
    end
    @testset "Review record values and starts" begin
        expected = [
            "A1" => ["r.x" => (1, 1), "r.y" => (6, 6)],
            "A2" => ["z" => (6, 6)], "A3" => ["z" => (5, 5)],
            "A7" => ["r.x" => (3, 1), "r.y" => (4, 2)],
            "A8" => ["w.x" => (0, 1), "w.y" => (0, 3), "z" => (3, 3)],
            "A12" => ["z" => (3, 3)],
            "A14" => ["o.a.v[3]" => (2, 2), "o.z" => (4, 4)],
            "B3" => ["x" => (1, 1), "y" => (2, 2)],
        ]
        for (case, values) in expected
            case == "B3" && continue # Covered with the initial-equation regressions.
            sys = parse_basemodelica(path(case); parser, arrays)
            sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Rodas5P(); reltol = 1e-9, abstol = 1e-11)
            @test sol.retcode == ReturnCode.Success
            for (name, targets) in values, (t, target) in zip((0.0, 1.0), targets)
                @test sol(t; idxs = review_record_member(sys, name)) ≈ target atol = 1e-8
            end
        end
        for case in ("A4", "A5", "A6", "A11", "A13")
            @test_throws Exception parse_basemodelica(path(case); parser, arrays)
        end
    end
end
