# ANTLR4 Parser for BaseModelica

This directory contains the ANTLR4 grammar definition and build tools for creating a parser for BaseModelica using ANTLR4. NOTE: this is only needed for people who are developing the package and need to regenerate the parsing code. A normal user does not need to follow any of these steps. 


## Prerequisites

1. **Java Development Kit (JDK)**: Version 8 or higher (only needed for building, not runtime)
   ```bash
   # Check if Java is installed
   java -version

   # Install on Ubuntu/Debian
   sudo apt install openjdk-17-jdk

   # Install on macOS
   brew install openjdk@17
   ```

2. **Julia**: Version 1.9 or higher
   - BaseModelica.jl automatically manages Python dependencies via CondaPkg.jl
   - No manual Python installation required!
   - CondaPkg will create an isolated Python environment for you

## Building the Parser

1. **Navigate to the grammar directory**:
   ```bash
   cd grammar
   ```

2. **Run the build script**:
   ```bash
   ./build_parser.sh
   ```

   This script will:
   - Download ANTLR 4.13.1 if not already present
   - Generate Python lexer and parser from `BaseModelica.g4`
   - Create a Python package structure with `__init__.py`

3. **Verify the build**:
   ```bash
   ls ../src/antlr_generated/
   # Should see: BaseModelicaLexer.py, BaseModelicaParser.py,
   #             BaseModelicaVisitor.py, BaseModelicaListener.py, __init__.py
   ```

## Using the ANTLR Parser in Julia

### First-Time Setup

When you first use the ANTLR parser, CondaPkg will automatically:
1. Create an isolated Python environment
2. Install `antlr4-python3-runtime==4.13.1`
3. Set up everything needed for PythonCall

This happens automatically on first import - no manual steps needed!

### Basic Usage

```julia
using BaseModelica

# Initialize the ANTLR parser (first time only, or after rebuilding)
# On first run, CondaPkg will set up Python dependencies automatically
BaseModelica.init_antlr_parser()

# Parse a file
ast = parse_file_with_antlr("path/to/model.mo")

# Convert to ModelingToolkit
sys = baseModelica_to_ModelingToolkit(ast)
```

### Switching Between Parsers

The original ParserCombinator parser is still available. You can choose which to use:

```julia
# Use ParserCombinator parser (original)
ast1 = BM.parse_file("model.mo")

# Use ANTLR parser (new)
ast2 = parse_file_with_antlr("model.mo")

# Both produce the same BaseModelicaPackage AST type
```

### Advanced: Parse to ANTLR tree only

```julia
using BaseModelica
using PythonCall

# Initialize
BaseModelica.init_antlr_parser()

# Parse to ANTLR tree (Python object)
source = read("model.mo", String)
parse_tree = BaseModelica.parse_with_antlr(source)

# Inspect the tree structure
println(parse_tree.toStringTree())

# Convert to BaseModelica AST (when implemented)
ast = BaseModelica.antlr_tree_to_ast(parse_tree)
```

## Development

### Modifying the Grammar

1. Edit `BaseModelica.g4`
2. Run `./build_parser.sh` to regenerate
3. Restart your Julia session to reload the parser
4. Test with `parse_file_with_antlr()`

### Testing the Grammar

You can test the ANTLR grammar directly with the ANTLR TestRig (grun):

```bash
# In the grammar directory
export CLASSPATH=".:antlr-4.13.1-complete.jar:$CLASSPATH"

# Create test input
cat > test.mo << 'EOF'
package Test
  model SimpleModel
    Real x;
  equation
    der(x) = -x;
  end SimpleModel;
end Test;
EOF

# Generate and run
java -jar antlr-4.13.1-complete.jar -Dlanguage=Python3 BaseModelica.g4
python3 << 'PYTHON'
from antlr4 import *
from BaseModelicaLexer import BaseModelicaLexer
from BaseModelicaParser import BaseModelicaParser

with open('test.mo', 'r') as f:
    input_stream = InputStream(f.read())

lexer = BaseModelicaLexer(input_stream)
stream = CommonTokenStream(lexer)
parser = BaseModelicaParser(stream)
tree = parser.baseModelicaPackage()
print(tree.toStringTree(recog=parser))
PYTHON
```

### Debugging Parse Errors

```bash
# Show tokens
python3 << 'PYTHON'
from antlr4 import *
from BaseModelicaLexer import BaseModelicaLexer

with open('model.mo', 'r') as f:
    lexer = BaseModelicaLexer(InputStream(f.read()))
    for token in lexer.getAllTokens():
        print(token)
PYTHON
```

You can also use ANTLR's Java-based tools:

```bash
# GUI parse tree viewer (requires X11)
java -cp antlr-4.13.1-complete.jar:../src/antlr_generated org.antlr.v4.gui.TestRig \
  BaseModelica baseModelicaPackage -gui < model.mo

# Text tree
java -cp antlr-4.13.1-complete.jar:../src/antlr_generated org.antlr.v4.gui.TestRig \
  BaseModelica baseModelicaPackage -tree < model.mo
```

## Current Status

### ✅ Completed
- [x] Initial ANTLR4 grammar for BaseModelica
- [x] Build script for Python parser generation
- [x] PythonCall integration infrastructure
- [x] Basic parse tree generation

### 🚧 In Progress
- [ ] AST bridge visitor implementation (`antlr_tree_to_ast`)
- [ ] Complete test coverage
- [ ] Performance benchmarking vs ParserCombinator

### 📋 TODO
- [ ] Implement visitor for all AST node types
- [ ] Handle edge cases (annotations, external functions, etc.)
- [ ] Add comprehensive error handling
- [ ] Document performance improvements
- [ ] Consider making ANTLR parser the default

## Implementation Notes

### AST Bridge Strategy

The `antlr_tree_to_ast()` function needs to be implemented as a visitor that:

1. **Traverses the ANTLR parse tree** (Python objects via PythonCall)
2. **Extracts relevant information** from each node
3. **Creates corresponding BaseModelica AST nodes** (Julia structs)
4. **Recursively processes children**

Example implementation approach:

```julia
# In Julia, create a visitor-like function that pattern matches on node types
function visit_node(ctx::Py)
    # Get the rule name/type
    rule_name = pyconvert(String, ctx.__class__.__name__)

    if rule_name == "BaseModelicaPackageContext"
        # Extract package components
        name = visit_node(ctx.name(0))
        composition = visit_node(ctx.composition())
        return BaseModelicaPackage(name, composition)
    elseif rule_name == "ComponentClauseContext"
        # Handle component clauses
        # ...
    end
    # ... handle all node types
end
```

Alternatively, you could write a Python visitor that creates a simplified JSON/dict representation, then convert that to Julia AST types:

```python
# Python visitor (could be generated or hand-written)
class ASTBuilder(BaseModelicaVisitor):
    def visitBaseModelicaPackage(self, ctx):
        return {
            'type': 'package',
            'name': ctx.name(0).getText(),
            'composition': self.visit(ctx.composition())
        }
    # ... other visit methods
```

Then in Julia:
```julia
ast_dict = visitor.visit(parse_tree)  # Returns Python dict
ast = dict_to_basemodelica_ast(pyconvert(Dict, ast_dict))
```

The Julia-only approach is recommended for:
- Easier debugging (stay in one language)
- Direct access to BaseModelica AST constructors
- No serialization overhead

The Python helper approach might be better for:
- Leveraging Python's visitor pattern
- Easier to test incrementally
- Can use ANTLR's built-in visitor features

## Performance Comparison (TODO)

Once implemented, compare parsing performance:

```julia
using BenchmarkTools

# ParserCombinator (original)
@btime BM.parse_file("CauerLowPassAnalog.bmo")

# ANTLR4 (new)
@btime parse_file_with_antlr("CauerLowPassAnalog.bmo")
```

Expected improvements:
- **Small files**: Similar performance (some Python/Julia bridge overhead)
- **Medium files**: 2-5x faster
- **Large/complex files** (like ChuaCircuit): 10-100x faster (avoids exponential backtracking)

## References

- [ANTLR4 Documentation](https://github.com/antlr/antlr4/blob/master/doc/index.md)
- [ANTLR4 Python Target](https://github.com/antlr/antlr4/blob/master/doc/python-target.md)
- [PythonCall.jl Documentation](https://github.com/JuliaPy/PythonCall.jl)
- [BaseModelica Specification](https://github.com/modelica/newsletter/issues/17)

## Troubleshooting

### "Java not found"
Install JDK 8 or higher (see Prerequisites). Only needed for building the parser, not runtime.

### "Generated parser not found"
Run `./build_parser.sh` from the `grammar` directory

### CondaPkg is installing packages slowly
On first run, CondaPkg needs to download and install Python and the ANTLR runtime. This is a one-time setup and takes 1-2 minutes. Subsequent uses are instant.

### Forcing CondaPkg to reinstall
If you encounter Python environment issues:
```julia
using CondaPkg
CondaPkg.resolve()  # Reset and reinstall Python environment
```

### Using a different Python installation
By default, CondaPkg creates an isolated environment. If you want to use system Python instead:
```julia
# Not recommended - CondaPkg isolation is preferred
ENV["JULIA_CONDAPKG_BACKEND"] = "Null"
ENV["JULIA_PYTHONCALL_EXE"] = "/usr/bin/python3"
```

### Parse errors in valid BaseModelica code
The grammar may need adjustment. Please open an issue with the input file.

### "Module 'BaseModelicaLexer' not found"
Make sure the generated files are in `src/antlr_generated/` and have proper `__init__.py`:
```bash
ls -la ../src/antlr_generated/
# Should show: __init__.py and Base*.py files
```

## Why PythonCall + CondaPkg instead of JavaCall?

**PythonCall.jl** provides better interoperability with Julia:
- **Automatic type conversion**: Seamless conversion between Julia and Python types
- **Less boilerplate**: Simpler API than JavaCall
- **Better integration**: Feels more native to Julia
- **Active development**: PythonCall is actively maintained
- **No JVM overhead**: Python runtime is lighter than JVM for this use case

**CondaPkg.jl** makes dependency management effortless:
- **Isolated environment**: No conflicts with system Python
- **Automatic installation**: Users don't need to manually install Python packages
- **Reproducible**: Same environment across all machines
- **Cross-platform**: Works on Linux, macOS, and Windows
- **Version control**: Pin exact versions (like `antlr4-python3-runtime==4.13.1`)
