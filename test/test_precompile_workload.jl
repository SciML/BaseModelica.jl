using BaseModelica
using ModelingToolkitBase: System
using Test

source = """//! base 0.1.0
package Tiny
  model Tiny
    Real x;
  equation
    der(x) = -x;
  end Tiny;
end Tiny;
"""

path, io = mktemp()
write(io, source)
close(io)

try
    @testset "Precompile workload" begin
        @test BaseModelica.parse_basemodelica(path; parser = :julia) isa System
    end
finally
    rm(path; force = true)
end
