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
        path = record_file(
            RECORD_DEFS * """
                model M
                  Real x(start=1, fixed=true);
                  Real y;
                equation
                  der(x) = -consume(make(x));
                  y = consume(Outer(v=Vec(y={3,4}, x=x), z=5));
                  annotation(experiment(StopTime=0.2));
                end M;
                """
        )
        sys = parse_basemodelica(path; parser)
        sol = solve(ODEProblem(sys, [], (0.0, 0.2)), Tsit5(); reltol = 1.0e-10, abstol = 1.0e-12)
        @test sol.retcode == ReturnCode.Success
        @test experiment_settings(sys).StopTime == 0.2
        @test sol(0.2; idxs = sys.x) ≈ (1 + 5 / 3) * exp(-0.6) - 5 / 3 atol = 1.0e-8
        @test sol(0.2; idxs = sys.y) ≈ sol(0.2; idxs = sys.x) + 12 atol = 1.0e-10
    end

    @testset "Record components, parameters, starts and equations" begin
        path = record_file(
            RECORD_DEFS * """
                record StateVec
                  Real x;
                  Real y[2];
                end StateVec;
                record StateOuter
                  StateVec v;
                  Real z;
                end StateOuter;
                model M
                  parameter Outer p(v(x=2, y={3,4}), z=5);
                  StateOuter a(start=StateOuter(StateVec(1,{2,3}),4), fixed=true);
                  Outer b = p;
                  Real s;
                equation
                  der(a.v.x) = -a.v.x;
                  der(a.v.y) = -a.v.y;
                  der(a.z) = -a.z;
                  s = consume(b);
                end M;
                """
        )
        sys = parse_basemodelica(path; parser)
        sol = solve(ODEProblem(sys, [], (0.0, 0.2)), Tsit5(); reltol = 1.0e-10, abstol = 1.0e-12)
        @test sol.retcode == ReturnCode.Success
        @test sol(0.2; idxs = getproperty(sys, Symbol("a.v.x"))) ≈ exp(-0.2) atol = 1.0e-8
        @test sol(0.2; idxs = getproperty(sys, Symbol("a.v.y[2]"))) ≈ 3exp(-0.2) atol = 1.0e-8
        @test sol(0.2; idxs = sys.s) ≈ 14
    end

    @testset "Literal arrays of records" begin
        path = record_file(
            RECORD_DEFS * """
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
                """
        )
        sys = parse_basemodelica(path; parser)
        sol = solve(ODEProblem(sys, [], (0.0, 0.2)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        @test sol(0.2; idxs = sys.x) ≈ 3.4
    end

    @testset "Each modifiers preserve array fields of record arrays" begin
        path = record_file(
            """
            record R
              Real v[2];
            end R;
            function default_records
              output R rs[2](v={{5,6},{7,8}});
            end default_records;
            function array_value
              input R rs[2] = default_records();
              output Real y;
            algorithm
              y := rs[1].v[2] + 10*rs[2].v[1];
            end array_value;
            model M
              parameter R p[2](each v={1,2});
              parameter R q[2](v={{1,2},{3,4}});
              Real x(start=0, fixed=true);
            equation
              der(x) = p[1].v[2] + 10*p[2].v[1] + 100*q[1].v[2] + 1000*q[2].v[1] + array_value();
            end M;
            """
        )
        sys = @test_logs parse_basemodelica(path; parser)
        sol = solve(ODEProblem(sys, [], (0.0, 0.2)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        @test sol(0.2; idxs = sys.x) ≈ 657.6
    end

    @testset "Generated constructor output binding" begin
        path = record_file(
            RECORD_DEFS * """
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
                """
        )
        sys = parse_basemodelica(path; parser)
        sol = solve(ODEProblem(sys, [], (0.0, 0.2)), Tsit5())
        @test sol(0.2; idxs = sys.x) ≈ 1
    end

    @testset "Zero-argument record calls and input defaults" begin
        path = record_file(
            RECORD_DEFS * """
                function zero_constructor
                  output Vec r(x=2, y={3,4});
                end zero_constructor;
                function nullRecord
                  output Vec r;
                algorithm
                  r := zero_constructor();
                end nullRecord;
                function default_record
                  input Vec r = nullRecord();
                  output Real y;
                algorithm
                  y := r.x + sum(r.y);
                end default_record;
                function constant_value
                  output Real y;
                algorithm
                  y := 2;
                end constant_value;
                model M
                  Real x(start=0, fixed=true);
                equation
                  der(x) = default_record() + constant_value();
                end M;
                """
        )
        sys = parse_basemodelica(path; parser)
        sol = solve(ODEProblem(sys, [], (0.0, 0.2)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        @test sol(0.2; idxs = sys.x) ≈ 2.2
    end

    @testset "Field defaults and dimensions use record scope" begin
        path = record_file(
            """
            record Sized
              Integer n = 2;
              Real v[n] = fill(n,n);
            end Sized;
            function total
              input Sized p;
              output Real y;
            algorithm
              y := sum(p.v);
            end total;
            model M
              parameter Integer n=7;
              parameter Sized p(n=3);
              Real x(start=0, fixed=true);
            equation
              der(x) = total(p) + total(Sized(n=4)) + n;
            end M;
            """
        )
        sys = parse_basemodelica(path; parser)
        sol = solve(ODEProblem(sys, [], (0.0, 0.2)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        @test sol(0.2; idxs = sys.x) ≈ 6.4
    end

    @testset "Record equations and nested arrays of records" begin
        path = record_file(
            """
            record R
              Real x;
            end R;
            record A
              R rs[2];
            end A;
            function total
              input A a;
              output Real y;
            algorithm
              y := a.rs[1].x + a.rs[2].x;
            end total;
            model M
              parameter A p = A({R(2),R(3)});
              A a;
              Real x(start=0, fixed=true);
            equation
              a = p;
              der(x) = total(a);
            end M;
            """
        )
        sys = parse_basemodelica(path; parser)
        sol = solve(ODEProblem(sys, [], (0.0, 0.2)), Tsit5())
        @test sol.retcode == ReturnCode.Success
        @test sol(0.2; idxs = sys.x) ≈ 1
    end

    @testset "Record arrays and branch field assignments in functions" begin
        path = record_file(
            RECORD_DEFS * """
                function choose
                  input Real u;
                  output Vec rs[2];
                algorithm
                  if u > 0 then
                    rs[1].x := u;
                    rs[1].y := {rs[1].x, 2};
                  else
                    rs[1].x := -u;
                    rs[1].y := {rs[1].x, 3};
                  end if;
                  rs[2] := Vec(4,{5,6});
                end choose;
                function read_rs
                  input Vec rs[2];
                  output Real y;
                algorithm
                  y := rs[1].x + sum(rs[1].y) + rs[2].x;
                end read_rs;
                model M
                  Real x(start=-1, fixed=true);
                  Real y;
                equation
                  der(x) = 1;
                  y = read_rs(choose(x));
                end M;
                """
        )
        sys = parse_basemodelica(path; parser)
        sol = solve(ODEProblem(sys, [], (0.0, 2.0)), Tsit5(); reltol = 1.0e-10)
        @test sol.retcode == ReturnCode.Success
        @test sol(0.25; idxs = sys.y) ≈ 8.5
        @test sol(1.75; idxs = sys.y) ≈ 7.5
    end

    @testset "Unsupported records fail clearly" begin
        for body in (
                "record R R r; end R; model M R r; end M;",
                "record R Real x; equation x=1; end R; model M R r; end M;",
                "record R Real x; end R; model M parameter Integer n=2; R r[n]; end M;",
                "record R Real x; end R; model M R r(bad=2); end M;",
                "record R Real x; end R; model M Real x; equation x=R(bad=1); end M;",
                "record R Real x; end R; model M R r = R(); end M;",
                "record R Real x; end R; model M R r = R(1,x=2); end M;",
                "record R Real x[2]; end R; model M R r = R({1,2,3}); end M;",
                "record R String x; end R; model M R r; end M;",
                "record R Real x=1; end R; function f output R r(x=1); external; end f; model M R r=f(); end M;",
                "record R Real x; end R; function f output R r; end f; model M R r=f(); end M;",
            )
            path = record_file(body)
            @test_throws BM.UnsupportedFeatureError parse_basemodelica(path; parser, simplify = false)
        end
    end
end
