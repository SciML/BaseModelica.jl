grammar BaseModelica;

// ============================================================================
// Parser Rules - Translated from BaseModelica Specification
// https://github.com/modelica/ModelicaSpecification/blob/MCP/0031/RationaleMCP/0031/grammar.md
// ============================================================================

// Start Rule
baseModelica
    : versionHeader 'package' IDENT
      (decoration? classDefinition ';' | decoration? globalConstant ';')*
      decoration? 'model' longClassSpecifier ';'
      (annotationComment ';')?
      'end' IDENT ';'
    ;

versionHeader
    : VERSION_HEADER
    ;

// Class Definition (B22)
classDefinition
    : classPrefixes classSpecifier
    ;

classPrefixes
    : 'type'
    | 'operator'? 'record'
    | (('pure' 'constant'?) | 'impure')? 'operator'? 'function'
    ;

classSpecifier
    : longClassSpecifier
    | shortClassSpecifier
    | derClassSpecifier
    ;

longClassSpecifier
    : IDENT stringComment composition 'end' IDENT
    ;

shortClassSpecifier
    : IDENT '=' (basePrefix? typeSpecifier classModification?
                 | 'enumeration' '(' (enumList? | ':') ')') comment
    ;

derClassSpecifier
    : IDENT '=' 'der' '(' typeSpecifier ',' IDENT (',' IDENT)* ')' comment
    ;

basePrefix
    : 'input'
    | 'output'
    ;

enumList
    : enumerationLiteral (',' enumerationLiteral)*
    ;

enumerationLiteral
    : IDENT comment
    ;

composition
    : (decoration? genericElement ';')*
      ('equation' (equation ';')*
      | 'initial' 'equation' (initialEquation ';')*
      | 'initial'? 'algorithm' (statement ';')*)*
      (decoration? 'external' languageSpecification? externalFunctionCall? annotationComment? ';')?
      basePartition*
      (annotationComment ';')?
    ;

languageSpecification
    : STRING
    ;

externalFunctionCall
    : (componentReference '=')? IDENT '(' expressionList? ')'
    ;

genericElement
    : normalElement
    | parameterEquation
    ;

normalElement
    : componentClause
    ;

parameterEquation
    : 'parameter' 'equation' guessValue '=' (expression | prioritizeExpression) comment
    ;

guessValue
    : 'guess' '(' componentReference ')'
    ;

// Clock Partitions
basePartition
    : 'partition' stringComment (annotationComment ';')?
      (clockClause ';')* subPartition*
    ;

subPartition
    : 'subpartition' '(' argumentList ')' stringComment (annotationComment ';')?
      ('equation' (equation ';')* | 'algorithm' (statement ';')*)*
    ;

clockClause
    : decoration? 'Clock' IDENT '=' expression comment
    ;

// Component Clause (B24)
componentClause
    : typePrefix typeSpecifier componentList
    ;

globalConstant
    : 'constant' typeSpecifier arraySubscripts? declaration comment
    ;

typePrefix
    : ('discrete' | 'parameter' | 'constant')? ('input' | 'output')?
    ;

componentList
    : componentDeclaration (',' componentDeclaration)*
    ;

componentDeclaration
    : declaration comment
    ;

declaration
    : IDENT arraySubscripts? modification?
    ;

// Modification (B25)
modification
    : classModification ('=' expression)?
    | '=' expression
    | ':=' expression
    ;

classModification
    : '(' argumentList? ')'
    ;

argumentList
    : argument (',' argument)*
    ;

argument
    : decoration? elementModificationOrReplaceable
    ;

elementModificationOrReplaceable
    : elementModification
    ;

elementModification
    : name modification? stringComment
    ;

// Equations (B26)
equation
    : decoration? (simpleExpression decoration? ('=' expression)?
                  | ifEquation
                  | forEquation
                  | whenEquation) comment
    ;

initialEquation
    : equation
    | prioritizeEquation
    ;

statement
    : decoration? (componentReference (':=' expression | functionCallArgs)
                  | '(' outputExpressionList ')' ':=' componentReference functionCallArgs
                  | 'break'
                  | 'return'
                  | ifStatement
                  | forStatement
                  | whileStatement
                  | whenStatement) comment
    ;

ifEquation
    : 'if' expression 'then' (equation ';')*
      ('elseif' expression 'then' (equation ';')*)*
      ('else' (equation ';')*)?
      'end' 'if'
    ;

ifStatement
    : 'if' expression 'then' (statement ';')*
      ('elseif' expression 'then' (statement ';')*)*
      ('else' (statement ';')*)?
      'end' 'if'
    ;

forEquation
    : 'for' forIndex 'loop' (equation ';')* 'end' 'for'
    ;

forStatement
    : 'for' forIndex 'loop' (statement ';')* 'end' 'for'
    ;

forIndex
    : IDENT 'in' expression
    ;

whileStatement
    : 'while' expression 'loop' (statement ';')* 'end' 'while'
    ;

whenEquation
    : 'when' expression 'then' (equation ';')*
      ('elsewhen' expression 'then' (equation ';')*)*
      'end' 'when'
    ;

whenStatement
    : 'when' expression 'then' (statement ';')*
      ('elsewhen' expression 'then' (statement ';')*)*
      'end' 'when'
    ;

prioritizeEquation
    : 'prioritize' '(' componentReference ',' priority ')'
    ;

prioritizeExpression
    : 'prioritize' '(' expression ',' priority ')'
    ;

priority
    : expression
    ;

// Expressions
decoration
    : '@' UNSIGNED_INTEGER
    ;

expression
    : expressionNoDecoration decoration?
    ;

expressionNoDecoration
    : simpleExpression
    | ifExpression
    ;

ifExpression
    : 'if' expressionNoDecoration 'then' expressionNoDecoration
      ('elseif' expressionNoDecoration 'then' expressionNoDecoration)*
      'else' expressionNoDecoration
    ;

simpleExpression
    : logicalExpression (':' logicalExpression (':' logicalExpression)?)?
    ;

logicalExpression
    : logicalTerm ('or' logicalTerm)*
    ;

logicalTerm
    : logicalFactor ('and' logicalFactor)*
    ;

logicalFactor
    : 'not'? relation
    ;

relation
    : arithmeticExpression (relationalOperator arithmeticExpression)?
    ;

relationalOperator
    : '<' | '<=' | '>' | '>=' | '==' | '<>'
    ;

arithmeticExpression
    : addOperator? term (addOperator term)*
    ;

addOperator
    : '+' | '-' | '.+' | '.-'
    ;

term
    : factor (mulOperator factor)*
    ;

mulOperator
    : '*' | '/' | '.*' | './'
    ;

factor
    : primary (('^' | '.^') primary)?
    ;

primary
    : UNSIGNED_NUMBER
    | STRING
    | 'false'
    | 'true'
    | ('der' | 'initial' | 'pure') functionCallArgs
    | componentReference functionCallArgs?
    | '(' outputExpressionList ')' arraySubscripts?
    | '[' expressionList (';' expressionList)* ']'
    | '{' arrayArguments '}'
    | 'end'
    ;

typeSpecifier
    : '.'? name
    ;

name
    : IDENT ('.' IDENT)*
    ;

componentReference
    : '.'? IDENT arraySubscripts? ('.' IDENT arraySubscripts?)*
    ;

functionCallArgs
    : '(' functionArguments? ')'
    ;

functionArguments
    : expression (',' functionArgumentsNonFirst | 'for' forIndex)?
    | functionPartialApplication (',' functionArgumentsNonFirst)?
    | namedArguments
    ;

functionArgumentsNonFirst
    : functionArgument (',' functionArgumentsNonFirst)?
    | namedArguments
    ;

arrayArguments
    : expression ((',' expression)* | 'for' forIndex)
    ;

namedArguments
    : namedArgument (',' namedArgument)*
    ;

namedArgument
    : IDENT '=' functionArgument
    ;

functionArgument
    : functionPartialApplication
    | expression
    ;

functionPartialApplication
    : 'function' typeSpecifier '(' namedArguments? ')'
    ;

outputExpressionList
    : expression? (',' expression?)*
    ;

expressionList
    : expression (',' expression)*
    ;

arraySubscripts
    : '[' subscript (',' subscript)* ']'
    ;

subscript
    : ':'
    | expression
    ;

comment
    : stringComment annotationComment?
    ;

stringComment
    : (STRING ('+' STRING)*)?
    ;

annotationComment
    : 'annotation' classModification
    ;

// ============================================================================
// Lexer Rules
// ============================================================================

// Version Header - must match exactly (does not consume trailing newline)
VERSION_HEADER
    : '//!' ' ' 'base' ' ' [0-9]+ '.' [0-9]+ ('.' [0-9]+)? ~[\r\n]*
    ;

// Identifiers
IDENT
    : NONDIGIT (DIGIT | NONDIGIT)*
    | Q_IDENT
    ;

fragment NONDIGIT
    : [_a-zA-Z]
    ;

fragment DIGIT
    : [0-9]
    ;

fragment Q_IDENT
    : '\'' (Q_CHAR | S_ESCAPE | '"')+ '\''
    ;

fragment Q_CHAR
    : NONDIGIT
    | DIGIT
    | [!#$%&()*+,\-./:;<>=?@[\\\]^{}|~ ]
    ;

// Numbers
UNSIGNED_NUMBER
    : DIGIT+ ('.' DIGIT*)? EXPONENT?
    ;

UNSIGNED_INTEGER
    : DIGIT+
    ;

fragment EXPONENT
    : [eE] [+\-]? DIGIT+
    ;

// Strings
STRING
    : '"' (S_CHAR | S_ESCAPE)* '"'
    ;

fragment S_CHAR
    : ~[\r\n\\"]
    | NL
    ;

fragment S_ESCAPE
    : '\\' ['"?\\abfnrtv]
    ;

fragment NL
    : '\r\n'
    | '\n'
    | '\r'
    ;

// Whitespace and Comments
WS
    : ([ \t] | NL)+ -> skip
    ;

LINE_COMMENT
    : '//' ~[!\r\n] ~[\r\n]* (NL | EOF) -> skip
    ;

ML_COMMENT
    : '/*' .*? '*/' -> skip
    ;
