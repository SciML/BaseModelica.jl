using Pkg
Pkg.activate(".")
using BaseModelica

# Test the fix for issue #34 - parsing comments before package definition
println("Testing fix for comments before package...")

try
    # This should work now with our fix
    result = BaseModelica.parse_file("test/testfiles/CommentBeforePackage.mo")
    println("✅ SUCCESS: Parsed file with comment before package")
    println("Package name: ", result.name)
    println("Result type: ", typeof(result))
catch e
    println("❌ FAILED: ", e)
end
