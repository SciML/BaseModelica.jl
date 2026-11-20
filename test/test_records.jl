using Test
using BaseModelica
using ModelingToolkit
using OrdinaryDiffEq

const BM = BaseModelica

function record_file(body)
    path = tempname() * ".bmo"
    write(path, "//! base 0.1.0\npackage P\n" * body * "\nend P;\n")
    return path
end

const RECORD_DEFS = """
record Vec
  Real x = 1;
  Real y[2] = {2,3};
end Vec;
record Outer
  Vec v;
  Real z = 4;
end Outer;
function make
  input Real x;
  output Outer r;
algorithm
  r.v.x := x;
  r.z := 2*x;
end make;
function consume
  input Outer r;
  output Real y;
algorithm
  y := r.v.x + sum(r.v.y) + r.z;
end consume;
function '-Vec'
  input Real x;
  input Real y[2];
  output Vec result(x=x, y=y);
end '-Vec';
"""

@testset "Records ($parser)" for parser in (:julia, :antlr)
    @testset "Constructors, nested values and function fields" begin
        path = record_file(RECORD_DEFS * """
        model M
          Real x(start=1, fixed=true);
          Real y;
        equation
          der(x) = -consume(make(x));
          y = consume(Outer(v=Vec(y={3,4}, x=x), z=5)) + sum('-Vec'(x,{1,2}).y);
        end M;
        """)
        # Accessor functions emitted by rumoca use local field access.
        source = read(path, String)
        source = replace(source, " + sum('-Vec'(x,{1,2}).y)" => "")
        write(path, source)
        sys = parse_basemodelica(path; parser)
        sol = solve(ODEProblem(sys, [], (0.0, 0.2)), Tsit5(); reltol=1e-10, abstol=1e-12)
        @test sol.retcode == ReturnCode.Success
        @test sol(0.2; idxs=sys.x) ≈ (1 + 5/3)*exp(-0.6) - 5/3 atol=1e-8
        @test sol(0.2; idxs=sys.y) ≈ sol(0.2; idxs=sys.x) + 12 atol=1e-10
    end

    @testset "Record components, parameters, starts and equations" begin
        path = record_file(RECORD_DEFS * """
        model M
          parameter Outer p(v(x=2, y={3,4}), z=5);
          Outer a(start=Outer(Vec(1,{2,3}),4), fixed=true);
          Outer b = p;
          Real s;
        equation
          der(a.v.x) = -a.v.x;
          der(a.v.y) = -a.v.y;
          der(a.z) = -a.z;
          s = consume(b);
        end M;
        """)
        sys = parse_basemodelica(path; parser)
        sol = solve(ODEProblem(sys, [], (0.0, 0.2)), Tsit5(); reltol=1e-10, abstol=1e-12)
        @test sol.retcode == ReturnCode.Success
        @test sol(0.2; idxs=getproperty(sys, Symbol("a.v.x"))) ≈ exp(-0.2) atol=1e-8
        @test sol(0.2; idxs=getproperty(sys, Symbol("a.v.y[2]"))) ≈ 3exp(-0.2) atol=1e-8
        @test sol(0.2; idxs=sys.s) ≈ 14
    end

    @testset "Literal arrays of records" begin
        path = record_file(RECORD_DEFS * """
        function first_x
          input Vec rs[2];
          output Real x;
        algorithm
          x := rs[1].x + rs[2].y[2];
        end first_x;
        model M
          parameter Vec p[2] = {Vec(2,{3,4}), Vec(5,{6,7})};
          Real x(start=0, fixed=true);
        equation
          der(x) = p[1].x + p[2].y[1] + first_x(p);
        end M;
        """)
        sys = parse_basemodelica(path; parser)
        sol = solve(ODEProblem(sys, [], (0.0, 0.2)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        @test sol(0.2; idxs=sys.x) ≈ 3.4
    end

    @testset "Generated constructor output binding" begin
        path = record_file(RECORD_DEFS * """
        function accessor
          input Real x;
          output Real y;
          Vec r;
        algorithm
          r := '-Vec'(x,{2,3});
          y := r.x + r.y[2];
        end accessor;
        model M
          Real x(start=0, fixed=true);
        equation
          der(x) = accessor(2);
        end M;
        """)
        sys = parse_basemodelica(path; parser)
        sol = solve(ODEProblem(sys, [], (0.0, 0.2)), Tsit5())
        @test sol(0.2; idxs=sys.x) ≈ 1
    end

    @testset "Unsupported records fail clearly" begin
        for body in (
            "record R R r; end R; model M R r; end M;",
            "record R Real x; equation x=1; end R; model M R r; end M;",
            "record R Real x; end R; model M parameter Integer n=2; R r[n]; end M;",
            "record R Real x; end R; model M R r(bad=2); end M;",
            "record R Real x; end R; model M Real x; equation x=R(1).bad; end M;",
        )
            path = record_file(body)
            # Direct function-result member syntax is outside the Base Modelica grammar;
            # unsupported syntax must still throw, never silently drop the member.
            @test_throws Exception parse_basemodelica(path; parser, simplify=false)
        end
    end
end
