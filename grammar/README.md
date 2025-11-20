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

## Development

### Modifying the Grammar

1. Edit `BaseModelica.g4`
2. Run `./build_parser.sh` to regenerate
3. Restart your Julia session to reload the parser
4. Test with `parse_file_antlr()`

