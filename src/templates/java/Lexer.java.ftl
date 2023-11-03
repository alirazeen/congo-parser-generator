 /* Generated by: ${generated_by}. ${filename} ${settings.copyrightBlurb} */
 
 [#--
    This template generates the XXXLexer.java class.
    The details of generating the code for the NFA state machine
    are in the imported template NfaCode.java.ftl
 --]

 [#var TOKEN = settings.baseTokenClassName]
 
package ${settings.parserPackage};

import ${settings.parserPackage}.${TOKEN}.TokenType;
import static ${settings.parserPackage}.${TOKEN}.TokenType.*;
[#if settings.rootAPIPackage?has_content]
   import ${settings.rootAPIPackage}.Node;
   import ${settings.rootAPIPackage}.TokenSource;
[/#if]

[#import "NfaCode.java.ftl" as NFA]

[#var lexerData=grammar.lexerData]

[#var PRESERVE_LINE_ENDINGS=settings.preserveLineEndings?string("true", "false")
      JAVA_UNICODE_ESCAPE= settings.javaUnicodeEscape?string("true", "false")
      PRESERVE_TABS = settings.preserveTabs?string("true", "false")
      TERMINATING_STRING = "\"" + settings.terminatingString?j_string + "\""
]      
[#var BaseToken = settings.treeBuildingEnabled?string("Node.TerminalNode", "${TOKEN}")]

[#macro EnumSet varName tokenNames]
   [#if tokenNames?size=0]
       static final EnumSet<TokenType> ${varName} = EnumSet.noneOf(TokenType.class);
   [#else]
       static final EnumSet<TokenType> ${varName} = EnumSet.of(
       [#list tokenNames as type]
          [#if type_index > 0],[/#if]
          ${type} 
       [/#list]
     ); 
   [/#if]
[/#macro]

import java.io.IOException;
import java.util.*;

[#if settings.rootAPIPackage?has_content]
import ${settings.rootAPIPackage}.TokenSource;
[/#if]

public 
[#if isFinal]final[/#if]
class ${settings.lexerClassName} extends TokenSource
{
    
  private static MatcherHook MATCHER_HOOK; // this cannot be initialize here, since hook must be set afterwards

  public enum LexicalState {
  [#list lexerData.lexicalStates as lexicalState]
     ${lexicalState.name}
     [#if lexicalState_has_next],[/#if]
  [/#list]
  }  
  LexicalState lexicalState = LexicalState.values()[0];

 [#if settings.lexerUsesParser]
  private ${settings.parserClassName} parser;

  public ${settings.parserClassName} getParser() {return parser;}

  public void setParser(${settings.parserClassName} parser) {this.parser = parser;}
 [/#if]

   [#if settings.deactivatedTokens?size>0]
    EnumSet<TokenType> activeTokenTypes = EnumSet.allOf(TokenType.class);
  [#else]
    EnumSet<TokenType> activeTokenTypes = null;
  [/#if]
  [#if settings.deactivatedTokens?size>0]
     {
       [#list settings.deactivatedTokens as token]
          activeTokenTypes.remove(${token});
       [/#list]
     }
  [/#if]

 
  // A lookup for lexical state transitions triggered by a certain token type
  private static EnumMap<TokenType, LexicalState> tokenTypeToLexicalStateMap = new EnumMap<>(TokenType.class);
  // ${TOKEN} types that are "regular" tokens that participate in parsing,
  // i.e. declared as TOKEN
  [@EnumSet "regularTokens" lexerData.regularTokens.tokenNames /]
  // ${TOKEN} types that do not participate in parsing
  // i.e. declared as UNPARSED (or SPECIAL_TOKEN)
  [@EnumSet "unparsedTokens" lexerData.unparsedTokens.tokenNames /]
  // Tokens that are skipped, i.e. SKIP 
  [@EnumSet "skippedTokens" lexerData.skippedTokens.tokenNames /]
  // Tokens that correspond to a MORE, i.e. that are pending 
  // additional input
  [@EnumSet "moreTokens" lexerData.moreTokens.tokenNames /]
  [#if settings.extraTokens?size >0]
     static {
     [#list settings.extraTokenNames as token]
         regularTokens.add(${token});
     [/#list]
     }
  [/#if]
  
    public ${settings.lexerClassName}(CharSequence input) {
        this("input", input);
    }

    /**
     * @param inputSource just the name of the input source (typically the filename)
     * that will be used in error messages and so on.
     * @param input the input
     */
    public ${settings.lexerClassName}(String inputSource, CharSequence input) {
        this(inputSource, input, LexicalState.${lexerData.lexicalStates[0].name}, 1, 1);
    }

     /**
      * @param inputSource just the name of the input source (typically the filename) that 
      * will be used in error messages and so on.
      * @param input the input
      * @param lexicalState The starting lexical state, may be null to indicate the default
      * starting state
      * @param line The line number at which we are starting for the purposes of location/error messages. In most 
      * normal usage, this is 1.
      * @param column number at which we are starting for the purposes of location/error messages. In most normal
      * usages this is 1.
      */
     public ${settings.lexerClassName}(String inputSource, CharSequence input, LexicalState lexState, int startingLine, int startingColumn) {
        super(inputSource, input, startingLine, startingColumn,
                        ${settings.tabSize}, ${PRESERVE_TABS}, 
                        ${PRESERVE_LINE_ENDINGS}, 
                        ${JAVA_UNICODE_ESCAPE}, 
                        ${TERMINATING_STRING});
        if (lexicalState != null) switchTo(lexState);
     [#if settings.cppContinuationLine]
        handleCContinuationLines();
     [/#if]
     }

     public ${TOKEN} getNextToken(${TOKEN} tok) {
        return getNextToken(tok, this.activeTokenTypes);
     }

  /**
   * The public method for getting the next token, that is
   * called by ${settings.parserClassName}.
   * It checks whether we have already cached
   * the token after this one. If not, it finally goes 
   * to the NFA machinery
   */ 
    public ${TOKEN} getNextToken(${TOKEN} tok, EnumSet<TokenType> activeTokenTypes) {
       if (tok == null) {
          tok = tokenizeAt(0, null, activeTokenTypes);
          cacheToken(tok);
          return tok;
       }
       ${TOKEN} cachedToken = tok.nextCachedToken();
    // If the cached next token is not currently active, we
    // throw it away and go back to the ${settings.lexerClassName} 
       if (cachedToken != null && activeTokenTypes != null && !activeTokenTypes.contains(cachedToken.getType())) {
           reset(tok);
           cachedToken = null;
       }
       if (cachedToken == null) {
           ${TOKEN} token = tokenizeAt(tok.getEndOffset(), null, activeTokenTypes);
           cacheToken(token);
           return token;
       }
       return cachedToken;
    }

  static class MatchInfo {
      TokenType matchedType;
      int matchLength;
        
      @Override
      public int hashCode() {
          return Objects.hash(matchLength, matchedType);
      }
      @Override
      public boolean equals(Object obj) {
          if (this == obj)
              return true;
          if (obj == null)
              return false;
          if (getClass() != obj.getClass())
              return false;
          MatchInfo other = (MatchInfo) obj;
          return matchLength == other.matchLength && matchedType == other.matchedType;
      }
  }
    
  @FunctionalInterface
    private static interface MatcherHook {
      MatchInfo apply(LexicalState lexicalState, CharSequence input, int position, EnumSet<TokenType> activeTokenTypes, NfaFunction[] nfaFunctions, BitSet currentStates, BitSet nextStates, MatchInfo matchInfo);
  }

  /**
   * Core tokenization method. Note that this can be called from a static context.
   * Hence the extra parameters that need to be passed in.
   */
  static MatchInfo getMatchInfo(CharSequence input, int position, EnumSet<TokenType> activeTokenTypes, NfaFunction[] nfaFunctions, BitSet currentStates, BitSet nextStates, MatchInfo matchInfo) {
       if (matchInfo == null) {
           matchInfo = new MatchInfo();
       }
       if (position >= input.length()) {
           matchInfo.matchedType = EOF;
           matchInfo.matchLength = 0;
           return matchInfo;
       }
       int start = position;
       int matchLength = 0;
       TokenType matchedType = TokenType.INVALID;
       EnumSet<TokenType> alreadyMatchedTypes = EnumSet.noneOf(TokenType.class);
       if (currentStates == null) currentStates = new BitSet(${lexerData.maxNfaStates});
       else currentStates.clear();
       if (nextStates == null) nextStates=new BitSet(${lexerData.maxNfaStates});
       else nextStates.clear();
        // the core NFA loop
        do {
            // Holder for the new type (if any) matched on this iteration
            if (position > start) {
                // What was nextStates on the last iteration 
                // is now the currentStates!
                BitSet temp = currentStates;
                currentStates = nextStates;
                nextStates = temp;
                nextStates.clear();
    [#if settings.usesPreprocessor]
                if (input instanceof TokenSource) {
                    position = ((TokenSource) input).nextUnignoredOffset(position);
                }
    [/#if]                
            } else {
                currentStates.set(0);
            }
            if (position >= input.length()) {
                break;
            }
            int curChar = Character.codePointAt(input, position++);
            if (curChar > 0xFFFF) position++;
            int nextActive = currentStates.nextSetBit(0);
            while(nextActive != -1) {
                TokenType returnedType = nfaFunctions[nextActive].apply(curChar, nextStates, activeTokenTypes, alreadyMatchedTypes);
                if (returnedType != null && (position - start > matchLength || returnedType.ordinal() < matchedType.ordinal())) {
                    matchedType = returnedType;
                    matchLength = position - start;
                    alreadyMatchedTypes.add(returnedType);
                }
                nextActive = currentStates.nextSetBit(nextActive+1);
            }
            if (position >= input.length()) break;
       } while (!nextStates.isEmpty());
       matchInfo.matchedType = matchedType;
       matchInfo.matchLength = matchLength;
       return matchInfo;
  }

  /**
   * @param position The position at which to tokenize.
   * @param lexicalState The lexical state in which to tokenize. If this is null, it is the instance variable #lexicalState
   * @param activeTokenTypes The active token types. If this is null, they are all active.
   * @return the Token at position
   */
  final ${TOKEN} tokenizeAt(int position, LexicalState lexicalState, EnumSet<TokenType> activeTokenTypes) {
      if (lexicalState == null) lexicalState = this.lexicalState;
      int tokenBeginOffset = position;
      boolean inMore = false;
      StringBuilder invalidChars = null;
      ${TOKEN} matchedToken = null;
      TokenType matchedType = null;
      // The core tokenization loop
      MatchInfo matchInfo = new MatchInfo();
      BitSet currentStates = new BitSet(${lexerData.maxNfaStates});
      BitSet nextStates = new BitSet(${lexerData.maxNfaStates});
      while (matchedToken == null) {
      [#if NFA.multipleLexicalStates]
       // Get the NFA function table for the current lexical state.
       // If we are in a MORE, there is some possibility that there 
       // was a lexical state change since the last iteration of this loop!
        NfaFunction[] nfaFunctions = functionTableMap.get(lexicalState);
      [/#if]
[#if settings.usesPreprocessor]      
        position = nextUnignoredOffset(position);
[/#if]        
        if (!inMore) tokenBeginOffset = position;
        if (MATCHER_HOOK != null) {
            matchInfo = MATCHER_HOOK.apply(lexicalState, this, position, activeTokenTypes, nfaFunctions, currentStates, nextStates, matchInfo);
            if (matchInfo == null) {
                matchInfo = getMatchInfo(this, position, activeTokenTypes, nfaFunctions, currentStates, nextStates, matchInfo);
            }
        } else {
            matchInfo = getMatchInfo(this, position, activeTokenTypes, nfaFunctions, currentStates, nextStates, matchInfo);
        }
        matchedType = matchInfo.matchedType;
        inMore = moreTokens.contains(matchedType);
        position += matchInfo.matchLength;
     [#if lexerData.hasLexicalStateTransitions]
        LexicalState newState = tokenTypeToLexicalStateMap.get(matchedType);
        if (newState !=null) {
            lexicalState = this.lexicalState = newState;
        }
     [/#if]
        if (matchedType == TokenType.INVALID) {
            if (invalidChars==null) {
                invalidChars=new StringBuilder();
            } 
            int cp  = Character.codePointAt(this, tokenBeginOffset);
            invalidChars.appendCodePoint(cp);
            ++position;
            if (cp >0xFFFF) ++position;
            continue;
        }
        if (invalidChars !=null) {
            return new InvalidToken(this, tokenBeginOffset - invalidChars.length(), tokenBeginOffset);
        }
        if (skippedTokens.contains(matchedType)) {
            skipTokens(tokenBeginOffset, position);
        }
        else if (regularTokens.contains(matchedType) || unparsedTokens.contains(matchedType)) {
            matchedToken = ${TOKEN}.newToken(matchedType, 
                                        this, 
                                        tokenBeginOffset,
                                        position);
            matchedToken.setUnparsed(!regularTokens.contains(matchedType));
        }
      }
[#if lexerData.hasLexicalStateTransitions]
      doLexicalStateSwitch(matchedToken.getType());
 [/#if]
 [#if lexerData.hasTokenActions]
      matchedToken = tokenLexicalActions(matchedToken, matchedType);
 [/#if  ]
 [#list grammar.lexerTokenHooks as tokenHookMethodName]
    [#if tokenHookMethodName = "CommonTokenAction"]
           ${tokenHookMethodName}(matchedToken);
    [#else]
            matchedToken = ${tokenHookMethodName}(matchedToken);
    [/#if]
 [/#list]
       return matchedToken;
   }


[#if lexerData.hasLexicalStateTransitions]
  // Generate the map for lexical state transitions from the various token types
  static {
    [#list grammar.lexerData.regularExpressions as regexp]
      [#if !regexp.newLexicalState?is_null]
          tokenTypeToLexicalStateMap.put(${regexp.label}, LexicalState.${regexp.newLexicalState.name});
      [/#if]
    [/#list]
  }

  boolean doLexicalStateSwitch(TokenType tokenType) {
       LexicalState newState = tokenTypeToLexicalStateMap.get(tokenType);
       if (newState == null) return false;
       return switchTo(newState);
  }
[/#if]
  
    /** 
     * Switch to specified lexical state. 
     * @param lexState the lexical state to switch to
     * @return whether we switched (i.e. we weren't already in the desired lexical state)
     */
    public boolean switchTo(LexicalState lexState) {
        if (this.lexicalState != lexState) {
           this.lexicalState = lexState;
           return true;
        }
        return false;
    }

    // Reset the token source input
    // to just after the ${TOKEN} passed in.
    void reset(${TOKEN} t, LexicalState state) {
[#list grammar.resetTokenHooks as resetTokenHookMethodName]
      ${resetTokenHookMethodName}(t);
[/#list]
      uncacheTokens(t);
      if (state != null) {
          switchTo(state);
      }
[#if lexerData.hasLexicalStateTransitions] 
      else {
          doLexicalStateSwitch(t.getType());
      }
[/#if]        
    }

  void reset(${TOKEN} t) {
      reset(t, null);
  }
    
 [#if lexerData.hasTokenActions]
  private ${TOKEN} tokenLexicalActions(${TOKEN} matchedToken, TokenType matchedType) {
    switch(matchedType) {
   [#list lexerData.regularExpressions as regexp]
        [#if regexp.codeSnippet?has_content]
      case ${regexp.label} :
          ${regexp.codeSnippet.javaCode}
           break;
        [/#if]
   [/#list]
      default : break;
    }
    return matchedToken;
  }
 [/#if]

[#if settings.tokenChaining]        
    @Override
    public void cacheToken(${BaseToken} tok) {
        ${TOKEN} token = (${TOKEN}) tok;
        if (token.isInserted()) {
            ${TOKEN} next = token.nextCachedToken();
            if (next != null) cacheToken(next);
            return;
        }
        super.cacheToken(tok);
    }
    
    @Override
    public void uncacheTokens(${BaseToken} lastToken) {
        super.uncacheTokens(lastToken);
        ((${TOKEN})lastToken).unsetAppendedToken();
    }
[/#if]    

 

  // Utility methods. Having them here makes it easier to handle things
  // more uniformly in other generation languages.

   private boolean atLineStart(${TOKEN} tok) {
      int offset = tok.getBeginOffset();
      while (offset > 0) {
        --offset;
        char c = charAt(offset);
        if (!Character.isWhitespace(c)) return false;
        if (c=='\n') break;
      }
      return true;
   }

   private String getLine(${TOKEN} tok) {
       int lineNum = tok.getBeginLine();
       return getText(getLineStartOffset(lineNum), getLineEndOffset(lineNum)+1);
   }

  
  // NFA related code follows.

  // The functional interface that represents 
  // the acceptance method of an NFA state
  static interface NfaFunction {
      TokenType apply(int ch, BitSet bs, EnumSet<TokenType> validTypes, EnumSet<TokenType> alreadyMatchedTypes);
  }

 [#if NFA.multipleLexicalStates]
  // A lookup of the NFA function tables for the respective lexical states.
  private static final EnumMap<LexicalState,NfaFunction[]> functionTableMap = new EnumMap<>(LexicalState.class);
 [#else]
  [#-- We don't need the above lookup if there is only one lexical state.--]
   private static NfaFunction[] nfaFunctions;
 [/#if]
 
  // Initialize the various NFA method tables
  static {
    [#list grammar.lexerData.lexicalStates as lexicalState]
      ${lexicalState.name}.NFA_FUNCTIONS_init();
    [/#list]
  }

 //The Nitty-gritty of the NFA code follows.
 [#list lexerData.lexicalStates as lexicalState]
 /**
  * Holder class for NFA code related to ${lexicalState.name} lexical state
  */
  private static class ${lexicalState.name} {
   [@NFA.GenerateStateCode lexicalState/]
  }
 [/#list]  
}
