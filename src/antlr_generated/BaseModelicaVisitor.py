# Generated from /home/jadonclugston/Documents/Work/dev/Modelica/BaseModelica.jl/grammar/BaseModelica.g4 by ANTLR 4.13.1
from antlr4 import *
if "." in __name__:
    from .BaseModelicaParser import BaseModelicaParser
else:
    from BaseModelicaParser import BaseModelicaParser

# This class defines a complete generic visitor for a parse tree produced by BaseModelicaParser.

class BaseModelicaVisitor(ParseTreeVisitor):

    # Visit a parse tree produced by BaseModelicaParser#baseModelica.
    def visitBaseModelica(self, ctx:BaseModelicaParser.BaseModelicaContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#versionHeader.
    def visitVersionHeader(self, ctx:BaseModelicaParser.VersionHeaderContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#classDefinition.
    def visitClassDefinition(self, ctx:BaseModelicaParser.ClassDefinitionContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#classPrefixes.
    def visitClassPrefixes(self, ctx:BaseModelicaParser.ClassPrefixesContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#classSpecifier.
    def visitClassSpecifier(self, ctx:BaseModelicaParser.ClassSpecifierContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#longClassSpecifier.
    def visitLongClassSpecifier(self, ctx:BaseModelicaParser.LongClassSpecifierContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#shortClassSpecifier.
    def visitShortClassSpecifier(self, ctx:BaseModelicaParser.ShortClassSpecifierContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#derClassSpecifier.
    def visitDerClassSpecifier(self, ctx:BaseModelicaParser.DerClassSpecifierContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#basePrefix.
    def visitBasePrefix(self, ctx:BaseModelicaParser.BasePrefixContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#enumList.
    def visitEnumList(self, ctx:BaseModelicaParser.EnumListContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#enumerationLiteral.
    def visitEnumerationLiteral(self, ctx:BaseModelicaParser.EnumerationLiteralContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#composition.
    def visitComposition(self, ctx:BaseModelicaParser.CompositionContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#languageSpecification.
    def visitLanguageSpecification(self, ctx:BaseModelicaParser.LanguageSpecificationContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#externalFunctionCall.
    def visitExternalFunctionCall(self, ctx:BaseModelicaParser.ExternalFunctionCallContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#genericElement.
    def visitGenericElement(self, ctx:BaseModelicaParser.GenericElementContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#normalElement.
    def visitNormalElement(self, ctx:BaseModelicaParser.NormalElementContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#parameterEquation.
    def visitParameterEquation(self, ctx:BaseModelicaParser.ParameterEquationContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#guessValue.
    def visitGuessValue(self, ctx:BaseModelicaParser.GuessValueContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#basePartition.
    def visitBasePartition(self, ctx:BaseModelicaParser.BasePartitionContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#subPartition.
    def visitSubPartition(self, ctx:BaseModelicaParser.SubPartitionContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#clockClause.
    def visitClockClause(self, ctx:BaseModelicaParser.ClockClauseContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#componentClause.
    def visitComponentClause(self, ctx:BaseModelicaParser.ComponentClauseContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#globalConstant.
    def visitGlobalConstant(self, ctx:BaseModelicaParser.GlobalConstantContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#typePrefix.
    def visitTypePrefix(self, ctx:BaseModelicaParser.TypePrefixContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#componentList.
    def visitComponentList(self, ctx:BaseModelicaParser.ComponentListContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#componentDeclaration.
    def visitComponentDeclaration(self, ctx:BaseModelicaParser.ComponentDeclarationContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#declaration.
    def visitDeclaration(self, ctx:BaseModelicaParser.DeclarationContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#modification.
    def visitModification(self, ctx:BaseModelicaParser.ModificationContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#classModification.
    def visitClassModification(self, ctx:BaseModelicaParser.ClassModificationContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#argumentList.
    def visitArgumentList(self, ctx:BaseModelicaParser.ArgumentListContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#argument.
    def visitArgument(self, ctx:BaseModelicaParser.ArgumentContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#elementModificationOrReplaceable.
    def visitElementModificationOrReplaceable(self, ctx:BaseModelicaParser.ElementModificationOrReplaceableContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#elementModification.
    def visitElementModification(self, ctx:BaseModelicaParser.ElementModificationContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#equation.
    def visitEquation(self, ctx:BaseModelicaParser.EquationContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#initialEquation.
    def visitInitialEquation(self, ctx:BaseModelicaParser.InitialEquationContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#statement.
    def visitStatement(self, ctx:BaseModelicaParser.StatementContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#ifEquation.
    def visitIfEquation(self, ctx:BaseModelicaParser.IfEquationContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#ifStatement.
    def visitIfStatement(self, ctx:BaseModelicaParser.IfStatementContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#forEquation.
    def visitForEquation(self, ctx:BaseModelicaParser.ForEquationContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#forStatement.
    def visitForStatement(self, ctx:BaseModelicaParser.ForStatementContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#forIndex.
    def visitForIndex(self, ctx:BaseModelicaParser.ForIndexContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#whileStatement.
    def visitWhileStatement(self, ctx:BaseModelicaParser.WhileStatementContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#whenEquation.
    def visitWhenEquation(self, ctx:BaseModelicaParser.WhenEquationContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#whenStatement.
    def visitWhenStatement(self, ctx:BaseModelicaParser.WhenStatementContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#prioritizeEquation.
    def visitPrioritizeEquation(self, ctx:BaseModelicaParser.PrioritizeEquationContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#prioritizeExpression.
    def visitPrioritizeExpression(self, ctx:BaseModelicaParser.PrioritizeExpressionContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#priority.
    def visitPriority(self, ctx:BaseModelicaParser.PriorityContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#decoration.
    def visitDecoration(self, ctx:BaseModelicaParser.DecorationContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#expression.
    def visitExpression(self, ctx:BaseModelicaParser.ExpressionContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#expressionNoDecoration.
    def visitExpressionNoDecoration(self, ctx:BaseModelicaParser.ExpressionNoDecorationContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#ifExpression.
    def visitIfExpression(self, ctx:BaseModelicaParser.IfExpressionContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#simpleExpression.
    def visitSimpleExpression(self, ctx:BaseModelicaParser.SimpleExpressionContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#logicalExpression.
    def visitLogicalExpression(self, ctx:BaseModelicaParser.LogicalExpressionContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#logicalTerm.
    def visitLogicalTerm(self, ctx:BaseModelicaParser.LogicalTermContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#logicalFactor.
    def visitLogicalFactor(self, ctx:BaseModelicaParser.LogicalFactorContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#relation.
    def visitRelation(self, ctx:BaseModelicaParser.RelationContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#relationalOperator.
    def visitRelationalOperator(self, ctx:BaseModelicaParser.RelationalOperatorContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#arithmeticExpression.
    def visitArithmeticExpression(self, ctx:BaseModelicaParser.ArithmeticExpressionContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#addOperator.
    def visitAddOperator(self, ctx:BaseModelicaParser.AddOperatorContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#term.
    def visitTerm(self, ctx:BaseModelicaParser.TermContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#mulOperator.
    def visitMulOperator(self, ctx:BaseModelicaParser.MulOperatorContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#factor.
    def visitFactor(self, ctx:BaseModelicaParser.FactorContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#primary.
    def visitPrimary(self, ctx:BaseModelicaParser.PrimaryContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#typeSpecifier.
    def visitTypeSpecifier(self, ctx:BaseModelicaParser.TypeSpecifierContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#name.
    def visitName(self, ctx:BaseModelicaParser.NameContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#componentReference.
    def visitComponentReference(self, ctx:BaseModelicaParser.ComponentReferenceContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#functionCallArgs.
    def visitFunctionCallArgs(self, ctx:BaseModelicaParser.FunctionCallArgsContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#functionArguments.
    def visitFunctionArguments(self, ctx:BaseModelicaParser.FunctionArgumentsContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#functionArgumentsNonFirst.
    def visitFunctionArgumentsNonFirst(self, ctx:BaseModelicaParser.FunctionArgumentsNonFirstContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#arrayArguments.
    def visitArrayArguments(self, ctx:BaseModelicaParser.ArrayArgumentsContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#namedArguments.
    def visitNamedArguments(self, ctx:BaseModelicaParser.NamedArgumentsContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#namedArgument.
    def visitNamedArgument(self, ctx:BaseModelicaParser.NamedArgumentContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#functionArgument.
    def visitFunctionArgument(self, ctx:BaseModelicaParser.FunctionArgumentContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#functionPartialApplication.
    def visitFunctionPartialApplication(self, ctx:BaseModelicaParser.FunctionPartialApplicationContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#outputExpressionList.
    def visitOutputExpressionList(self, ctx:BaseModelicaParser.OutputExpressionListContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#expressionList.
    def visitExpressionList(self, ctx:BaseModelicaParser.ExpressionListContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#arraySubscripts.
    def visitArraySubscripts(self, ctx:BaseModelicaParser.ArraySubscriptsContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#subscript.
    def visitSubscript(self, ctx:BaseModelicaParser.SubscriptContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#comment.
    def visitComment(self, ctx:BaseModelicaParser.CommentContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#stringComment.
    def visitStringComment(self, ctx:BaseModelicaParser.StringCommentContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by BaseModelicaParser#annotationComment.
    def visitAnnotationComment(self, ctx:BaseModelicaParser.AnnotationCommentContext):
        return self.visitChildren(ctx)



del BaseModelicaParser