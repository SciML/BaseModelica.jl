using Pkg
Pkg.activate(".")

# Load only the parser components directly
include("src/parser.jl")

# Test the example from the issue
test_content = """//! base 0.1.0
package 'Comment'
  model 'Comment'
    Real 'x';
  equation
    der('x') = 'x';
  end 'Comment';
end 'Comment';"""

println("Testing parsing with comments before package...")
try
    result = parse_str(test_content)
    println("✅ SUCCESS: Parsed content with comment before package")
    println("Result type: ", typeof(result))
    println("Package name: ", result.name)
catch e
    println("❌ FAILED: ", e)
end
