 /* Generated by: ${generated_by}. ${filename} ${settings.copyrightBlurb} */
 
 [#--
    This template generates the XXXLexer.java class.
    The details of generating the code for the NFA state machine
    are in the imported template NfaCode.java.ftl
 --]
 
package ${settings.parserPackage};

import ${settings.parserPackage}.${settings.baseTokenClassName}.TokenType;
import static ${settings.parserPackage}.${settings.baseTokenClassName}.TokenType.*;
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
[#var BaseToken = settings.treeBuildingEnabled?string("Node.TerminalNode", "${settings.baseTokenClassName}")]

[#macro EnumSet varName tokenNames]
   [#if tokenNames?size=0]
       static private final EnumSet<TokenType> ${varName} = EnumSet.noneOf(TokenType.class);
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
import java.util.Arrays;
import java.util.BitSet;
import java.util.EnumMap;
import java.util.EnumSet;

[#if settings.rootAPIPackage?has_content]
import ${settings.rootAPIPackage}.TokenSource;
[/#if]

public class ${settings.lexerClassName} extends TokenSource
{

 public enum LexicalState {
  [#list lexerData.lexicalStates as lexicalState]
     ${lexicalState.name}
     [#if lexicalState_has_next],[/#if]
  [/#list]
 }  
   LexicalState lexicalState = LexicalState.values()[0];
 [#if settings.lexerUsesParser]
  public ${settings.parserClassName} parser;
 [/#if]

  EnumSet<TokenType> activeTokenTypes = EnumSet.allOf(TokenType.class);
  [#if settings.deactivatedTokens?size>0 || settings.extraTokens?size >0]
     {
       [#list settings.deactivatedTokens as token]
          activeTokenTypes.remove(${token});
       [/#list]
       [#list settings.extraTokenNames as token]
          regularTokens.add(${token});
       [/#list]
     }
  [/#if]

  // A lookup for lexical state transitions triggered by a certain token type
  private static EnumMap<TokenType, LexicalState> tokenTypeToLexicalStateMap = new EnumMap<>(TokenType.class);
  // ${settings.baseTokenClassName} types that are "regular" tokens that participate in parsing,
  // i.e. declared as TOKEN
  [@EnumSet "regularTokens" lexerData.regularTokens.tokenNames /]
  // ${settings.baseTokenClassName} types that do not participate in parsing
  // i.e. declared as UNPARSED (or SPECIAL_TOKEN)
  [@EnumSet "unparsedTokens" lexerData.unparsedTokens.tokenNames /]
  // Tokens that are skipped, i.e. SKIP 
  [@EnumSet "skippedTokens" lexerData.skippedTokens.tokenNames /]
  // Tokens that correspond to a MORE, i.e. that are pending 
  // additional input
  [@EnumSet "moreTokens" lexerData.moreTokens.tokenNames /]


   
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

  /**
   * The public method for getting the next token.
   * It checks whether we have already cached
   * the token after this one. If not, it finally goes 
   * to the NFA machinery
   */ 
    public ${settings.baseTokenClassName} getNextToken(${settings.baseTokenClassName} tok) {
       if (tok == null) {
          tok = nextToken(0);
          cacheToken(tok);
          return tok;
       }
       ${settings.baseTokenClassName} cachedToken = tok.nextCachedToken();
    // If the cached next token is not currently active, we
    // throw it away and go back to the XXXLexer
       if (cachedToken != null && !activeTokenTypes.contains(cachedToken.getType())) {
           reset(tok);
           cachedToken = null;
       }
       if (cachedToken == null) {
           ${settings.baseTokenClassName} token = nextToken(tok.getEndOffset());
           cacheToken(token);
           return token;
       }
       return cachedToken;
    }

  private final ${settings.baseTokenClassName} nextToken(int position) {
      position = nextUnignoredOffset(position);
      ${settings.baseTokenClassName} matchedToken = position >= length() ?
         ${settings.baseTokenClassName}.newToken(EOF, this, position, position)
         : nextToken(position, this, this.activeTokenTypes, this.lexicalState);
 [#if lexerData.hasLexicalStateTransitions]
      doLexicalStateSwitch(matchedToken.getType());
 [/#if]
 [#if lexerData.hasTokenActions]
      matchedToken = tokenLexicalActions(matchedToken, matchedType);
 [/#if]
 [#list grammar.lexerTokenHooks as tokenHookMethodName]
    [#if tokenHookMethodName = "CommonTokenAction"]
           ${tokenHookMethodName}(matchedToken);
    [#else]
            matchedToken = ${tokenHookMethodName}(matchedToken);
    [/#if]
 [/#list]
      return matchedToken;
  }

  static class MatchInfo {
      TokenType matchedType;
      int matchLength;
      boolean reachedEnd;

      MatchInfo(TokenType matchedType, int matchLength, boolean reachedEnd) {
          this.matchedType = matchedType;
          this.matchLength = matchLength;
          this.reachedEnd = reachedEnd;
      }
  }

  static MatchInfo getMatchInfo(int position, CharSequence input, EnumSet<TokenType> activeTokenTypes, NfaFunction[] nfaFunctions) {
       if (position >= input.length()) {
          return new MatchInfo(EOF, 0, true);
       }
       assert position < input.length();
       if (input instanceof TokenSource) {
           position = ((TokenSource) input).nextUnignoredOffset(position);
       }
       int start = position, matchLength = 0;
       TokenType matchedType = null;
       BitSet currentStates = new BitSet(${lexerData.maxNfaStates}),
              nextStates=new BitSet(${lexerData.maxNfaStates});
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
                if (input instanceof TokenSource) {
                    position = ((TokenSource) input).nextUnignoredOffset(position);
                }
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
                TokenType returnedType = nfaFunctions[nextActive].apply(curChar, nextStates, activeTokenTypes);
                if (returnedType != null && (position - start > matchLength || returnedType.ordinal() < matchedType.ordinal())) {
                    matchedType = returnedType;
                    matchLength = position - start;
                }
                nextActive = currentStates.nextSetBit(nextActive+1);
            }
            if (position >= input.length()) break;
       } while (!nextStates.isEmpty());
       return new MatchInfo(matchedType, matchLength, position >= input.length());
  }

// The main method to invoke the NFA machinery
  private final ${settings.baseTokenClassName} nextToken(int position, CharSequence input, EnumSet<TokenType> activeTokenTypes, LexicalState lexicalState) {
      boolean inMore = false;
      StringBuilder invalidChars = null;
      int tokenBeginOffset = position;
      // The core tokenization loop
      while (true) {
      [#if NFA.multipleLexicalStates]
       // Get the NFA function table current lexical state
       // There is some possibility that there was a lexical state change
       // since the last iteration of this loop!
        NfaFunction[] nfaFunctions = functionTableMap.get(lexicalState);
      [/#if]
        if (this instanceof TokenSource) {
            position = ((TokenSource)input).nextUnignoredOffset(position);
        }
        if (!inMore) tokenBeginOffset = position;
        MatchInfo matchInfo = getMatchInfo(position, input, activeTokenTypes, nfaFunctions);
        int matchLength = matchInfo.matchLength;
        TokenType matchedType = matchInfo.matchedType;
        inMore = moreTokens.contains(matchedType);
        position += matchLength;

     [#if lexerData.hasLexicalStateTransitions]
        LexicalState newState = tokenTypeToLexicalStateMap.get(matchedType);
        if (newState !=null) {
            lexicalState = this.lexicalState = newState;
        }
     [/#if]
        if (matchedType == null) {
            if (invalidChars==null) {
                invalidChars=new StringBuilder();
            } 
            invalidChars.appendCodePoint(Character.codePointAt(input, tokenBeginOffset));
            position = forward(input, tokenBeginOffset, 1);
            continue;
        }
        if (matchedType == INVALID) {
           return new InvalidToken(this, tokenBeginOffset, position);
        }
        if (invalidChars !=null) {
            position = tokenBeginOffset;
            return new InvalidToken(this, tokenBeginOffset - invalidChars.length(), tokenBeginOffset);
        }
        if (skippedTokens.contains(matchedType)) {
            skipTokens(tokenBeginOffset, position);
        }
        else if (regularTokens.contains(matchedType) || unparsedTokens.contains(matchedType)) {
            ${settings.baseTokenClassName} matchedToken = ${settings.baseTokenClassName}.newToken(matchedType, 
                                        this, 
                                        tokenBeginOffset,
                                        position);
            matchedToken.setUnparsed(!regularTokens.contains(matchedType));
            return matchedToken;
        }
      }
   }

    private static int forward(CharSequence input, int pos, int amount) {
        for (int i = 0; i < amount; i++) {
            if (Character.isHighSurrogate(input.charAt(pos))) pos++;
            pos++;
            if (input instanceof TokenSource) {
              TokenSource ts = (TokenSource) input;
              while (ts.isIgnored(pos)) pos++;
            }
        }
        return pos;
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
    // to just after the ${settings.baseTokenClassName} passed in.
    void reset(${settings.baseTokenClassName} t, LexicalState state) {
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

  void reset(${settings.baseTokenClassName} t) {
      reset(t, null);
  }
    
 [#if lexerData.hasTokenActions]
  private ${settings.baseTokenClassName} tokenLexicalActions(${settings.baseTokenClassName} matchedToken, TokenType matchedType) {
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

    void cacheToken(${settings.baseTokenClassName} tok) {
[#if settings.tokenChaining]        
        if (tok.isInserted()) {
            ${settings.baseTokenClassName} next = tok.nextCachedToken();
            if (next != null) cacheToken(next);
            return;
        }
[/#if]        
        cacheTokenAt(tok, tok.getBeginOffset());
    }

[#if settings.tokenChaining]
    @Override
    protected void uncacheTokens(${BaseToken} lastToken) {
        super.uncacheTokens(lastToken);
        ((${settings.baseTokenClassName})lastToken).unsetAppendedToken();
    }
[/#if]    

 

  // Utility methods. Having them here makes it easier to handle things
  // more uniformly in other generation languages.

   private void setRegionIgnore(int start, int end) {
     setIgnoredRange(start, end);
   }

   private boolean atLineStart(${settings.baseTokenClassName} tok) {
      int offset = tok.getBeginOffset();
      while (offset > 0) {
        --offset;
        char c = charAt(offset);
        if (!Character.isWhitespace(c)) return false;
        if (c=='\n') break;
      }
      return true;
   }

   private String getLine(${settings.baseTokenClassName} tok) {
       int lineNum = tok.getBeginLine();
       return getText(getLineStartOffset(lineNum), getLineEndOffset(lineNum)+1);
   }

  
  // NFA related code follows.

  // The functional interface that represents 
  // the acceptance method of an NFA state
  static interface NfaFunction {
      TokenType apply(int ch, BitSet bs, EnumSet<TokenType> validTypes);
  }

 [#if NFA.multipleLexicalStates]
  // A lookup of the NFA function tables for the respective lexical states.
  private static final EnumMap<LexicalState,NfaFunction[]> functionTableMap = new EnumMap<>(LexicalState.class);
 [#else]
  [#-- We don't need the above lookup if there is only one lexical state.--]
   static private NfaFunction[] nfaFunctions;
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
