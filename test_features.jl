#!/usr/bin/env julia

using ParserCombinator
using MLStyle

include("src/parser.jl")

# Test different features that might be causing parsing issues

function test_feature(name, code)
    println("Testing: $name")
    try
        result = parse_str(code)
        println("  ✓ SUCCESS")
        return true
    catch e
        println("  ✗ FAILED: $e")
        return false
    end
end

# Test 1: Simple package without comment prefix
simple_package = """
package 'Test'
  model 'Test'
    Real x;
  equation
    x = 1.0;
  end 'Test';
end 'Test';
"""

# Test 2: Package with comment prefix
package_with_comment = """
//! base 0.1.0
package 'Test'
  model 'Test'
    Real x;
  equation
    x = 1.0;
  end 'Test';
end 'Test';
"""

# Test 3: Final parameter
final_parameter = """
package 'Test'
  model 'Test'
    final parameter Boolean flag = false;
  equation
  end 'Test';
end 'Test';
"""

# Test 4: Complex parameter modifications
complex_parameter = """
package 'Test'
  model 'Test'
    parameter Real 'T_ref'(nominal = 300.0, start = 288.15, min = 0.0, displayUnit = "degC", unit = "K", quantity = "ThermodynamicTemperature") = 300.15 "Reference temperature";
  equation
  end 'Test';
end 'Test';
"""

# Test 5: Assert function
assert_test = """
package 'Test'
  model 'Test'
    Real x;
  equation
    x = 1.0;
    assert(x > 0.0, "x must be positive", AssertionLevel.error);
  end 'Test';
end 'Test';
"""

# Test 6: Conditional expression
conditional_test = """
package 'Test'
  model 'Test'
    Real y;
    Real x = 2.0;
  equation
    y = if x > 1.0 then 2.0 * x else x;
  end 'Test';
end 'Test';
"""

# Test 7: Annotation
annotation_test = """
package 'Test'
  model 'Test'
    final parameter Boolean flag = false annotation(Evaluate = true);
  equation
  end 'Test';
end 'Test';
"""

# Run tests
test_feature("Simple package", simple_package)
test_feature("Package with comment prefix", package_with_comment)
test_feature("Final parameter", final_parameter)
test_feature("Complex parameter modifications", complex_parameter)
test_feature("Assert function", assert_test)
test_feature("Conditional expression", conditional_test)  
test_feature("Annotation", annotation_test)