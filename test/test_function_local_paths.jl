using Test, BaseModelica, ModelingToolkit, OrdinaryDiffEq

function local_paths_file(declarations, algorithm)
    file = tempname() * ".bmo"
    write(file, """
    //! base 0.1.0
    package P
      record R
        Real x;
        Real w;
      end R;
      record A
        Real v[2];
      end A;
      function f
        input Real u;
        output Real y;
        $declarations
      algorithm
        $algorithm
      end f;
      model M
        Real z;
      equation
        z = f(time);
      end M;
    end P;
    """)
    return file
end

@testset "Function local paths ($parser, $arrays)" for parser in (:julia, :antlr), arrays in (:scalarize, :keep)
    @testset "Partial branch assignments have a clear diagnostic" begin
        for (declarations, algorithm, var) in (
                ("Real a[2];", "a[1] := 1; if u > 0.5 then a[2] := 2; end if; y := a[2] + 7;", "a"),
                ("R r;", "r.x := 1; if u > 0.5 then r.w := 2; end if; y := r.w;", "r"),
                ("A r;", "r.v[1] := 1; if u > 0.5 then r.v[2] := 2; end if; y := r.v[2];", "r"),
                ("R r[2];", "r[1].x := 1; if u > 0.5 then r[1].w := 2; end if; y := r[1].w;", "r"),
            )
            file = local_paths_file(declarations, algorithm)
            err = try
                parse_basemodelica(file; parser, arrays)
                nothing
            catch ex
                ex
            end
            @test err isa BaseModelica.UnsupportedFeatureError
            @test occursin("function local `$var` is unassigned on some execution paths", sprint(showerror, err))
        end
    end

    @testset "Assigned members merge while other members await assignment" begin
        for (declarations, algorithm, expected) in (
                ("Real a[2];", "if u > 0.5 then a[1] := 10; else a[1] := 3; end if; a[2] := 2; y := sum(a);", (5, 12)),
                ("R r;", "if u > 0.5 then r.x := 10; else r.x := 3; end if; r.w := 2; y := r.x + r.w;", (5, 12)),
                ("A r;", "if u > 0.5 then r.v[1] := 10; else r.v[1] := 3; end if; r.v[2] := 2; y := sum(r.v);", (5, 12)),
                ("Real a[2] = {1, 2};", "if u > 0.5 then a[2] := 20; end if; y := sum(a);", (3, 21)),
                ("R r;", "r.x := 1; if true then r.w := 2; end if; y := r.x + r.w;", (3, 3)),
            )
            file = local_paths_file(declarations, algorithm)
            sys = parse_basemodelica(file; parser, arrays)
            sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5())
            @test sol.retcode == ReturnCode.Success
            @test sol(0.0; idxs = sys.z) ≈ expected[1]
            @test sol(1.0; idxs = sys.z) ≈ expected[2]
        end
    end

    @testset "Separate matching guards remain conservatively unsupported" begin
        file = local_paths_file("Real x;", """
            if u > 0.5 then x := 10; end if;
            if u > 0.5 then y := x; else y := 0; end if;
            """)
        @test_throws BaseModelica.UnsupportedFeatureError parse_basemodelica(file; parser, arrays)
    end
end
