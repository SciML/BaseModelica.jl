#!/bin/bash
# Build script for generating ANTLR4 Python parser

set -e

# Configuration
ANTLR_VERSION="4.13.1"
ANTLR_JAR="antlr-${ANTLR_VERSION}-complete.jar"
ANTLR_URL="https://www.antlr.org/download/antlr-${ANTLR_VERSION}-complete.jar"
GRAMMAR_FILE="./grammar/BaseModelica.g4"
OUTPUT_DIR="../src/antlr_generated"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}BaseModelica ANTLR4 Parser Builder${NC}"
echo "========================================"

# Check if ANTLR JAR exists, download if not
if [ ! -f "$ANTLR_JAR" ]; then
    echo -e "${YELLOW}ANTLR JAR not found. Downloading...${NC}"
    wget -q "$ANTLR_URL" -O "$ANTLR_JAR"
    echo -e "${GREEN}Downloaded ANTLR ${ANTLR_VERSION}${NC}"
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Generate Python parser
echo -e "${GREEN}Generating Python parser from grammar...${NC}"
java -jar "$ANTLR_JAR" \
    -Dlanguage=Python3 \
    -o "$OUTPUT_DIR" \
    -visitor \
    -listener \
    "$GRAMMAR_FILE"

# Create __init__.py for Python package
echo -e "${GREEN}Creating Python package files...${NC}"
cat > "$OUTPUT_DIR/__init__.py" << 'EOF'
"""
ANTLR4-generated parser for BaseModelica
"""
from .BaseModelicaLexer import BaseModelicaLexer
from .BaseModelicaParser import BaseModelicaParser
from .BaseModelicaVisitor import BaseModelicaVisitor
from .BaseModelicaListener import BaseModelicaListener

__all__ = [
    'BaseModelicaLexer',
    'BaseModelicaParser',
    'BaseModelicaVisitor',
    'BaseModelicaListener',
]
EOF

echo -e "${GREEN}Build complete!${NC}"
echo "Generated files are in: $OUTPUT_DIR"
echo ""
echo "Generated Python files:"
echo "  - BaseModelicaLexer.py"
echo "  - BaseModelicaParser.py"
echo "  - BaseModelicaVisitor.py"
echo "  - BaseModelicaListener.py"
echo "  - __init__.py"
echo ""
echo "The parser is ready to use with PythonCall.jl"
