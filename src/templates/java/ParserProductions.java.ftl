#-- This template contains the core logic for generating the various parser routines. --

#var nodeNumbering = 0,
     exceptionNesting = 0,
     NODE_USES_PARSER = settings.nodeUsesParser,
     NODE_PREFIX = grammar.nodePrefix,
     currentProduction,
     topLevelExpansion [#-- A "one-shot" indication that we are processing
                              an expansion immediately below the BNF production expansion,
                              ignoring an ExpansionSequence that might be there. This is
                              primarily, if not exclusively, for allowing JTB-compatible
                              syntactic trees to be built. While seemingly silly (and perhaps could be done differently),
                              it is also a bit tricky, so treat it like the Holy Hand-grenade in that respect.
                          --]

#var jtbNameMap = {
   "Terminal" : "nodeToken",
   "Sequence" : "nodeSequence",
   "Choice" : "nodeChoice",
   "ZeroOrOne" : "nodeOptional",
   "ZeroOrMore" : "nodeListOptional",
   "OneOrMore" : "nodeList" },
   nodeFieldOrdinal = {}

#var injectedFields = {},
     syntheticNodesEnabled = settings.syntheticNodesEnabled && settings.treeBuildingEnabled,
     jtbParseTree = syntheticNodesEnabled && settings.jtbParseTree

#macro Productions
 //====================================================================//
 // Start of methods for BNF Productions                               //
 // This code is generated by the ParserProductions.java.ftl template. //
 //====================================================================//
   #list grammar.parserProductions as production
      #set nodeNumbering = 0
      [@CU.firstSetVar production.expansion/]
      #if !production.onlyForLookahead
         #set currentProduction = production
         [@ParserProduction production/]
      /#if
   /#list
   #if settings.faultTolerant
      [@BuildRecoverRoutines/]
   /#if
/#macro

#macro ParserProduction production
    #set nodeNumbering = 0,
         nodeFieldOrdinal = {},
         injectedFields = {}
    #set newVarIndex = 0 in CU
    #-- Generate the method modifiers and header --
    ${production.leadingComments}
// ${production.location}
    final ${production.accessModifier}
    ${production.returnType}
    ${production.name}(${production.parameterList!})
   #if settings.useCheckedException
    throws ParseException
    [#list (production.throwsList.types)! as throw], ${throw}[/#list]
   #elseif (production.throwsList.types)??
     #list production.throwsList.types as throw
        #if throw_index == 0
           throws ${throw}
        #else
           , ${throw}
        /#if
     /#list
   /#if
   #-- Now generate the body --
    {
     if (cancelled) throw new CancellationException();
     this.currentlyParsedProduction = "${production.name}";
     [#--${production.javaCode!}
       This is actually inserted further down because
       we want the prologue java code block to be able to refer to
       CURRENT_NODE.
     --]
     #set topLevelExpansion = false
     [@BuildCode production /]
    }
/#macro

[#--
   Macro to build routines that scan up to the start of an expansion
   as part of a recovery routine
--]
#macro BuildRecoverRoutines
   #list grammar.expansionsNeedingRecoverMethod as expansion
       private void ${expansion.recoverMethodName}() {
          ${settings.baseTokenClassName} initialToken = lastConsumedToken;
          java.util.List<${settings.baseTokenClassName}> skippedTokens = new java.util.ArrayList<>();
          boolean success = false;
          while (lastConsumedToken.getType() != EOF) {
            #if expansion.simpleName = "OneOrMore" || expansion.simpleName = "ZeroOrMore"
             if (${ExpansionCondition(expansion.nestedExpansion)}) {
            #else
             if (${ExpansionCondition(expansion)}) {
            /#if
                success = true;
                break;
             }
             #if expansion.simpleName = "ZeroOrMore" || expansion.simpleName = "OneOrMore"
               #var followingExpansion = expansion.followingExpansion
               #list 1..1000000 as unused
                [#if followingExpansion?is_null][#break][/#if]
                #if followingExpansion.maximumSize >0
                 #if followingExpansion.simpleName = "OneOrMore" || followingExpansion.simpleName = "ZeroOrOne" || followingExpansion.simpleName = "ZeroOrMore"
                 if (${ExpansionCondition(followingExpansion.nestedExpansion)}) {
                 #else
                 if (${ExpansionCondition(followingExpansion)}) {
                 /#if
                    success = true;
                    break;
                 }
                /#if
                [#if !followingExpansion.possiblyEmpty][#break][/#if]
                #if followingExpansion.followingExpansion?is_null
                 if (outerFollowSet != null) {
                   if (outerFollowSet.contains(nextTokenType())) {
                      success = true;
                      break;
                   }
                 }
                 [#break/]
                /#if
                #set followingExpansion = followingExpansion.followingExpansion
               /#list
             /#if
             lastConsumedToken = nextToken(lastConsumedToken);
             skippedTokens.add(lastConsumedToken);
          }
          if (!success && !skippedTokens.isEmpty()) {
             lastConsumedToken = initialToken;
          }
          if (success&& !skippedTokens.isEmpty()) {
             InvalidNode iv = new InvalidNode();
             iv.copyLocationInfo(skippedTokens.get(0));
             for (${settings.baseTokenClassName} tok : skippedTokens) {
                iv.add(tok);
                iv.setEndOffset(tok.getEndOffset());
             }
             pushNode(iv);
          }
          pendingRecovery = !success;
       }
   /#list
/#macro

#macro BuildCode expansion
  #if expansion.simpleName != "ExpansionSequence" && expansion.simpleName != "ExpansionWithParentheses"
  // Code for ${expansion.simpleName} specified at ${expansion.location}
  /#if
     [@CU.HandleLexicalStateChange expansion false]
         #if settings.faultTolerant && expansion.requiresRecoverMethod && !expansion.possiblyEmpty
         if (pendingRecovery) {
            ${expansion.recoverMethodName}();
         }
         /#if
         [@BuildExpansionCode expansion/]
     [/@CU.HandleLexicalStateChange]
/#macro

#-- The following macro wraps expansions that might build tree nodes. --
#macro TreeBuildingAndRecovery expansion
   #var production,
         treeNodeBehavior,
         buildingTreeNode=false,
         nodeVarName,
         javaCodePrologue = "",
         parseExceptionVar = CU.newVarName("parseException"),
         callStackSizeVar = CU.newVarName("callStackSize"),
         canRecover = settings.faultTolerant && expansion.tolerantParsing && expansion.simpleName != "Terminal"
   #set treeNodeBehavior = resolveTreeNodeBehavior(expansion)
   #-- // DBG <> treeNodeBehavior = ${(treeNodeBehavior??)?string!} for expansion ${expansion.simpleName} --
   #if expansion == currentProduction
      #-- Set this expansion as the current production and capture any Java code specified before the first expansion unit --
      #set production = currentProduction,
           javaCodePrologue = production.javaCode!
   /#if
   #if treeNodeBehavior??
      #if settings.treeBuildingEnabled
         #set buildingTreeNode = true,
              nodeVarName = nodeVar(production??)
      /#if
   /#if
   #if !buildingTreeNode && !canRecover
      #-- We need neither tree nodes nor recovery code; do the simple one. --
      ${javaCodePrologue}
      #nested
   #else
      #-- We need tree nodes and/or recovery code. --
      #if buildingTreeNode
         #-- Build the tree node (part 1). --
         [@buildTreeNode production treeNodeBehavior nodeVarName /]
      /#if
      #-- Any prologue code can refer to CURRENT_NODE at this point. --
      #-- REVISIT: Is this needed anymore, since THIS_PRODUCTION is always the reference to the current production node (if any) (jb)? --
      ${javaCodePrologue}
      ParseException ${parseExceptionVar} = null;
      int ${callStackSizeVar} = parsingStack.size();
      try {
      #if settings.useCheckedException
         if (false) throw new ParseException("Never happens!");
      /#if
         #-- Here is the "nut". --
         #nested
      }
      catch (ParseException ${exceptionVar()}) {
         ${parseExceptionVar} = ${exceptionVar()};
      #if !canRecover
         #if settings.faultTolerant
         if (isParserTolerant()) this.pendingRecovery = true;
         /#if
         throw e;
      #else
         if (!isParserTolerant()) throw e;
         this.pendingRecovery = true;
         ${expansion.customErrorRecoveryBlock!}
         #if production?? && production.returnType != "void"
            #var rt = production.returnType
            #-- We need a return statement here or the code won't compile! --
            #if rt = "int" || rt="char" || rt=="byte" || rt="short" || rt="long" || rt="float"|| rt="double"
         return 0;
            #else
         return null;
            /#if
         /#if
      /#if
      }
      finally {
         restoreCallStack(${callStackSizeVar});
      #if buildingTreeNode
         #-- Build the tree node (part 2). --
         [@buildTreeNodeEpilogue treeNodeBehavior nodeVarName parseExceptionVar /]
      /#if
      }
   /#if
/#macro

#function imputedJtbFieldName nodeClass
   #if nodeClass?? && jtbParseTree && topLevelExpansion
      #-- Determine the name of the node field containing the reference to a synthetic syntax node --
      #var fieldName = nodeClass?uncap_first,
           fieldOrdinal
      #if jtbNameMap[nodeClass]??
         #-- Allow for JTB-style syntactic node names (but exclude Token and <non-terminal> ). --
         #set fieldName = jtbNameMap[nodeClass]
      /#if
      #set fieldOrdinal = nodeFieldOrdinal[nodeClass]!null
      #if !fieldOrdinal??
         #set nodeFieldOrdinal = nodeFieldOrdinal + {nodeClass : 1}
      #else
         #set nodeFieldOrdinal = nodeFieldOrdinal + {nodeClass : fieldOrdinal + 1}
      /#if
      #var nodeFieldName = fieldName + fieldOrdinal!""
      #-- INJECT <production-node> : { public <field-type> <unique-field-name> } --
      ${injectDeclaration(nodeClass, nodeFieldName)}
      #return nodeFieldName
   /#if
   #-- Indicate that no field name is required (either not JTB or not a top-level production node) --
   #return null
/#function

#function resolveTreeNodeBehavior expansion
   #var treeNodeBehavior = expansion.treeNodeBehavior,
        isProduction = false
   #if expansion.simpleName = "BNFProduction"
      #set isProduction = true
   #else
      #var nodeName = syntacticNodeName(expansion) [#-- This maps ExpansionSequence containing more than one syntax element to "Sequence", otherwise to the element itself --]
      #if !treeNodeBehavior?? && expansion.assignment??
         #if syntheticNodesEnabled && isProductionInstantiatingNode(expansion)
            #-- Assignment is explicitly provided and synthetic nodes are enabled --
            [#-- NOTE: An explicit assignment will take precedence over a synthetic JTB node.
               I.e., it will not create a field in the production node.  It WILL, however,
               use the syntactic node type for the natural assignment value, as seen below.
            --]
            #-- This expansion has an explicit assignment; check if we need to synthesize a definite node --
            #if nodeName?? && (
               nodeName == "ZeroOrOne" ||
               nodeName == "ZeroOrMore" ||
               nodeName == "OneOrMore" ||
               nodeName == "Choice" ||
               nodeName == "Sequence"
               )
               #-- We do need to create a definite node --
               #if !jtbParseTree
                  [#-- It's not a JTB tree but it is a syntactic node with a LHS assignment, so use the BASE_NODE type --][#-- (jb) is there a reason to use the syntactic type always?  Perhaps, but I can't think of one. --]
                  #set nodeName = settings.baseNodeClassName
               /#if
               #-- Make a new node to wrap the current expansion with the expansion's assignment. --
               #set treeNodeBehavior = {
                                          'nodeName' : nodeName,
                                          'condition' : null,
                                          'gtNode' : false,
                                          'void' : false,
                                          'assignment' : expansion.assignment
                                       }
               #if expansion.assignment.propertyAssignment && expansion.assignment.declarationOf
                  #-- Inject the receiving property --
                  ${injectDeclaration(nodeName, expansion.assignment.name, expansion.assignment)}
               /#if
            /#if
         #elseif nodeName??
            #-- We are attempting to do assignment of a syntactic node value, but synthetic nodes are not enabled --
            #exec grammar.errors::addWarning(currentProduction, "Attempt to assign " + nodeName + " in production node " + currentProduction.name + " but either synthetic nodes are not enabled or the production is not instantiated; the assignment will be ignored.")
            #return null
         /#if
      #elseif treeNodeBehavior?? &&
               treeNodeBehavior.assignment??
         #-- There is an explicit tree node annotation with assignment; make sure a property is injected if needed. --
         #if treeNodeBehavior.assignment.declarationOf
            ${injectDeclaration(treeNodeBehavior.nodeName, treeNodeBehavior.assignment.name, treeNodeBehavior.assignment)}
         /#if
      #elseif jtbParseTree &&
              expansion.parent.simpleName != "ExpansionWithParentheses" &&
              isProductionInstantiatingNode(currentProduction)
         #-- No in-line definite node annotation; synthesize a parser node for the expansion type being built, if needed. --
         #if nodeName??
            #-- Determine the node name depending on syntactic type --
            #var nodeFieldName = imputedJtbFieldName(nodeName) [#-- Among other things this injects the node field into the generated node if result is non-nullv--]
            #-- Default to always produce a node even if no child nodes --
            #var gtNode = false
            #var condition = null
            #var initialShorthand = null
            #if nodeName == "Choice"
               #-- Generate a Choice node only if at least one child node --
               #set gtNode = true
               #set condition = "0"
               #set initialShorthand = " > "
            /#if
            #if nodeFieldName??
               [#-- Provide an assignment to save the syntactic node in a
               synthetic field injected into the actual production node per JTB behavior. --]
               #set treeNodeBehavior = {
                                          'nodeName' : nodeName!"nemo",
                                          'condition' : condition,
                                          'gtNode' : gtNode,
                                          'initialShorthand' : initialShorthand,
                                          'void' : false,
                                          'assignment' :
                                             { 'name' : globals::translateIdentifier("THIS_PRODUCTION") + "." + nodeFieldName,
                                               'propertyAssignment' : false,
                                               'declarationOf' : true,
                                               'existenceOf' : false }
                                       }
            #else
               #-- Just provide the syntactic node with no LHS needed --
               #set treeNodeBehavior = {
                                          'nodeName' : nodeName!"nemo",
                                          'condition' : condition,
                                          'gtNode' : gtNode,
                                          'initialShorthand' : initialShorthand,
                                          'void' : false,
                                          'assignment' : null
                                       }
            /#if
         /#if
      /#if
   /#if
   #if !treeNodeBehavior??
      #-- There is still no treeNodeBehavior determined; supply the default if this is a BNF production node. No assignment is needed. --
      #if isProduction && !settings.nodeDefaultVoid
                        && !grammar::nodeIsInterface(expansion.name)
                        && !grammar::nodeIsAbstract(expansion.name)
         #if settings.smartNodeCreation
            #set treeNodeBehavior = {
                                       "nodeName" : expansion.name!"nemo",
                                       "condition" : "1",
                                       "gtNode" : true,
                                       "void" :false,
                                       "initialShorthand" : ">",
                                       'assignment' : null
                                     }
         #else
            #set treeNodeBehavior = {
                                       "nodeName" : expansion.name!"nemo",
                                       "condition" : null,
                                       "gtNode" : false,
                                       "void" : false,
                                       'assignment' : null
                                    }
         /#if
      /#if
   /#if
   #if treeNodeBehavior?? && treeNodeBehavior.neverInstantiated?? && treeNodeBehavior.neverInstantiated
      #-- Now, if the treeNodeBehavior says it will never be instantiated, throw it all away --
      #return null
   /#if
   #-- This is the actual treeNodeBehavior for this node --
   #return treeNodeBehavior
/#function

#-- This is primarily to distinguish sequences of syntactic elements from effectively single elements --
#function syntacticNodeName expansion
      #var classname = expansion.simpleName
      #if classname = "ZeroOrOne"
         #return classname
      #elseif classname = "ZeroOrMore"
         #return classname
      #elseif classname = "OneOrMore"
         #return classname
      #elseif jtbParseTree && classname = "Terminal"
         #return classname
      #elseif classname = "ExpansionChoice"
         #return "Choice"
      #elseif classname = "ExpansionWithParentheses" || classname = "BNFProduction"
         #-- the () will be skipped and the nested expansion processed, so built the tree node for it rather than this --
         #var innerExpansion = expansion.nestedExpansion
         #return syntacticNodeName(innerExpansion)
      #elseif classname = "ExpansionSequence" &&
               expansion.parent?? &&
               (
                  expansion.parent.simpleName == "ExpansionWithParentheses" ||
                  (
                     expansion.parent.simpleName == "ZeroOrOne" ||
                     expansion.parent.simpleName == "OneOrMore" ||
                     expansion.parent.simpleName == "ZeroOrMore" ||
                     expansion.parent.simpleName == "ExpansionChoice"
                  ) && expansion.essentialSequence
               )
         #return "Sequence"
      /#if
      #return null
/#function

#function isProductionInstantiatingNode expansion
   #return !expansion.containingProduction.treeNodeBehavior?? ||
           !expansion.containingProduction.treeNodeBehavior.neverInstantiated!true
/#function

#function nodeVar isProduction
   #var nodeVarName
   #if isProduction
      #set nodeVarName = globals::translateIdentifier("THIS_PRODUCTION")
   #else
      #set nodeNumbering = nodeNumbering +1
      #set nodeVarName = currentProduction.name + nodeNumbering
   /#if
   #return nodeVarName
/#function

#function exceptionVar(isNesting)
   #var exceptionVarName = "e"
   #if exceptionNesting > 0
      #set exceptionVarName = "e" + exceptionNesting
   /#if
   #if isNesting!false
      #set exceptionNesting = exceptionNesting+1
   /#if
   #return exceptionVarName
/#function

#macro buildTreeNode production treeNodeBehavior nodeVarName [#-- FIXME: production is not used here --]
   #exec globals::pushNodeVariableName(nodeVarName)
   [@createNode nodeClassName(treeNodeBehavior) nodeVarName /]
/#macro

#--  Boilerplate code to create the node variable --
#macro createNode nodeClass nodeVarName
#-- // DBG > createNode --
   ${nodeClass}
   ${nodeVarName} = null;
   if (buildTree) {
      ${nodeVarName} = new ${nodeClass}();
   #if settings.nodeUsesParser
      ${nodeVarName}.setParser(this);
   /#if
        openNodeScope(${nodeVarName});
   }
#-- // DBG < createNode --
/#macro

#macro buildTreeNodeEpilogue treeNodeBehavior nodeVarName parseExceptionVar
   if (${nodeVarName}!=null) {
      if (${parseExceptionVar} == null) {
   #if treeNodeBehavior?? && treeNodeBehavior.assignment??
      #var LHS = getLhsPattern(treeNodeBehavior.assignment, null)
         if (closeNodeScope(${nodeVarName}, ${closeCondition(treeNodeBehavior)})) {
            ${LHS?replace("@", "(" + nodeClassName(treeNodeBehavior) + ") peekNode()")};
         } else{
            ${LHS?replace("@", "null")};
         }
   #else
         closeNodeScope(${nodeVarName}, ${closeCondition(treeNodeBehavior)});
   /#if
   #list grammar.closeNodeHooksByClass[nodeClassName(treeNodeBehavior)]! as hook
         ${hook}(${nodeVarName});
   /#list
      } else {
   #if settings.faultTolerant
         closeNodeScope(${nodeVarName}, true);
         ${nodeVarName}.setDirty(true);
   #else
         clearNodeScope();
   /#if
      }
   }
   #exec globals::popNodeVariableName()
/#macro

#function getRhsAssignmentPattern assignment
   #if assignment.existenceOf!false
      #-- replace "@" with "(((@) != null) ? true : false)" --
      #return "(((@) != null) ? true : false)"
   #elseif assignment.stringOf!false
      [#-- replace "@" with the string value of the node --]
      #return "Objects.toString((@), \"\").trim()"
   /#if
   #return "@"
/#function

#function getLhsPattern assignment, lhsType
   #if assignment??
      #var lhsName = assignment.name
      #if assignment.propertyAssignment
         #-- This is the assignment of the current node's effective value to a property of the production node --
         #set lhsName = lhsName?cap_first
         #if lhsType?? && assignment.declarationOf
            #-- This is a declaration assignment; inject required property --
            ${injectDeclaration(lhsType, assignment.name, assignment)}
         /#if
         #if assignment.addTo!false
            #-- This is the addition of the current node as a child of the specified property's node value --
            #return globals::translateIdentifier("THIS_PRODUCTION") + ".get" + lhsName + "().add(" + getRhsAssignmentPattern(assignment) + ")"
         #else
            #-- This is an assignment of the current node's effective value to the specified property of the production node --
            #return globals::translateIdentifier("THIS_PRODUCTION") + ".set" + lhsName + "(" + getRhsAssignmentPattern(assignment) + ")"
         /#if
      #elseif assignment.namedAssignment!false
         #if assignment.addTo
            #-- This is the addition of the current node to the named child list of the production node --
            #return "${globals.currentNodeVariableName}" + ".addToNamedChildList(\"" + lhsName + "\", " + getRhsAssignmentPattern(assignment) + ")"
         #else
            #-- This is an assignment of the current node to a named child of the production node --
            #return "${globals.currentNodeVariableName}" + ".setNamedChild(\"" + lhsName + "\", " + getRhsAssignmentPattern(assignment) + ")"
         /#if
      /#if
      #-- This is the assignment of the current node or it's returned value to an arbitrary LHS "name" (i.e., the legacy JavaCC assignment) --
      #return lhsName + " = " + getRhsAssignmentPattern(assignment)
   /#if
   #-- There is no LHS --
   #return "@"
/#function

#function injectDeclaration typeName, fieldName, assignment
   #if !isProductionInstantiatingNode(currentProduction)
      #exec grammar.errors::addWarning(currentProduction, "Attempt to inject property or field declaration " + fieldName + " into an un-instantiated production node " + currentProduction.name + "; the assignment will be ignored.")
      #return ""
   /#if
   #var modifier = "public",
        type = typeName,
        field = fieldName
   #if assignment?? && assignment.propertyAssignment
      #set modifier = "@Property"
   /#if
   #if assignment?? && assignment.existenceOf
      #set type = "boolean"
   #elseif assignment?? && assignment.stringOf
      #set type = "String"
   #elseif assignment?? && assignment.addTo
      #set type = "List<Node>"
      #set field = field + " = new ArrayList<Node>()"
   /#if
   #if !(injectedFields[field])??
      #set injectedFields = injectedFields + {field : type}
      #exec grammar::addFieldInjection(currentProduction.nodeName, modifier, type, field)
   /#if
   #return ""
/#function

#function closeCondition treeNodeBehavior
   #var cc = "true"
   #if (treeNodeBehavior.condition)??
         #set cc = treeNodeBehavior.condition
         #if treeNodeBehavior.gtNode
            #set cc = "nodeArity() " + treeNodeBehavior.initialShorthand  + cc
         /#if
   /#if
   #return cc
/#function

#function nodeClassName treeNodeBehavior
   #if treeNodeBehavior?? && treeNodeBehavior.nodeName??
      #return NODE_PREFIX + treeNodeBehavior.nodeName
   /#if
   #return NODE_PREFIX + currentProduction.name
/#function

#macro BuildExpansionCode expansion
   #var classname=expansion.simpleName
   #var prevLexicalStateVar = CU.newVarName("previousLexicalState")
   #-- take care of the non-tree-building classes --
   #if classname = "CodeBlock"
      ${expansion}
   #elseif classname = "UncacheTokens"
         uncacheTokens();
   #elseif classname = "Failure"
      [@BuildCodeFailure expansion/]
   #elseif classname = "Assertion"
      [@BuildAssertionCode expansion/]
   #elseif classname = "TokenTypeActivation"
      [@BuildCodeTokenTypeActivation expansion/]
   #elseif classname = "TryBlock"
      [@BuildCodeTryBlock expansion/]
   #elseif classname = "AttemptBlock"
      [@BuildCodeAttemptBlock expansion /]
   #else
      #-- take care of the tree node (if any) --
      [@TreeBuildingAndRecovery expansion]
         #if classname = "BNFProduction"
            #-- The tree node having been built, now build the actual top-level expansion --
            #set topLevelExpansion = true
            [@BuildCode expansion.nestedExpansion/]
         #else
            #-- take care of terminal and non-terminal expansions; they cannot contain child expansions --
            #if classname = "NonTerminal"
               [@BuildCodeNonTerminal expansion/]
            #elseif classname = "Terminal"
               [@BuildCodeTerminal expansion /]
            #else
               #-- take care of the syntactical expansions (which can contain child expansions) --
               #-- capture the top-level indication in order to restore when bubbling up --
               #var stackedTopLevel = topLevelExpansion
               #if topLevelExpansion && classname != "ExpansionSequence"
                  #-- turn off top-level indication unless an expansion sequence (the tree node has already been determined when this nested template is expanded) --
                  #set topLevelExpansion = false
               [/#if]
               #if classname = "ZeroOrOne"
                  [@BuildCodeZeroOrOne expansion/]
               #elseif classname = "ZeroOrMore"
                  [@BuildCodeZeroOrMore expansion/]
               #elseif classname = "OneOrMore"
                  [@BuildCodeOneOrMore expansion/]
               #elseif classname = "ExpansionChoice"
                  [@BuildCodeChoice expansion/]
               #elseif classname = "ExpansionWithParentheses"
                  #-- Recurse; the real expansion is nested within this one (but the LHS, if any, is on the parent) --
                  [@BuildExpansionCode expansion.nestedExpansion/]
               #elseif classname = "ExpansionSequence"
                  [@BuildCodeSequence expansion/] [#-- leave the topLevelExpansion one-shot alone (see above) --]
               /#if
               #set topLevelExpansion = stackedTopLevel
            /#if
         /#if
      [/@TreeBuildingAndRecovery]
   /#if
/#macro

#-- The following macros build expansions that never build tree nodes. --

#macro BuildCodeFailure fail
    #if fail.code?is_null
      #if fail.exp??
       fail("Failure: " + ${fail.exp}, getToken(1));
      #else
       fail("Failure", getToken(1));
      /#if
    #else
       ${fail.code}
    /#if
/#macro

#macro BuildAssertionCode assertion
   #var optionalPart = ""
   #if assertion.messageExpression??
      #set optionalPart = " + " + assertion.messageExpression
   /#if
   #var assertionMessage = "Assertion at: " + assertion.location?j_string + " failed. "
   #if assertion.assertionExpression??
      if (!(${assertion.assertionExpression})) {
         fail("${assertionMessage}"${optionalPart}, getToken(1));
      }
   /#if
   #if assertion.expansion??
      if ( [#if !assertion.expansionNegated]![/#if]
      ${assertion.expansion.scanRoutineName}()) {
         fail("${assertionMessage}"${optionalPart}, getToken(1));
      }
   /#if
/#macro

#macro BuildCodeTokenTypeActivation activation
    #if activation.deactivate
       deactivateTokenTypes(
    #else
       activateTokenTypes(
    /#if
    #list activation.tokenNames as name
       ${name} [#if name_has_next],[/#if]
    /#list
       );
/#macro

#macro BuildCodeTryBlock tryblock
     try {
        [@BuildCode tryblock.nestedExpansion /]
     }
   #list tryblock.catchBlocks as catchBlock
     ${catchBlock}
   /#list
     ${tryblock.finallyBlock!}
/#macro

#macro BuildCodeAttemptBlock attemptBlock
   try {
      stashParseState();
      [@BuildCode attemptBlock.nestedExpansion /]
      popParseState();
   }
   #var pe = exceptionVar(true)
   catch (ParseException ${pe}) {
      restoreStashedParseState();
      [@BuildCode attemptBlock.recoveryExpansion /]
      #set exceptionNesting = exceptionNesting - 1
   }
[/#macro]

#-- The following macros build expansions that might build tree nodes (could be called "syntactic" nodes). --

#macro BuildCodeNonTerminal nonterminal
   pushOntoCallStack("${nonterminal.containingProduction.name}", "${nonterminal.inputSource?j_string}", ${nonterminal.beginLine}, ${nonterminal.beginColumn});
   #if settings.faultTolerant
      #var followSet = nonterminal.followSet
      #if !followSet.incomplete
         #if !nonterminal.beforeLexicalStateSwitch
            outerFollowSet = ${nonterminal.followSetVarName};
         #else
            outerFollowSet = null;
         /#if
      #elseif !followSet.empty
         if (outerFollowSet != null) {
            EnumSet<TokenType> newFollowSet = ${nonterminal.followSetVarName}.clone();
            newFollowSet.addAll(outerFollowSet);
            outerFollowSet = newFollowSet;
         }
      /#if
   /#if
   try {
      [@AcceptNonTerminal nonterminal /]
   }
   finally {
       popCallStack();
   }
/#macro

#macro AcceptNonTerminal nonterminal
   #var lhsClassName = nonterminal.production.nodeName,
        expressedLHS = getLhsPattern(nonterminal.assignment,lhsClassName),
        impliedLHS = "@"
   #if jtbParseTree && isProductionInstantiatingNode(nonterminal.production) && topLevelExpansion
      #var newName = imputedJtbFieldName(nonterminal.production.nodeName)
      #set impliedLHS = globals::translateIdentifier("THIS_PRODUCTION") + "." + newName + " = @"
   /#if
   #-- Accept the non-terminal expansion --
   #if nonterminal.production.returnType != "void" && expressedLHS != "@" && !nonterminal.assignment.namedAssignment && !nonterminal.assignment.propertyAssignment
      #-- Not a void production, so accept and clear the expressedLHS, it has already been applied. --
      ${expressedLHS?replace("@", nonterminal.name + "(" + nonterminal.args! + ")")};
      #set expressedLHS = "@"
   #else
      ${nonterminal.name}(${nonterminal.args!});
   /#if
   #if expressedLHS != "@" || impliedLHS != "@"
      #if nonterminal.assignment?? && (nonterminal.assignment.addTo!false || nonterminal.assignment.namedAssignment)
         if (buildTree) {
            #if impliedLHS == "@"
               ${expressedLHS?replace("@", impliedLHS?replace("@", "peekNode()"))};
            #else
               ${expressedLHS?replace("@", impliedLHS?replace("@", "(" + nonterminal.production.nodeName + ") peekNode()"))};
            /#if
         }
      #else
         try {
            #-- There had better be a node here! --
            ${expressedLHS?replace("@", impliedLHS?replace("@", "(" + nonterminal.production.nodeName + ") peekNode()"))};
         } catch (ClassCastException cce) {
            ${expressedLHS?replace("@", impliedLHS?replace("@", "null"))};
         }
      /#if
   /#if
/#macro

#macro BuildCodeTerminal terminal
   #var LHS = getLhsPattern(terminal.assignment, "Token"), regexp=terminal.regexp
   #if !settings.faultTolerant
       ${LHS?replace("@", "consumeToken(" + regexp.label + ")")};
   #else
       #var tolerant = terminal.tolerantParsing?string("true", "false"),
            followSetVarName = terminal.followSetVarName
       #if terminal.followSet.incomplete
         #set followSetVarName = "followSet" + CU.newID()
         EnumSet<TokenType> ${followSetVarName} = null;
         if (outerFollowSet != null) {
            ${followSetVarName} = ${terminal.followSetVarName}.clone();
            ${followSetVarName}.addAll(outerFollowSet);
         }
       /#if
       ${LHS?replace("@", "consumeToken(" + regexp.label + ", " + tolerant + ", " + followSetVarName + ")")};
   /#if
/#macro

#macro BuildCodeZeroOrOne zoo
    #if zoo.nestedExpansion.class.simpleName = "ExpansionChoice"
       [@BuildCode zoo.nestedExpansion /]
    #else
       if (${ExpansionCondition(zoo.nestedExpansion)}) {
          ${BuildCode(zoo.nestedExpansion)}
       }
    /#if
/#macro

#var inFirstVarName = "",
     inFirstIndex =0

#macro BuildCodeOneOrMore oom
   #var nestedExp=oom.nestedExpansion, prevInFirstVarName = inFirstVarName
   #if nestedExp.simpleName = "ExpansionChoice"
     #set inFirstVarName = "inFirst" + inFirstIndex, inFirstIndex = inFirstIndex +1
     boolean ${inFirstVarName} = true;
   /#if
   while (true) {
      [@RecoveryLoop oom /]
      #if nestedExp.simpleName = "ExpansionChoice"
         ${inFirstVarName} = false;
      #else
         if (!(${ExpansionCondition(oom.nestedExpansion)})) break;
      /#if
   }
   #set inFirstVarName = prevInFirstVarName
/#macro

#macro BuildCodeZeroOrMore zom
    while (true) {
       #if zom.nestedExpansion.class.simpleName != "ExpansionChoice"
         if (!(${ExpansionCondition(zom.nestedExpansion)})) break;
       /#if
       [@RecoveryLoop zom/]
    }
/#macro

#macro RecoveryLoop loopExpansion
   #if !settings.faultTolerant || !loopExpansion.requiresRecoverMethod
       ${BuildCode(loopExpansion.nestedExpansion)}
   #else
       #var initialTokenVarName = "initialToken" + CU.newID()
       ${settings.baseTokenClassName} ${initialTokenVarName} = lastConsumedToken;
       try {
          ${BuildCode(loopExpansion.nestedExpansion)}
       } catch (ParseException pe) {
          if (!isParserTolerant()) throw pe;
          if (${initialTokenVarName} == lastConsumedToken) {
             lastConsumedToken = nextToken(lastConsumedToken);
             //We have to skip a token in this spot or
             // we'll be stuck in an infinite loop!
             lastConsumedToken.setSkipped(true);
          }
          ${loopExpansion.recoverMethodName}();
          if (pendingRecovery) throw pe;
       }
   /#if
/#macro

#macro BuildCodeChoice choice
   #list choice.choices as expansion
      #if expansion.enteredUnconditionally
        {
         ${BuildCode(expansion)}
         #if jtbParseTree && isProductionInstantiatingNode(expansion)
            ${globals.currentNodeVariableName}.setChoice(${expansion_index});
         [/#if]
        }
        #if expansion_has_next
            #var nextExpansion = choice[expansion_index+1]
            // Warning: choice at ${nextExpansion.location} is is ignored because the
            // choice at ${expansion.location} is entered unconditionally and we jump
            // out of the loop..
        /#if
         #return
      /#if
      if (${ExpansionCondition(expansion)}) {
         ${BuildCode(expansion)}
         #if jtbParseTree && isProductionInstantiatingNode(expansion)
            ${globals.currentNodeVariableName}.setChoice(${expansion_index});
         [/#if]
      }
      [#if expansion_has_next] else [/#if]
   /#list
   #if choice.parent.simpleName == "ZeroOrMore"
      else {
         break;
      }
   #elseif choice.parent.simpleName = "OneOrMore"
       else if (${inFirstVarName}) {
           pushOntoCallStack("${currentProduction.name}", "${choice.inputSource?j_string}", ${choice.beginLine}, ${choice.beginColumn});
           throw new ParseException(lastConsumedToken, ${choice.firstSetVarName}, parsingStack);
       } else {
           break;
       }
   #elseif choice.parent.simpleName != "ZeroOrOne"
       else {
           pushOntoCallStack("${currentProduction.name}", "${choice.inputSource?j_string}", ${choice.beginLine}, ${choice.beginColumn});
           throw new ParseException(lastConsumedToken, ${choice.firstSetVarName}, parsingStack);
        }
   /#if
/#macro

#macro BuildCodeSequence expansion
       #list expansion.units as subexp
           [@BuildCode subexp/]
       /#list
/#macro

#-- The following is a set of utility macros used in expansion expansions. --

[#--
     Macro to generate the condition for entering an expansion
     including the default single-token lookahead
--]
#macro ExpansionCondition expansion
    #if expansion.requiresPredicateMethod
       ${ScanAheadCondition(expansion)}
    #else
       ${SingleTokenCondition(expansion)}
    /#if
/#macro

#-- Generates code for when we need a scanahead --
#macro ScanAheadCondition expansion
   #if expansion.lookahead?? && expansion.lookahead.assignment??
      (${expansion.lookahead.assignment.name} =
   /#if
   #if expansion.hasSemanticLookahead && !expansion.lookahead.semanticLookaheadNested
      (${expansion.semanticLookahead}) &&
   /#if
   ${expansion.predicateMethodName}()
   #if expansion.lookahead?? && expansion.lookahead.assignment??
      )
   /#if
/#macro


#-- Generates code for when we don't need any scanahead routine. --
#macro SingleTokenCondition expansion
   #if expansion.hasSemanticLookahead
      (${expansion.semanticLookahead}) &&
   /#if
   #if expansion.enteredUnconditionally
      true
   #elseif expansion.firstSet.tokenNames?size ==0
      false
   #elseif expansion.firstSet.tokenNames?size < CU.USE_FIRST_SET_THRESHOLD
      #list expansion.firstSet.tokenNames as name
          nextTokenType [#if name_index ==0]() [/#if]
          == ${name}
         [#if name_has_next] || [/#if]
      /#list
   #else
      ${expansion.firstSetVarName}.contains(nextTokenType())
   /#if
/#macro
