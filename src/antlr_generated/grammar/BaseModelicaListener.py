# Generated from ./grammar/BaseModelica.g4 by ANTLR 4.13.1
from antlr4 import *
if "." in __name__:
    from .BaseModelicaParser import BaseModelicaParser
else:
    from BaseModelicaParser import BaseModelicaParser

# This class defines a complete listener for a parse tree produced by BaseModelicaParser.
class BaseModelicaListener(ParseTreeListener):

    # Enter a parse tree produced by BaseModelicaParser#baseModelica.
    def enterBaseModelica(self, ctx:BaseModelicaParser.BaseModelicaContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#baseModelica.
    def exitBaseModelica(self, ctx:BaseModelicaParser.BaseModelicaContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#versionHeader.
    def enterVersionHeader(self, ctx:BaseModelicaParser.VersionHeaderContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#versionHeader.
    def exitVersionHeader(self, ctx:BaseModelicaParser.VersionHeaderContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#classDefinition.
    def enterClassDefinition(self, ctx:BaseModelicaParser.ClassDefinitionContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#classDefinition.
    def exitClassDefinition(self, ctx:BaseModelicaParser.ClassDefinitionContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#classPrefixes.
    def enterClassPrefixes(self, ctx:BaseModelicaParser.ClassPrefixesContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#classPrefixes.
    def exitClassPrefixes(self, ctx:BaseModelicaParser.ClassPrefixesContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#classSpecifier.
    def enterClassSpecifier(self, ctx:BaseModelicaParser.ClassSpecifierContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#classSpecifier.
    def exitClassSpecifier(self, ctx:BaseModelicaParser.ClassSpecifierContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#longClassSpecifier.
    def enterLongClassSpecifier(self, ctx:BaseModelicaParser.LongClassSpecifierContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#longClassSpecifier.
    def exitLongClassSpecifier(self, ctx:BaseModelicaParser.LongClassSpecifierContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#shortClassSpecifier.
    def enterShortClassSpecifier(self, ctx:BaseModelicaParser.ShortClassSpecifierContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#shortClassSpecifier.
    def exitShortClassSpecifier(self, ctx:BaseModelicaParser.ShortClassSpecifierContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#derClassSpecifier.
    def enterDerClassSpecifier(self, ctx:BaseModelicaParser.DerClassSpecifierContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#derClassSpecifier.
    def exitDerClassSpecifier(self, ctx:BaseModelicaParser.DerClassSpecifierContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#basePrefix.
    def enterBasePrefix(self, ctx:BaseModelicaParser.BasePrefixContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#basePrefix.
    def exitBasePrefix(self, ctx:BaseModelicaParser.BasePrefixContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#enumList.
    def enterEnumList(self, ctx:BaseModelicaParser.EnumListContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#enumList.
    def exitEnumList(self, ctx:BaseModelicaParser.EnumListContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#enumerationLiteral.
    def enterEnumerationLiteral(self, ctx:BaseModelicaParser.EnumerationLiteralContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#enumerationLiteral.
    def exitEnumerationLiteral(self, ctx:BaseModelicaParser.EnumerationLiteralContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#composition.
    def enterComposition(self, ctx:BaseModelicaParser.CompositionContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#composition.
    def exitComposition(self, ctx:BaseModelicaParser.CompositionContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#languageSpecification.
    def enterLanguageSpecification(self, ctx:BaseModelicaParser.LanguageSpecificationContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#languageSpecification.
    def exitLanguageSpecification(self, ctx:BaseModelicaParser.LanguageSpecificationContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#externalFunctionCall.
    def enterExternalFunctionCall(self, ctx:BaseModelicaParser.ExternalFunctionCallContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#externalFunctionCall.
    def exitExternalFunctionCall(self, ctx:BaseModelicaParser.ExternalFunctionCallContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#genericElement.
    def enterGenericElement(self, ctx:BaseModelicaParser.GenericElementContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#genericElement.
    def exitGenericElement(self, ctx:BaseModelicaParser.GenericElementContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#normalElement.
    def enterNormalElement(self, ctx:BaseModelicaParser.NormalElementContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#normalElement.
    def exitNormalElement(self, ctx:BaseModelicaParser.NormalElementContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#parameterEquation.
    def enterParameterEquation(self, ctx:BaseModelicaParser.ParameterEquationContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#parameterEquation.
    def exitParameterEquation(self, ctx:BaseModelicaParser.ParameterEquationContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#guessValue.
    def enterGuessValue(self, ctx:BaseModelicaParser.GuessValueContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#guessValue.
    def exitGuessValue(self, ctx:BaseModelicaParser.GuessValueContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#basePartition.
    def enterBasePartition(self, ctx:BaseModelicaParser.BasePartitionContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#basePartition.
    def exitBasePartition(self, ctx:BaseModelicaParser.BasePartitionContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#subPartition.
    def enterSubPartition(self, ctx:BaseModelicaParser.SubPartitionContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#subPartition.
    def exitSubPartition(self, ctx:BaseModelicaParser.SubPartitionContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#clockClause.
    def enterClockClause(self, ctx:BaseModelicaParser.ClockClauseContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#clockClause.
    def exitClockClause(self, ctx:BaseModelicaParser.ClockClauseContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#componentClause.
    def enterComponentClause(self, ctx:BaseModelicaParser.ComponentClauseContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#componentClause.
    def exitComponentClause(self, ctx:BaseModelicaParser.ComponentClauseContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#globalConstant.
    def enterGlobalConstant(self, ctx:BaseModelicaParser.GlobalConstantContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#globalConstant.
    def exitGlobalConstant(self, ctx:BaseModelicaParser.GlobalConstantContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#typePrefix.
    def enterTypePrefix(self, ctx:BaseModelicaParser.TypePrefixContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#typePrefix.
    def exitTypePrefix(self, ctx:BaseModelicaParser.TypePrefixContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#componentList.
    def enterComponentList(self, ctx:BaseModelicaParser.ComponentListContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#componentList.
    def exitComponentList(self, ctx:BaseModelicaParser.ComponentListContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#componentDeclaration.
    def enterComponentDeclaration(self, ctx:BaseModelicaParser.ComponentDeclarationContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#componentDeclaration.
    def exitComponentDeclaration(self, ctx:BaseModelicaParser.ComponentDeclarationContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#declaration.
    def enterDeclaration(self, ctx:BaseModelicaParser.DeclarationContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#declaration.
    def exitDeclaration(self, ctx:BaseModelicaParser.DeclarationContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#modification.
    def enterModification(self, ctx:BaseModelicaParser.ModificationContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#modification.
    def exitModification(self, ctx:BaseModelicaParser.ModificationContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#classModification.
    def enterClassModification(self, ctx:BaseModelicaParser.ClassModificationContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#classModification.
    def exitClassModification(self, ctx:BaseModelicaParser.ClassModificationContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#argumentList.
    def enterArgumentList(self, ctx:BaseModelicaParser.ArgumentListContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#argumentList.
    def exitArgumentList(self, ctx:BaseModelicaParser.ArgumentListContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#argument.
    def enterArgument(self, ctx:BaseModelicaParser.ArgumentContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#argument.
    def exitArgument(self, ctx:BaseModelicaParser.ArgumentContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#elementModificationOrReplaceable.
    def enterElementModificationOrReplaceable(self, ctx:BaseModelicaParser.ElementModificationOrReplaceableContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#elementModificationOrReplaceable.
    def exitElementModificationOrReplaceable(self, ctx:BaseModelicaParser.ElementModificationOrReplaceableContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#elementModification.
    def enterElementModification(self, ctx:BaseModelicaParser.ElementModificationContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#elementModification.
    def exitElementModification(self, ctx:BaseModelicaParser.ElementModificationContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#equation.
    def enterEquation(self, ctx:BaseModelicaParser.EquationContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#equation.
    def exitEquation(self, ctx:BaseModelicaParser.EquationContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#initialEquation.
    def enterInitialEquation(self, ctx:BaseModelicaParser.InitialEquationContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#initialEquation.
    def exitInitialEquation(self, ctx:BaseModelicaParser.InitialEquationContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#statement.
    def enterStatement(self, ctx:BaseModelicaParser.StatementContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#statement.
    def exitStatement(self, ctx:BaseModelicaParser.StatementContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#ifEquation.
    def enterIfEquation(self, ctx:BaseModelicaParser.IfEquationContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#ifEquation.
    def exitIfEquation(self, ctx:BaseModelicaParser.IfEquationContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#ifStatement.
    def enterIfStatement(self, ctx:BaseModelicaParser.IfStatementContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#ifStatement.
    def exitIfStatement(self, ctx:BaseModelicaParser.IfStatementContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#forEquation.
    def enterForEquation(self, ctx:BaseModelicaParser.ForEquationContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#forEquation.
    def exitForEquation(self, ctx:BaseModelicaParser.ForEquationContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#forStatement.
    def enterForStatement(self, ctx:BaseModelicaParser.ForStatementContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#forStatement.
    def exitForStatement(self, ctx:BaseModelicaParser.ForStatementContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#forIndex.
    def enterForIndex(self, ctx:BaseModelicaParser.ForIndexContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#forIndex.
    def exitForIndex(self, ctx:BaseModelicaParser.ForIndexContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#whileStatement.
    def enterWhileStatement(self, ctx:BaseModelicaParser.WhileStatementContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#whileStatement.
    def exitWhileStatement(self, ctx:BaseModelicaParser.WhileStatementContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#whenEquation.
    def enterWhenEquation(self, ctx:BaseModelicaParser.WhenEquationContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#whenEquation.
    def exitWhenEquation(self, ctx:BaseModelicaParser.WhenEquationContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#whenStatement.
    def enterWhenStatement(self, ctx:BaseModelicaParser.WhenStatementContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#whenStatement.
    def exitWhenStatement(self, ctx:BaseModelicaParser.WhenStatementContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#prioritizeEquation.
    def enterPrioritizeEquation(self, ctx:BaseModelicaParser.PrioritizeEquationContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#prioritizeEquation.
    def exitPrioritizeEquation(self, ctx:BaseModelicaParser.PrioritizeEquationContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#prioritizeExpression.
    def enterPrioritizeExpression(self, ctx:BaseModelicaParser.PrioritizeExpressionContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#prioritizeExpression.
    def exitPrioritizeExpression(self, ctx:BaseModelicaParser.PrioritizeExpressionContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#priority.
    def enterPriority(self, ctx:BaseModelicaParser.PriorityContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#priority.
    def exitPriority(self, ctx:BaseModelicaParser.PriorityContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#decoration.
    def enterDecoration(self, ctx:BaseModelicaParser.DecorationContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#decoration.
    def exitDecoration(self, ctx:BaseModelicaParser.DecorationContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#expression.
    def enterExpression(self, ctx:BaseModelicaParser.ExpressionContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#expression.
    def exitExpression(self, ctx:BaseModelicaParser.ExpressionContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#expressionNoDecoration.
    def enterExpressionNoDecoration(self, ctx:BaseModelicaParser.ExpressionNoDecorationContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#expressionNoDecoration.
    def exitExpressionNoDecoration(self, ctx:BaseModelicaParser.ExpressionNoDecorationContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#ifExpression.
    def enterIfExpression(self, ctx:BaseModelicaParser.IfExpressionContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#ifExpression.
    def exitIfExpression(self, ctx:BaseModelicaParser.IfExpressionContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#simpleExpression.
    def enterSimpleExpression(self, ctx:BaseModelicaParser.SimpleExpressionContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#simpleExpression.
    def exitSimpleExpression(self, ctx:BaseModelicaParser.SimpleExpressionContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#logicalExpression.
    def enterLogicalExpression(self, ctx:BaseModelicaParser.LogicalExpressionContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#logicalExpression.
    def exitLogicalExpression(self, ctx:BaseModelicaParser.LogicalExpressionContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#logicalTerm.
    def enterLogicalTerm(self, ctx:BaseModelicaParser.LogicalTermContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#logicalTerm.
    def exitLogicalTerm(self, ctx:BaseModelicaParser.LogicalTermContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#logicalFactor.
    def enterLogicalFactor(self, ctx:BaseModelicaParser.LogicalFactorContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#logicalFactor.
    def exitLogicalFactor(self, ctx:BaseModelicaParser.LogicalFactorContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#relation.
    def enterRelation(self, ctx:BaseModelicaParser.RelationContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#relation.
    def exitRelation(self, ctx:BaseModelicaParser.RelationContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#relationalOperator.
    def enterRelationalOperator(self, ctx:BaseModelicaParser.RelationalOperatorContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#relationalOperator.
    def exitRelationalOperator(self, ctx:BaseModelicaParser.RelationalOperatorContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#arithmeticExpression.
    def enterArithmeticExpression(self, ctx:BaseModelicaParser.ArithmeticExpressionContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#arithmeticExpression.
    def exitArithmeticExpression(self, ctx:BaseModelicaParser.ArithmeticExpressionContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#addOperator.
    def enterAddOperator(self, ctx:BaseModelicaParser.AddOperatorContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#addOperator.
    def exitAddOperator(self, ctx:BaseModelicaParser.AddOperatorContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#term.
    def enterTerm(self, ctx:BaseModelicaParser.TermContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#term.
    def exitTerm(self, ctx:BaseModelicaParser.TermContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#mulOperator.
    def enterMulOperator(self, ctx:BaseModelicaParser.MulOperatorContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#mulOperator.
    def exitMulOperator(self, ctx:BaseModelicaParser.MulOperatorContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#factor.
    def enterFactor(self, ctx:BaseModelicaParser.FactorContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#factor.
    def exitFactor(self, ctx:BaseModelicaParser.FactorContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#primary.
    def enterPrimary(self, ctx:BaseModelicaParser.PrimaryContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#primary.
    def exitPrimary(self, ctx:BaseModelicaParser.PrimaryContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#typeSpecifier.
    def enterTypeSpecifier(self, ctx:BaseModelicaParser.TypeSpecifierContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#typeSpecifier.
    def exitTypeSpecifier(self, ctx:BaseModelicaParser.TypeSpecifierContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#name.
    def enterName(self, ctx:BaseModelicaParser.NameContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#name.
    def exitName(self, ctx:BaseModelicaParser.NameContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#componentReference.
    def enterComponentReference(self, ctx:BaseModelicaParser.ComponentReferenceContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#componentReference.
    def exitComponentReference(self, ctx:BaseModelicaParser.ComponentReferenceContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#functionCallArgs.
    def enterFunctionCallArgs(self, ctx:BaseModelicaParser.FunctionCallArgsContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#functionCallArgs.
    def exitFunctionCallArgs(self, ctx:BaseModelicaParser.FunctionCallArgsContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#functionArguments.
    def enterFunctionArguments(self, ctx:BaseModelicaParser.FunctionArgumentsContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#functionArguments.
    def exitFunctionArguments(self, ctx:BaseModelicaParser.FunctionArgumentsContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#functionArgumentsNonFirst.
    def enterFunctionArgumentsNonFirst(self, ctx:BaseModelicaParser.FunctionArgumentsNonFirstContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#functionArgumentsNonFirst.
    def exitFunctionArgumentsNonFirst(self, ctx:BaseModelicaParser.FunctionArgumentsNonFirstContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#arrayArguments.
    def enterArrayArguments(self, ctx:BaseModelicaParser.ArrayArgumentsContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#arrayArguments.
    def exitArrayArguments(self, ctx:BaseModelicaParser.ArrayArgumentsContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#namedArguments.
    def enterNamedArguments(self, ctx:BaseModelicaParser.NamedArgumentsContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#namedArguments.
    def exitNamedArguments(self, ctx:BaseModelicaParser.NamedArgumentsContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#namedArgument.
    def enterNamedArgument(self, ctx:BaseModelicaParser.NamedArgumentContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#namedArgument.
    def exitNamedArgument(self, ctx:BaseModelicaParser.NamedArgumentContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#functionArgument.
    def enterFunctionArgument(self, ctx:BaseModelicaParser.FunctionArgumentContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#functionArgument.
    def exitFunctionArgument(self, ctx:BaseModelicaParser.FunctionArgumentContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#functionPartialApplication.
    def enterFunctionPartialApplication(self, ctx:BaseModelicaParser.FunctionPartialApplicationContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#functionPartialApplication.
    def exitFunctionPartialApplication(self, ctx:BaseModelicaParser.FunctionPartialApplicationContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#outputExpressionList.
    def enterOutputExpressionList(self, ctx:BaseModelicaParser.OutputExpressionListContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#outputExpressionList.
    def exitOutputExpressionList(self, ctx:BaseModelicaParser.OutputExpressionListContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#expressionList.
    def enterExpressionList(self, ctx:BaseModelicaParser.ExpressionListContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#expressionList.
    def exitExpressionList(self, ctx:BaseModelicaParser.ExpressionListContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#arraySubscripts.
    def enterArraySubscripts(self, ctx:BaseModelicaParser.ArraySubscriptsContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#arraySubscripts.
    def exitArraySubscripts(self, ctx:BaseModelicaParser.ArraySubscriptsContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#subscript.
    def enterSubscript(self, ctx:BaseModelicaParser.SubscriptContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#subscript.
    def exitSubscript(self, ctx:BaseModelicaParser.SubscriptContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#comment.
    def enterComment(self, ctx:BaseModelicaParser.CommentContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#comment.
    def exitComment(self, ctx:BaseModelicaParser.CommentContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#stringComment.
    def enterStringComment(self, ctx:BaseModelicaParser.StringCommentContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#stringComment.
    def exitStringComment(self, ctx:BaseModelicaParser.StringCommentContext):
        pass


    # Enter a parse tree produced by BaseModelicaParser#annotationComment.
    def enterAnnotationComment(self, ctx:BaseModelicaParser.AnnotationCommentContext):
        pass

    # Exit a parse tree produced by BaseModelicaParser#annotationComment.
    def exitAnnotationComment(self, ctx:BaseModelicaParser.AnnotationCommentContext):
        pass



del BaseModelicaParser