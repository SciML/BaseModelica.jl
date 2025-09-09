using Pkg
Pkg.activate(".")

# Test just the identifier part first
include("src/parser.jl")

# Test just the IDENT pattern
test_ident = "'Comment'"
println("Testing IDENT parsing with: ", test_ident)
try
    using ParserCombinator
    PC = ParserCombinator
    result = only(PC.parse_one(test_ident, IDENT))
    println("✅ IDENT result: ", result)
    println("Type: ", typeof(result))
    if hasfield(typeof(result), :name)
        println("Name field: ", result.name)
    end
catch e
    println("❌ IDENT parsing failed: ", e)
end

# Test the comment string
test_comment = "//! base 0.1.0\npackage 'Comment'"  
println("\nTesting comment parsing with: ", repr(test_comment))
try
    using ParserCombinator
    PC = ParserCombinator
    result = only(PC.parse_one(test_comment, initial_spc_and_comments + E"package" + spc + IDENT))
    println("✅ Comment + package + ident result: ", result)
    println("Type: ", typeof(result))
catch e
    println("❌ Comment parsing failed: ", e)
end