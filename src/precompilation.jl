@setup_workload begin
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

    @compile_workload begin
        parse_basemodelica(path; parser = :julia)
    end

    rm(path; force = true)
end
