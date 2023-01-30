[#ftl strict_vars=true]
 
 /* Generated by: ${generated_by}. ${filename} */
 
 [#--
    This template generates the XXXLexer.java class.
    The details of generating the code for the NFA state machine
    are in the imported template NfaCode.java.ftl
 --]
 
[#if grammar.parserPackage?has_content]
    package ${grammar.parserPackage};
    import static ${grammar.parserPackage}.TokenType.*;
[/#if]

[#import "CommonUtils.java.ftl" as CU  ]

[#var lexerData=grammar.lexerData]
[#var multipleLexicalStates = lexerData.lexicalStates.size()>1]
[#var NFA_RANGE_THRESHOLD = 16]


[#var PRESERVE_LINE_ENDINGS=grammar.preserveLineEndings?string("true", "false")
      JAVA_UNICODE_ESCAPE= grammar.javaUnicodeEscape?string("true", "false")
      ENSURE_FINAL_EOL = grammar.ensureFinalEOL?string("true", "false")
      PRESERVE_TABS = grammar.preserveTabs?string("true", "false")
]      

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

[#list grammar.parserCodeImports as import]
   ${import}
[/#list]

import java.io.*;
import java.nio.charset.Charset;
import java.nio.Buffer;
import java.nio.ByteBuffer;
import java.nio.CharBuffer;
import java.nio.charset.CharsetDecoder;
import java.nio.charset.CoderResult;
import java.nio.charset.CharacterCodingException;
import static java.nio.charset.StandardCharsets.*;
import java.util.Arrays;
import java.util.BitSet;
import java.util.EnumMap;
import java.util.EnumSet;

public class ${grammar.lexerClassName} {
 [@CU.TokenTypeConstants/]
    private void backup(int amount) {
        if (amount > bufferPosition) throw new ArrayIndexOutOfBoundsException();
        this.bufferPosition -= amount;
    }

    static final int DEFAULT_TAB_SIZE = ${grammar.tabSize};

[#if grammar.preserveTabs]
    private int tabSize = DEFAULT_TAB_SIZE;

    /**
     * set the tab size used for location reporting
     */
    public void setTabSize(int tabSize) {this.tabSize = tabSize;}
[/#if]    



  final Token DUMMY_START_TOKEN = new Token();
// Just a dummy Token value that we put in the tokenLocationTable
// to indicate that this location in the file is ignored.
  static final private Token IGNORED = new Token(), SKIPPED = new Token();
  static {
      IGNORED.setUnparsed(true);
      SKIPPED.setUnparsed(true);
  }

   // Munged content, possibly replace unicode escapes, tabs, or CRLF with LF.
    private CharSequence content;
    // Typically a filename, I suppose.
    private String inputSource = "input";
    // A list of offsets of the beginning of lines
    private int[] lineOffsets;


    // The starting line and column, usually 1,1
    // that is used to report a file position 
    // in 1-based line/column terms
    private int startingLine, startingColumn;

    // The offset in the internal buffer to the very
    // next character that the readChar method returns
    private int bufferPosition;


// A BitSet that stores where the tokens are located.
// This is not strictly necessary, I suppose...
   private BitSet tokenOffsets;

//  A Bitset that stores the line numbers that
// contain either hard tabs or extended (beyond 0xFFFF) unicode
// characters.
   private BitSet needToCalculateColumns=new BitSet();

// Just a very simple, bloody minded approach, just store the
// Token objects in a table where the offsets are the code unit 
// positions in the content buffer. If the Token at a given offset is
// the dummy or marker type IGNORED, then the location is skipped via
// whatever preprocessor logic.    
    private Token[] tokenLocationTable;


 [#if grammar.lexerUsesParser]
  public ${grammar.parserClassName} parser;
 [/#if]
  // The following two BitSets are used to store 
  // the current active NFA states in the core tokenization loop
  private BitSet nextStates=new BitSet(${lexerData.maxNfaStates}), currentStates = new BitSet(${lexerData.maxNfaStates});

  EnumSet<TokenType> activeTokenTypes = EnumSet.allOf(TokenType.class);
  [#if grammar.deactivatedTokens?size>0 || grammar.extraTokens?size >0]
     {
       [#list grammar.deactivatedTokens as token]
          activeTokenTypes.remove(${token});
       [/#list]
       [#list grammar.extraTokenNames as token]
          regularTokens.add(${token});
       [/#list]
     }
  [/#if]

  // A lookup for lexical state transitions triggered by a certain token type
  private static EnumMap<TokenType, LexicalState> tokenTypeToLexicalStateMap = new EnumMap<>(TokenType.class);
  // Token types that are "regular" tokens that participate in parsing,
  // i.e. declared as TOKEN
  [@EnumSet "regularTokens" lexerData.regularTokens.tokenNames /]
  // Token types that do not participate in parsing
  // i.e. declared as UNPARSED (or SPECIAL_TOKEN)
  [@EnumSet "unparsedTokens" lexerData.unparsedTokens.tokenNames /]
  // Tokens that are skipped, i.e. SKIP 
  [@EnumSet "skippedTokens" lexerData.skippedTokens.tokenNames /]
  // Tokens that correspond to a MORE, i.e. that are pending 
  // additional input
  [@EnumSet "moreTokens" lexerData.moreTokens.tokenNames /]

  // The source of the raw characters that we are scanning  

  public String getInputSource() {
      return inputSource;
  }
  
  public void setInputSource(String inputSource) {
      this.inputSource = inputSource;
  }
   
  public ${grammar.lexerClassName}(CharSequence input) {
    this("input", input);
  }


     /**
      * @param inputSource just the naem of the input source (typically the filename)
      * that will be used in error messages and so on.
      * @param input the input
      */
     public ${grammar.lexerClassName}(String inputSource, CharSequence input) {
        this(inputSource, input, LexicalState.${lexerData.lexicalStates[0].name}, 1, 1);
     }

     /**
      * @param inputSource just the name of the input source (typically the filename) that 
      * will be used in error messages and so on.
      * @param input the input
      * @param line The line number at which we are starting for the purposes of location/error messages. In most 
      * normal usage, this is 1.
      * @param column number at which we are starting for the purposes of location/error messages. In most normal
      * usages this is 1.
      */
     public ${grammar.lexerClassName}(String inputSource, CharSequence input, LexicalState lexState, int startingLine, int startingColumn) {
        this.inputSource = inputSource;
        this.content = mungeContent(input, ${PRESERVE_TABS}, ${PRESERVE_LINE_ENDINGS}, ${JAVA_UNICODE_ESCAPE}, ${ENSURE_FINAL_EOL});
        this.inputSource = inputSource;
        createLineOffsetsTable();
        tokenLocationTable = new Token[content.length()+1];
        tokenOffsets = new BitSet(content.length() +1);
        this.startingLine = startingLine;
        this.startingColumn = startingColumn;
        switchTo(lexState);
     [#if grammar.cppContinuationLine]
        handleCContinuationLines();
     [/#if]
     }

    /**
     * @Deprecated Preferably use the constructor that takes a #java.nio.files.Path or simply a String,
     * depending on your use case
     */
    public ${grammar.lexerClassName}(Reader reader) {
       this("input", reader, LexicalState.${lexerData.lexicalStates[0].name}, 1, 1);
    }
    /**
     * @Deprecated Preferably use the constructor that takes a #java.nio.files.Path or simply a String,
     * depending on your use case
     */
    public ${grammar.lexerClassName}(String inputSource, Reader reader) {
       this(inputSource, reader, LexicalState.${lexerData.lexicalStates[0].name}, 1, 1);
    }

    /**
     * @Deprecated Preferably use the constructor that takes a #java.nio.files.Path or simply a String,
     * depending on your use case
     */
    public ${grammar.lexerClassName}(String inputSource, Reader reader, LexicalState lexState, int line, int column) {
        this(inputSource, readToEnd(reader), lexState, line, column);
        switchTo(lexState);
    }

    private Token getNextToken() {
      InvalidToken invalidToken = null;
      Token token = nextToken();
      while (token instanceof InvalidToken) {
          if (invalidToken == null) {
              invalidToken = (InvalidToken) token;
          } else {
              invalidToken.setEndOffset(token.getEndOffset());
          }
          token = nextToken();
      }
      if (invalidToken != null) cacheToken(invalidToken);
      cacheToken(token);
      if (invalidToken != null) {
        goTo(invalidToken.getEndOffset());
        return invalidToken;
      }
      return token;
    }

  /**
   * The public method for getting the next token.
   * If the tok parameter is null, it just tokenizes 
   * starting at the internal bufferPosition
   * Otherwise, it checks whether we have already cached
   * the token after this one. If not, it finally goes 
   * to the NFA machinery
   */ 
    public Token getNextToken(Token tok) {
       if(tok == null) {
           return getNextToken();
       }
       Token cachedToken = tok.nextCachedToken();
    // If the cached next token is not currently active, we
    // throw it away and go back to the XXXLexer
       if (cachedToken != null && !activeTokenTypes.contains(cachedToken.getType())) {
           reset(tok);
           cachedToken = null;
       }
       return cachedToken != null ? cachedToken : getNextToken(tok.getEndOffset());
    }

    /**
     * A lower level method to tokenize, that takes the absolute
     * offset into the content buffer as a parameter
     * @param offset where to start
     * @return the token that results from scanning from the given starting point 
     */
    public Token getNextToken(int offset) {
        goTo(offset);
        return getNextToken();
    }

// The main method to invoke the NFA machinery
 private final Token nextToken() {
      Token matchedToken = null;
      boolean inMore = false;
      int tokenBeginOffset = this.bufferPosition, firstChar =0;
      // The core tokenization loop
      while (matchedToken == null) {
        int curChar, codeUnitsRead=0, matchedPos=0;
        TokenType matchedType = null;
        boolean reachedEnd = false;
        if (inMore) {
            curChar = readChar();
            if (curChar == -1) reachedEnd = true;
        }
        else {
            tokenBeginOffset = this.bufferPosition;
            firstChar = curChar = readChar();
            if (curChar == -1) {
              matchedType = EOF;
              reachedEnd = true;
            }
        } 
      [#if multipleLexicalStates]
       // Get the NFA function table current lexical state
       // There is some possibility that there was a lexical state change
       // since the last iteration of this loop!
        NfaFunction[] nfaFunctions = functionTableMap.get(lexicalState);
      [/#if]
        // the core NFA loop
        if (!reachedEnd) do {
            // Holder for the new type (if any) matched on this iteration
            TokenType newType = null;
            if (codeUnitsRead > 0) {
                // What was nextStates on the last iteration 
                // is now the currentStates!
                BitSet temp = currentStates;
                currentStates = nextStates;
                nextStates = temp;
                int retval = readChar();
                if (retval >=0) {
                    curChar = retval;
                }
                else {
                    reachedEnd = true;
                    break;
                }
            }
            nextStates.clear();
            int nextActive = codeUnitsRead == 0 ? 0 : currentStates.nextSetBit(0);
            do {
                TokenType returnedType = nfaFunctions[nextActive].apply(curChar, nextStates, activeTokenTypes);
                if (returnedType != null && (newType == null || returnedType.ordinal() < newType.ordinal())) {
                    newType = returnedType;
                }
                nextActive = codeUnitsRead == 0 ? -1 : currentStates.nextSetBit(nextActive+1);
            } while (nextActive != -1);
            ++codeUnitsRead;
            if (curChar>0xFFFF) ++codeUnitsRead;
            if (newType != null) {
                matchedType = newType;
                inMore = moreTokens.contains(matchedType);
                matchedPos= codeUnitsRead;
            }
        } while (!nextStates.isEmpty());
        if (matchedType == null) {
            bufferPosition = tokenBeginOffset+1;
            if (firstChar>0xFFFF) ++bufferPosition;
            return new InvalidToken(this, tokenBeginOffset, bufferPosition);
        } 
        bufferPosition -= (codeUnitsRead - matchedPos);
        if (skippedTokens.contains(matchedType)) {
            for (int i=tokenBeginOffset; i< bufferPosition; i++) {
                if (tokenLocationTable[i] != IGNORED) tokenLocationTable[i] = SKIPPED;
            }
        }
        else if (regularTokens.contains(matchedType) || unparsedTokens.contains(matchedType)) {
            matchedToken = Token.newToken(matchedType, 
                                        this, 
                                        tokenBeginOffset,
                                        bufferPosition);
            matchedToken.setUnparsed(!regularTokens.contains(matchedType));
        }
     [#if lexerData.hasLexicalStateTransitions]
        doLexicalStateSwitch(matchedType);
     [/#if]
     [#if lexerData.hasTokenActions]
        matchedToken = tokenLexicalActions(matchedToken, matchedType);
     [/#if]
      }
 [#list grammar.lexerTokenHooks as tokenHookMethodName]
    [#if tokenHookMethodName = "CommonTokenAction"]
           ${tokenHookMethodName}(matchedToken);
    [#else]
            matchedToken = ${tokenHookMethodName}(matchedToken);
    [/#if]
 [/#list]
      return matchedToken;
   }

   LexicalState lexicalState = LexicalState.values()[0];

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
    // to just after the Token passed in.
    void reset(Token t, LexicalState state) {
[#list grammar.resetTokenHooks as resetTokenHookMethodName]
      ${resetTokenHookMethodName}(t);
[/#list]
      goTo(t.getEndOffset());
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

  void reset(Token t) {
      reset(t, null);
  }
    
 [#if lexerData.hasTokenActions]
  private Token tokenLexicalActions(Token matchedToken, TokenType matchedType) {
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

    // But there is no goto in Java!!!
    private void goTo(int offset) {
        while (offset<content.length() && tokenLocationTable[offset] == IGNORED) {
            ++offset;
        }
        this.bufferPosition = offset;
    }

    /**
     * @return the line length in code _units_
     */ 
    private int getLineLength(int lineNumber) {
        int startOffset = getLineStartOffset(lineNumber);
        int endOffset = getLineEndOffset(lineNumber);
        return 1+endOffset - startOffset;
    }

    /**
     * The offset of the start of the given line. This is in code units
     */
    private int getLineStartOffset(int lineNumber) {
        int realLineNumber = lineNumber - startingLine;
        if (realLineNumber <=0) {
            return 0;
        }
        if (realLineNumber >= lineOffsets.length) {
            return content.length();
        }
        return lineOffsets[realLineNumber];
    }

    /**
     * The offset of the end of the given line. This is in code units.
     */
    private int getLineEndOffset(int lineNumber) {
        int realLineNumber = lineNumber - startingLine;
        if (realLineNumber <0) {
            return 0;
        }
        if (realLineNumber >= lineOffsets.length) {
            return content.length();
        }
        if (realLineNumber == lineOffsets.length -1) {
            return content.length() -1;
        }
        return lineOffsets[realLineNumber+1] -1;
    }

    private int readChar() {
        while (tokenLocationTable[bufferPosition] == IGNORED && bufferPosition < content.length()) {
            ++bufferPosition;
        }
        if (bufferPosition >= content.length()) {
            return -1;
        }
        char ch = content.charAt(bufferPosition++);
        if (Character.isHighSurrogate(ch) && bufferPosition < content.length()) {
            char nextChar = content.charAt(bufferPosition);
            if (Character.isLowSurrogate(nextChar)) {
                ++bufferPosition;
                return Character.toCodePoint(ch, nextChar);
            }
        }
        return ch;
    }

    /**
     * This is used in conjunction with having a preprocessor.
     * We set which lines are actually parsed lines and the 
     * unset ones are ignored. 
     * @param parsedLines a #java.util.BitSet that holds which lines
     * are parsed (i.e. not ignored)
     */
    private void setParsedLines(BitSet parsedLines, boolean reversed) {
        for (int i=0; i < lineOffsets.length; i++) {
            boolean turnOffLine = !parsedLines.get(i+1);
            if (reversed) turnOffLine = !turnOffLine;
            if (turnOffLine) {
                int lineOffset = lineOffsets[i];
                int nextLineOffset = i < lineOffsets.length -1 ? lineOffsets[i+1] : content.length();
                for (int offset = lineOffset; offset < nextLineOffset; offset++) {
                    tokenLocationTable[offset] = IGNORED;
                }
            }
        }
    }

    /**
     * This is used in conjunction with having a preprocessor.
     * We set which lines are actually parsed lines and the 
     * unset ones are ignored. 
     * @param parsedLines a #java.util.BitSet that holds which lines
     * are parsed (i.e. not ignored)
     */
    public void setParsedLines(BitSet parsedLines) {setParsedLines(parsedLines,false);}

    public void setUnparsedLines(BitSet unparsedLines) {setParsedLines(unparsedLines,true);}

    /**
     * @return the line number from the absolute offset passed in as a parameter
     */
    public int getLineFromOffset(int pos) {
        if (pos >= content.length()) {
            if (content.charAt(content.length()-1) == '\n') {
                return startingLine + lineOffsets.length;
            }
            return startingLine + lineOffsets.length-1;
        }
        int bsearchResult = Arrays.binarySearch(lineOffsets, pos);
        if (bsearchResult>=0) {
        [#-- REVISIT --]
            return Math.max(1,startingLine + bsearchResult);
        }
        [#-- REVISIT --]
        return Math.max(1,startingLine-(bsearchResult+2));
    }

    /**
     * @return the column (1-based and in code points)
     * from the absolute offset passed in as a parameter
     */

    public int getCodePointColumnFromOffset(int pos) {
        if (pos >= content.length()) return 1;
        if (pos == 0) return startingColumn;
        final int line = getLineFromOffset(pos)-startingLine;
        final int lineStart = lineOffsets[line];
        int startColumnAdjustment = line > 0 ? 1 : startingColumn;
        int unadjustedColumn = pos - lineStart + startColumnAdjustment;
        if (!needToCalculateColumns.get(line)) {
            return unadjustedColumn;
        }
        if (Character.isLowSurrogate(content.charAt(pos))) --pos;
        int result = startColumnAdjustment;
        for (int i = lineStart; i < pos; i++) {
            char ch = content.charAt(i);
            if (ch == '\t') {
             [#if grammar.preserveTabs]
                result += tabSize - (result - 1) % tabSize;
             [#else]
                result += DEFAULT_TAB_SIZE - (result - 1) % DEFAULT_TAB_SIZE;
             [/#if]
            } 
            else if (Character.isHighSurrogate(ch)) {
                ++result;
                ++i;
            } 
            else {
                ++result;
            }
        }
        return result;
    }
    
    /**
     * @return the text between startOffset (inclusive)
     * and endOffset(exclusive)
     */
    public String getText(int startOffset, int endOffset) {
        StringBuilder buf = new StringBuilder();
        for (int offset = startOffset; offset < endOffset; offset++) {
            if (tokenLocationTable[offset] != IGNORED) {
                buf.append(content.charAt(offset));
            }
        }
        return buf.toString();
    }

    void cacheToken(Token tok) {
[#if !grammar.minimalToken]        
        if (tok.isInserted()) {
            Token next = tok.nextCachedToken();
            if (next != null) cacheToken(next);
            return;
        }
[/#if]        
	    int offset = tok.getBeginOffset();
        if (tokenLocationTable[offset] != IGNORED) {
	        tokenOffsets.set(offset);
	        tokenLocationTable[offset] = tok;
        }
    }

    void uncacheTokens(Token lastToken) {
        int endOffset = lastToken.getEndOffset();
        if (endOffset < tokenOffsets.length()) {
            tokenOffsets.clear(lastToken.getEndOffset(), tokenOffsets.length());
        }
      [#if !grammar.minimalToken]
        lastToken.unsetAppendedToken();
      [/#if]
    }

    Token nextCachedToken(int offset) {
        int nextOffset = tokenOffsets.nextSetBit(offset);
	    return nextOffset != -1 ? tokenLocationTable[nextOffset] : null;
    } 

    Token previousCachedToken(int offset) {
        int prevOffset = tokenOffsets.previousSetBit(offset-1);
        return prevOffset == -1 ? null : tokenLocationTable[prevOffset];
    }

    private void createLineOffsetsTable() {
        if (content.length() == 0) {
            this.lineOffsets = new int[0];
            return;
        }
        int lineCount = 0;
        int length = content.length();
        for (int i = 0; i < length; i++) {
            char ch = content.charAt(i);
            if (ch == '\t' || Character.isHighSurrogate(ch)) {
                needToCalculateColumns.set(lineCount);
            }
            if (ch == '\n') {
                lineCount++;
            }
        }
        if (content.charAt(length - 1) != '\n') {
            lineCount++;
        }
        int[] lineOffsets = new int[lineCount];
        lineOffsets[0] = 0;
        int index = 1;
        for (int i = 0; i < length; i++) {
            char ch = content.charAt(i);
            if (ch == '\n') {
                if (i + 1 == length)
                    break;
                lineOffsets[index++] = i + 1;
            }
        }
        this.lineOffsets = lineOffsets;
    }
 
// Icky method to handle annoying stuff. Might make this public later if it is
// needed elsewhere
  private static String mungeContent(CharSequence content, boolean preserveTabs, boolean preserveLines,
        boolean javaUnicodeEscape, boolean ensureFinalEndline) {
    if (preserveTabs && preserveLines && !javaUnicodeEscape) {
        if (ensureFinalEndline) {
            if (content.length() == 0) {
                content = "\n";
            } else {
                int lastChar = content.charAt(content.length()-1);
                if (lastChar != '\n' && lastChar != '\r') {
                    if (content instanceof StringBuilder) {
                        ((StringBuilder) content).append((char) '\n');
                    } else {
                        StringBuilder buf = new StringBuilder(content);
                        buf.append('\n');
                        content = buf.toString();
                    }
                }
            }
        }
        return content.toString();
    }
    StringBuilder buf = new StringBuilder();
    // This is just to handle tabs to spaces. If you don't have that setting set, it
    // is really unused.
    int col = 0;
    int index = 0, contentLength = content.length();
    while (index < contentLength) {
        char ch = content.charAt(index++);
        if (ch == '\n') {
            buf.append(ch);
            col = 0;
        }
        else if (javaUnicodeEscape && ch == '\\' && index < contentLength && content.charAt(index)=='u') {
            int numPrecedingSlashes = 0;
            for (int i = index-1; i>=0; i--) {
                if (content.charAt(i) == '\\') 
                    numPrecedingSlashes++;
                else break;
            }
            if (numPrecedingSlashes % 2 == 0) {
                buf.append('\\');
                ++col;
                continue;
            }
            int numConsecutiveUs = 0;
            for (int i = index; i < contentLength; i++) {
                if (content.charAt(i) == 'u') numConsecutiveUs++;
                else break;
            }
            String fourHexDigits = content.subSequence(index+numConsecutiveUs, index+numConsecutiveUs+4).toString();
            buf.append((char) Integer.parseInt(fourHexDigits, 16));
            index+=(numConsecutiveUs +4);
            ++col;
        }
        else if (!preserveLines && ch == '\r') {
            buf.append('\n');
            col = 0;
            if (index < contentLength && content.charAt(index) == '\n') {
                ++index;
            }
        } else if (ch == '\t' && !preserveTabs) {
            int spacesToAdd = DEFAULT_TAB_SIZE - col % DEFAULT_TAB_SIZE;
            for (int i = 0; i < spacesToAdd; i++) {
                buf.append(' ');
                col++;
            }
        } else {
            buf.append(ch);
            if (!Character.isLowSurrogate(ch)) col++;
        }
    }
    if (ensureFinalEndline) {
        if (buf.length() ==0) {
            return "\n";
        }
        char lastChar = buf.charAt(buf.length()-1);
        if (lastChar != '\n' && lastChar != '\r') buf.append('\n');
    }
    return buf.toString();
  }

  private void handleCContinuationLines() {
      String input = content.toString();
      for (int offset = input.indexOf('\\'); offset >=0; offset = input.indexOf('\\', offset+1)) {
          int nlIndex = input.indexOf('\n', offset);
          if (nlIndex < 0) break;
          if (input.substring(offset+1, nlIndex).trim().isEmpty()) {
              for (int i=offset; i<=nlIndex; i++) tokenLocationTable[i] = IGNORED;
          } 
      }
  }

  // Utility methods. Having them here makes it easier to handle things
  // more uniformly in other generation languages.

   private void setRegionIgnore(int start, int end) {
     for (int i = start; i< end; i++) {
       tokenLocationTable[i] = IGNORED;
     }
     tokenOffsets.clear(start, end);
   }

   private boolean atLineStart(Token tok) {
      int offset = tok.getBeginOffset();
      while (offset > 0) {
        --offset;
        char c = this.content.charAt(offset);
        if (!Character.isWhitespace(c)) return false;
        if (c=='\n') break;
      }
      return true;
   }

   private String getLine(Token tok) {
       int lineNum = tok.getBeginLine();
       return getText(getLineStartOffset(lineNum), getLineEndOffset(lineNum)+1);
   }

   private void setLineSkipped(Token tok) {
       int lineNum = tok.getBeginLine();
       int start = getLineStartOffset(lineNum);
       int end = getLineStartOffset(lineNum+1);
       setRegionIgnore(start, end);
       tok.setBeginOffset(start);
       tok.setEndOffset(end);
   }

  static String displayChar(int ch) {
    if (ch == '\'') return "\'\\'\'";
    if (ch == '\\') return "\'\\\\\'";
    if (ch == '\t') return "\'\\t\'";
    if (ch == '\r') return "\'\\r\'";
    if (ch == '\n') return "\'\\n\'";
    if (ch == '\f') return "\'\\f\'";
    if (ch == ' ') return "\' \'";
    if (ch < 128 && !Character.isWhitespace(ch) && !Character.isISOControl(ch)) return "\'" + (char) ch + "\'";
    if (ch < 10) return "" + ch;
    return "0x" + Integer.toHexString(ch);
  }

  static String addEscapes(String str) {
      StringBuilder retval = new StringBuilder();
      for (int ch : str.codePoints().toArray()) {
        switch (ch) {
           case '\b':
              retval.append("\\b");
              continue;
           case '\t':
              retval.append("\\t");
              continue;
           case '\n':
              retval.append("\\n");
              continue;
           case '\f':
              retval.append("\\f");
              continue;
           case '\r':
              retval.append("\\r");
              continue;
           case '\"':
              retval.append("\\\"");
              continue;
           case '\'':
              retval.append("\\\'");
              continue;
           case '\\':
              retval.append("\\\\");
              continue;
           default:
              if (Character.isISOControl(ch)) {
                 String s = "0000" + java.lang.Integer.toString(ch, 16);
                 retval.append("\\u" + s.substring(s.length() - 4, s.length()));
              } else {
                 retval.appendCodePoint(ch);
              }
              continue;
        }
      }
      return retval.toString();
  }

  // Annoying kludge really...
  static String readToEnd(Reader reader) {
    try {
        return readFully(reader);
    } catch (IOException ioe) {
        throw new RuntimeException(ioe);
    }
  }

  static final int BUF_SIZE = 0x10000;

  static String readFully(Reader reader) throws IOException {
    char[] block = new char[BUF_SIZE];
    int charsRead = reader.read(block);
    if (charsRead < 0) {
        throw new IOException("No input");
    } else if (charsRead < BUF_SIZE) {
        char[] result = new char[charsRead];
        System.arraycopy(block, 0, result, 0, charsRead);
        reader.close();
        return new String(block, 0, charsRead);
    }
    StringBuilder buf = new StringBuilder();
    buf.append(block);
    do {
        charsRead = reader.read(block);
        if (charsRead > 0) {
            buf.append(block, 0, charsRead);
        }
    } while (charsRead == BUF_SIZE);
    reader.close();
    return buf.toString();
  }

  /**
    * @param bytes the raw byte array 
    * @param charset The encoding to use to decode the bytes. If this is null, we check for the
    * initial byte order mark (used by Microsoft a lot seemingly)
    * See: https://docs.microsoft.com/es-es/globalization/encoding/byte-order-markc
    * @return A String taking into account the encoding passed in or in the byte order mark (if it was present). 
    * And if no encoding was passed in and no byte-order mark was present, we assume the raw input
    * is in UTF-8.
    */
  static public String stringFromBytes(byte[] bytes, Charset charset) throws CharacterCodingException {
    int arrayLength = bytes.length;
    if (charset == null) {
      int firstByte = arrayLength>0 ? Byte.toUnsignedInt(bytes[0]) : 1;
      int secondByte = arrayLength>1 ? Byte.toUnsignedInt(bytes[1]) : 1;
      int thirdByte = arrayLength >2 ? Byte.toUnsignedInt(bytes[2]) : 1;
      int fourthByte = arrayLength > 3 ? Byte.toUnsignedInt(bytes[3]) : 1;
      if (firstByte == 0xEF && secondByte == 0xBB && thirdByte == 0xBF) {
         return new String(bytes, 3, bytes.length-3, Charset.forName("UTF-8"));
      }
      if (firstByte == 0 && secondByte==0 && thirdByte == 0xFE && fourthByte == 0xFF) {
         return new String(bytes, 4, bytes.length-4, Charset.forName("UTF-32BE"));
      }
      if (firstByte == 0xFF && secondByte == 0xFE && thirdByte == 0 && fourthByte == 0) {
         return new String(bytes, 4, bytes.length-4, Charset.forName("UTF-32LE"));
      }
      if (firstByte == 0xFE && secondByte == 0xFF) {
         return new String(bytes, 2, bytes.length-2, Charset.forName("UTF-16BE"));
      }
      if (firstByte == 0xFF && secondByte == 0xFE) {
         return new String(bytes, 2, bytes.length-2, Charset.forName("UTF-16LE"));
      }
      charset = UTF_8;
    }
    CharsetDecoder decoder = charset.newDecoder();
    ByteBuffer b = ByteBuffer.wrap(bytes);
    CharBuffer c = CharBuffer.allocate(bytes.length);
    while (true) {
        CoderResult r = decoder.decode(b, c, false);
        if (!r.isError()) {
            break;
        }
        if (!r.isMalformed()) {
            r.throwException();
        }
        int n = r.length();
        b.position(b.position() + n);
        for (int i = 0; i < n; i++) {
            c.put((char) 0xFFFD);
        }
    }
    ((Buffer) c).limit(c.position());
    ((Buffer) c).rewind();
    return c.toString();
    // return new String(bytes, charset);
  }

  static public String stringFromBytes(byte[] bytes) throws CharacterCodingException {
     return stringFromBytes(bytes, null);
  }

  // NFA related code follows.


  // The functional interface that represents 
  // the acceptance method of an NFA state
  static interface NfaFunction {
    TokenType apply(int ch, BitSet bs, EnumSet<TokenType> validTypes);
  }

 [#if multipleLexicalStates]
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

  // Just use the canned binary search to check whether the char
  // is in one of the intervals
  private static final boolean checkIntervals(int[] ranges, int ch) {
    int result = Arrays.binarySearch(ranges, ch);
    return result >=0 || result%2 == 0;
  }

 [#list grammar.lexerData.lexicalStates as lexicalState]
 /**
  * Holder class for NFA code related to ${lexicalState.name} lexical state
  */
  private static class ${lexicalState.name} {
   [@GenerateStateCode lexicalState/]
  }
 [/#list]  
}

[#--
  Generate all the NFA transition code
  for the given lexical state
--]
[#macro GenerateStateCode lexicalState]
  [#list lexicalState.canonicalSets as state]
     [@GenerateNfaMethod state/]
  [/#list]

  [#list lexicalState.allNfaStates as state]
    [#if state.moveRanges.size() >= NFA_RANGE_THRESHOLD]
      [@GenerateMoveArray state/]
    [/#if]
  [/#list]

  static private void NFA_FUNCTIONS_init() {
    [#if multipleLexicalStates]
      NfaFunction[] functions = new NfaFunction[]
    [#else]
      nfaFunctions = new NfaFunction[]
    [/#if] 
    {
    [#list lexicalState.canonicalSets as state]
      ${lexicalState.name}::${state.methodName}
      [#if state_has_next],[/#if]
    [/#list]
    };
    [#if multipleLexicalStates]
      functionTableMap.put(LexicalState.${lexicalState.name}, functions);
    [/#if]
  }
[/#macro]

[#--
   Generate the array representing the characters
   that this NfaState "accepts".
   This corresponds to the moveRanges field in 
   org.congocc.core.NfaState
--]
[#macro GenerateMoveArray nfaState]
  [#var moveRanges = nfaState.moveRanges]
  [#var arrayName = nfaState.movesArrayName]
    static private int[] ${arrayName} = ${arrayName}_init();

    static private int[] ${arrayName}_init() {
        return new int[]
        {
        [#list nfaState.moveRanges as char]
          ${grammar.utils.displayChar(char)}
          [#if char_has_next],[/#if]
        [/#list]
        };
    }
[/#macro] 

[#--
   Generate the method that represents the transitions
   that correspond to an instanceof org.congocc.core.CompositeStateSet
--]
[#macro GenerateNfaMethod nfaState]  
    static private TokenType ${nfaState.methodName}(int ch, BitSet nextStates, EnumSet<TokenType> validTypes) {
      TokenType type = null;
    [#var states = nfaState.orderedStates, lastBlockStartIndex=0]
    [#list states as state]
      [#if state_index ==0 || !state.moveRanges.equals(states[state_index-1].moveRanges)]
          [#-- In this case we need a new if or possibly else if --]
         [#if state_index == 0 || state.overlaps(states.subList(lastBlockStartIndex, state_index))]
           [#-- If there is overlap between this state and any of the states
                 handled since the last lone if, we start a new if-else 
                 If not, we continue in the same if-else block as before. --]
           [#set lastBlockStartIndex = state_index]
               if
         [#else]
               else if
         [/#if]    
           ([@NfaStateCondition state /]) {
      [/#if]
      [#if state.nextStateIndex >= 0]
         nextStates.set(${state.nextStateIndex});
      [/#if]
      [#if !state_has_next || !state.moveRanges.equals(states[state_index+1].moveRanges)]
        [#-- We've reached the end of the block. --]
          [#var type = state.nextStateType]
          [#if type??]
            if (validTypes.contains(${type.label}))
              type = ${type.label};
          [/#if]
        }
      [/#if]
    [/#list]
      return type;
    }
[/#macro]

[#--
Generate the condition part of the NFA state transition
If the size of the moveRanges vector is greater than NFA_RANGE_THRESHOLD
it uses the canned binary search routine. For the smaller moveRanges
it just generates the inline conditional expression
--]
[#macro NfaStateCondition nfaState]
    [#if nfaState.moveRanges?size < NFA_RANGE_THRESHOLD]
      [@RangesCondition nfaState.moveRanges /]
    [#elseif nfaState.hasAsciiMoves && nfaState.hasNonAsciiMoves]
      ([@RangesCondition nfaState.asciiMoveRanges/])
      || (ch >=128 && checkIntervals(${nfaState.movesArrayName}, ch))
    [#else]
      checkIntervals(${nfaState.movesArrayName}, ch)
    [/#if]
[/#macro]

[#-- 
This is a recursive macro that generates the code corresponding
to the accepting condition for an NFA state. It is used
if NFA state's moveRanges array is smaller than NFA_RANGE_THRESHOLD
(which is set to 16 for now)
--]
[#macro RangesCondition moveRanges]
    [#var left = moveRanges[0], right = moveRanges[1]]
    [#var displayLeft = grammar.utils.displayChar(left), displayRight = grammar.utils.displayChar(right)]
    [#var singleChar = left == right]
    [#if moveRanges?size==2]
       [#if singleChar]
          ch == ${displayLeft}
       [#elseif left +1 == right]
          ch == ${displayLeft} || ch == ${displayRight}
       [#else]
          ch >= ${displayLeft} 
          [#if right < 1114111]
             && ch <= ${displayRight}
          [/#if]
       [/#if]
    [#else]
       ([@RangesCondition moveRanges[0..1]/])||([@RangesCondition moveRanges[2..moveRanges?size-1]/])
    [/#if]
[/#macro]

