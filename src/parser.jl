using Automa

struct BaseModelicaModel

end

struct BaseModelicaParameter
    type
    name
    value
    description
end

struct BaseModelicaVariable
    type
    name
    description
end

struct BaseModelicaEquation

end

struct BaseModelicaInitialEquation

end


base_Modelica_machine = let 
    type = re"Real"
    name = re"'[ -~]+'"
    value = re" ?(=? ?[0-9]+\.?[0-9]*)?"
    description = re" ?(\"([ -~]|\n)*\")?;"
    parameter = re"parameter" * ' ' * type * ' ' * name * value * description
    #parameter Real '[ -~]+' ?(=? ?[\d]+.?[\d]*)? ?("([ -~]|\n)*")?;$
end

base_Modelica_actions = Dict(
    :mark_name        => :(mark_name = p),
    :get_identifier  => :(identifier = String(data[mark:p-1]); mark = 0),

)


context = CodeGenContext(generator=:goto)
@eval function parse_BaseModelica(data::AbstractVector{UInt8})
    # Initialize variables you use in the action code.
    records = FASTARecord[]
    mark = 0
    seqlen = 0
    record_seen = false
    identifier = ""
    description = nothing
    buffer = UInt8[]

    # Generate code for initialization and main loop
    $(generate_code(context, fasta_machine, fasta_actions))
    record_seen && push!(records, FASTARecord(identifier, description, String(buffer[1:seqlen])))

    # Finally, return records accumulated in the action code.
    return records
end