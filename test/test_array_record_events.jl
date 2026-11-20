using BaseModelica, ModelingToolkit, OrdinaryDiffEq, Test
@testset "Record array events" begin
    for parser in (:julia, :antlr), arrays in (:scalarize, :keep)
        file = tempname() * ".bmo"
        write(
            file, """
            //! base 0.1.0
            package P
            record R
              Real v[2](start={1,2}, fixed=true);
              discrete Real d[2](start=0);
            end R;
            model M
              R r;
            equation
              der(r.v)=-r.v;
              when time >= 0.5 then
                reinit(r.v[2],pre(r.v[1]));
                r.d[1]=pre(r.d[2])+1;
                r.d[2]=pre(r.d[1])+2;
              end when;
            end M;
            end P;
            """
        )
        sys = parse_basemodelica(file; parser, arrays)
        sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5(); reltol = 1.0e-10, abstol = 1.0e-12)
        @test sol.retcode == ReturnCode.Success
        vars = arrays == :keep ? getproperty(sys, Symbol("r.v")) : [getproperty(sys, Symbol("r.v[$i]")) for i in 1:2]
        @test sol(1.0; idxs = vars) ≈ fill(exp(-1), 2) rtol = 1.0e-8
        discs = arrays == :keep ? getproperty(sys, Symbol("r.d")) : [getproperty(sys, Symbol("r.d[$i]")) for i in 1:2]
        @test sol(1.0; idxs = discs) == [1, 2]
    end
end
nothing

@testset "Element guesses on record fields ($parser)" for parser in (:julia, :antlr)
    file = tempname() * ".bmo"
    write(
        file, """
        //! base 0.1.0
        package P
        record R
          Real x[2];
          Real y[2];
        end R;
        model M
          R r;
          parameter equation guess(r.x[1])=1;
        equation
          r.x={1,2};
          r.y={3,4};
        end M;
        end P;
        """
    )
    raw = parse_basemodelica(file; parser, arrays = :keep, simplify = false)
    @test hasproperty(raw, Symbol("r.x[1]"))
    @test size(getproperty(raw, Symbol("r.y"))) == (2,)
end
nothing
