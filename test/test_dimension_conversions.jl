using Test, BaseModelica, ModelingToolkit, OrdinaryDiffEq

const BM = BaseModelica

@testset "Modelica dimensionality conversions" begin
    builtin(name, args...) = BM.call_builtin(name, Any[args...])
    @testset "Scalars and singleton dimensions" begin
        for x in (2.5, true, "ab")
            @test builtin(:scalar, x) === x
            @test builtin(:scalar, fill(x, 1, 1, 1)) === x
            @test builtin(:vector, x) == [x]
            @test builtin(:matrix, x) == fill(x, 1, 1)
            @test builtin(:promote, x, 0) === x
            @test builtin(:promote, x, 3) == fill(x, 1, 1, 1)
        end
        @test_throws BM.UnsupportedFeatureError builtin(:scalar, [1, 2])
        @test_throws BM.UnsupportedFeatureError builtin(:scalar, zeros(0, 1))
    end
    @testset "Ranks, order and empty arrays" begin
        v = [1, 2, 3]
        A = [1 2; 3 4; 5 6]
        @test builtin(:promote, v, 1) == v
        @test builtin(:promote, v, 2) == reshape(v, 3, 1)
        @test builtin(:promote, A, 2) == A
        @test builtin(:promote, A, 4) == reshape(A, 3, 2, 1, 1)
        @test builtin(:vector, reshape(v, 1, 3, 1)) == v
        @test builtin(:vector, reshape(v, 3, 1, 1)) == v
        @test builtin(:matrix, v) == reshape(v, 3, 1)
        @test builtin(:matrix, reshape(A, 3, 2, 1, 1)) == A
        @test size(builtin(:promote, zeros(0, 2), 3)) == (0, 2, 1)
        @test size(builtin(:matrix, zeros(0, 2, 1))) == (0, 2)
        @test size(builtin(:vector, zeros(0, 1))) == (0,)
        @test_throws BM.UnsupportedFeatureError builtin(:promote, A, 1)
        @test_throws BM.UnsupportedFeatureError builtin(:promote, 1, -1)
        @test_throws BM.UnsupportedFeatureError builtin(:promote, v, 2.5)
        @test_throws BM.UnsupportedFeatureError builtin(:vector, A)
        @test_throws BM.UnsupportedFeatureError builtin(:matrix, zeros(1, 1, 2))
        @test_throws BM.UnsupportedFeatureError builtin(:matrix, zeros(1, 1, 0))
    end
    @testset "Symbolic arrays retain elements and shape" begin
        @variables q[1:3] r
        @test size(builtin(:promote, q, 3)) == (3, 1, 1)
        @test isequal(builtin(:promote, q, 3)[2, 1, 1], q[2])
        @test isequal(builtin(:matrix, builtin(:promote, q, 3))[3, 1], q[3])
        @test isequal(builtin(:vector, builtin(:promote, q, 3))[1], q[1])
        @test isequal(builtin(:scalar, builtin(:promote, r, 2)), r)
        @test_throws BM.UnsupportedFeatureError builtin(:promote, q, r)
    end
end

function conversion_member(sys, name, indices...)
    hasproperty(sys, Symbol(name)) && return getproperty(sys, Symbol(name))[indices...]
    return getproperty(sys, Symbol("$name[$(join(indices, ','))]"))
end

@testset "Conversion builtin integration ($parser, $arrays)" for parser in (:julia, :antlr), arrays in (:scalarize, :keep)
    # The column conversion and its transpose occur in unpatched MultiBody output.
    source = """
    //! base 0.1.0
    package P
      model M
        parameter Integer n = 2;
        Real x[3](start = {1, 2, 3}, each fixed = true);
        Real col[3, 1];
        Real back[3];
        Real m[2, 2];
        Real selected;
        Real norm2;
      equation
        der(x) = -x;
        col = promote(x, n);
        back = vector(matrix(promote(x, 3)));
        m = matrix(promote([1, 2; 3, 4], 4));
        selected = scalar(promote(x[2], 3));
        norm2 = scalar(transpose(promote(x, 2)) * promote(x, 2));
      end M;
    end P;
    """
    mktemp() do path, io
        write(io, source)
        close(io)
        sys = parse_basemodelica(path; parser, arrays)
        sol = solve(ODEProblem(sys, [], (0.0, 1.0)), Tsit5(); reltol = 1e-9, abstol = 1e-11)
        @test sol.retcode == ReturnCode.Success
        for t in (0.0, 0.5, 1.0)
            for i in 1:3
                @test sol(t; idxs = conversion_member(sys, "col", i, 1)) ≈ i * exp(-t) atol = 1e-8
                @test sol(t; idxs = conversion_member(sys, "back", i)) ≈ i * exp(-t) atol = 1e-8
            end
            @test sol(t; idxs = sys.selected) ≈ 2 * exp(-t) atol = 1e-8
            @test sol(t; idxs = sys.norm2) ≈ 14 * exp(-2t) atol = 1e-8
        end
        @test sol(1.0; idxs = conversion_member(sys, "m", 1, 2)) == 2
        @test sol(1.0; idxs = conversion_member(sys, "m", 2, 1)) == 3
    end
end
