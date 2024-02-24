function display_machine(m::Automa.Machine)
    open("/tmp/machine.dot", "w") do io
        println(io, Automa.machine2dot(m))
    end
    run(pipeline(`dot -Tsvg /tmp/machine.dot`, stdout = "/tmp/machine.svg"))
    run(`firefox /tmp/machine.svg`)
end
