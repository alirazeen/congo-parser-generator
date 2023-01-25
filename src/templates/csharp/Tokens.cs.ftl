[#ftl strict_vars=true]
[#--
  Copyright (C) 2008-2020 Jonathan Revusky, revusky@congocc.com
  Copyright (C) 2021-2022 Vinay Sajip, vinay_sajip@yahoo.co.uk
  All rights reserved.

  Redistribution and use in source and binary forms, with or without
  modification, are permitted provided that the following conditions are met:

      * Redistributions of source code must retain the above copyright
        notices, this list of conditions and the following disclaimer.
      * Redistributions in binary form must reproduce the above copyright
        notice, this list of conditions and the following disclaimer in
        the documentation and/or other materials provided with the
        distribution.
      * None of the names Jonathan Revusky, Vinay Sajip, Sun
        Microsystems, Inc. nor the names of any contributors may be
        used to endorse or promote products derived from this software
        without specific prior written permission.

  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
  ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
  LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
  THE POSSIBILITY OF SUCH DAMAGE.
--]
// Generated by ${generated_by}. Do not edit.
// ReSharper disable InconsistentNaming
[#var csPackage = grammar.utils.getPreprocessorSymbol('cs.package', grammar.parserPackage) ]
namespace ${csPackage} {
    using System;
    using System.Collections.Generic;
    using System.Diagnostics;

    public enum TokenType {
 [#list grammar.lexerData.regularExpressions as regexp]
        ${regexp.label},
 [/#list]
 [#list grammar.extraTokenNames as t]
        ${t},
 [/#list]
        INVALID
    }

    public enum LexicalState {
[#list grammar.lexerData.lexicalStates as lexicalState]
     ${lexicalState.name}[#if lexicalState_has_next],[/#if]
[/#list]
    }

    public interface Node {
        void Open() {}
        void Close() {}
        Lexer TokenSource { get; set; }
        Node Parent { get; set; }
        int ChildCount { get; }
        Node GetChild(int i);
        void SetChild(int i, Node n);
        void AddChild(int i, Node n);
        void AddChild(Node n);
        void RemoveChild(int i);
        void ClearChildren();

        // default implementations

        string InputSource { get {
            Lexer ts = TokenSource;

            return (ts == null) ? "input" : ts.InputSource;
        } }

        int BeginOffset { get; set; }
        int EndOffset { get; set; }

        int BeginLine {
            get {
                return (TokenSource == null) ? 0 : TokenSource.GetLineFromOffset(BeginOffset);
            }
        }

        int EndLine {
            get {
                return (TokenSource == null) ? 0 : TokenSource.GetLineFromOffset(EndOffset - 1);
            }
        }

        int BeginColumn {
            get {
                return (TokenSource == null) ? 0 : TokenSource.GetCodePointColumnFromOffset(BeginOffset);
            }
        }

        int EndColumn {
            get {
                return (TokenSource == null) ? 0 : TokenSource.GetCodePointColumnFromOffset(EndOffset - 1);
            }
        }

        bool IsUnparsed { get => false; }

        bool HasChildNodes { get { return ChildCount > 0; } }

        int IndexOf(Node child) {
            for (int i = 0; i < ChildCount; i++) {
                if (child == GetChild(i)) {
                    return i;
                }
            }
            return -1;
        }

        Node FirstChild {
            get {
                return (ChildCount > 0) ? GetChild(0) : null;
            }
        }

        Node LastChild {
            get {
                int n = ChildCount;
                return (n > 0) ? GetChild(n - 1) : null;
            }
        }

        Node Root {
            get {
                Node n = this;
                while(n.Parent != null) {
                    n = n.Parent;
                }
                return n;
            }
        }

        ListAdapter<Node> Children {
            get {
                ListAdapter<Node> result = new ListAdapter<Node>();

                for (int i = 0; i < ChildCount; i++) {
                    result.Add(GetChild(i));
                }
                return result;
            }
        }

        bool RemoveChild(Node n) {
            int i = IndexOf(n);
            if (i < 0) {
                return false;
            }
            RemoveChild(i);
            return true;
        }

        bool ReplaceChld(Node current, Node replacement) {
            int i = IndexOf(current);
            if (i < 0) {
                return false;
            }
            SetChild(i, replacement);
            return true;
        }

        bool PrependChild(Node where, Node inserted) {
            int i = IndexOf(where);
            if (i < 0) {
                return false;
            }
            AddChild(i, inserted);
            return true;
        }

        bool AppendChild(Node where, Node inserted) {
            int i = IndexOf(where);
            if (i < 0) {
                return false;
            }
            AddChild(i + 1, inserted);
            return true;
        }

        T FirstChildOfType<T>(System.Type t) where T : Node {
            var result = default(T);

            for (int i = 0; i < ChildCount; i++) {
                Node child = GetChild(i);
                if (t.IsInstanceOfType(child)) {
                    result = (T) child;
                    break;
                }
            }
            return result;
        }

        T FirstChildOfType<T>(System.Type t, Predicate<T> pred) where T : Node {
            var result = default(T);

            for (int i = 0; i < ChildCount; i++) {
                Node child = GetChild(i);
                if (t.IsInstanceOfType(child)) {
                    T c = (T) child;
                    if (pred(c)) {
                        result = c;
                        break;
                    }
                }
            }
            return result;
        }

        void CopyLocationInfo(Node start, Node end = null) {
            TokenSource = start.TokenSource;
            BeginOffset = start.BeginOffset;
            EndOffset = start.EndOffset;
            if (end != null) {
                if (TokenSource == null) {
                    TokenSource = end.TokenSource;
                }
                EndOffset = end.EndOffset;
            }
        }

        void Replace(Node toBeReplaced) {
            CopyLocationInfo(toBeReplaced);
            Node parent = toBeReplaced.Parent;
            if (parent != null) {
                int index = parent.IndexOf(toBeReplaced);
                parent.SetChild(index, this);
            }
        }

[#if grammar.tokensAreNodes]
        Token FirstDescendantOfType(TokenType tt) {
            for (int i = 0; i < ChildCount; i++) {
                Node child = GetChild(i);
                Token tok;

                if (child is Token) {
                    tok = (Token) child;
                    if (tt == tok.Type) {
                        return tok;
                    }
                }
                else {
                    tok = child.FirstDescendantOfType(tt);
                    if (tok != null) {
                        return tok;
                    }
                }
            }
            return null;
        }

        Token FirstChildOfType(TokenType tt) {
            for (int i = 0; i < ChildCount; i++) {
                Node child = GetChild(i);
                if (child is Token) {
                    Token tok = (Token) child;
                    if (tt == tok.Type) {
                        return tok;
                    }
                }
            }
            return null;
        }

        ListAdapter<T> ChildrenOfType<T>(System.Type t) where T : Node {
            var result = new ListAdapter<T>();

            for (int i = 0; i < ChildCount; i++) {
                Node child = GetChild(i);
                if (t.IsInstanceOfType(child)) {
                    result.Add((T) child);
                }
            }
            return result;
        }

        ListAdapter<T> DescendantsOfType<T>(System.Type t) where T : Node {
            var result = new ListAdapter<T>();

            for (int i = 0; i < ChildCount; i++) {
                Node child = GetChild(i);
                if (t.IsInstanceOfType(child)) {
                    result.Add((T) child);
                }
                result.AddRange(child.DescendantsOfType<T>(t));
            }
            return result;
        }

        ListAdapter<T> Descendants<T>(System.Type t, Predicate<T> predicate) where T : Token {
            var result = new ListAdapter<T>();

            for (int i = 0; i < ChildCount; i++) {
                Node child = GetChild(i);
                if (t.IsInstanceOfType(child)) {
                    T c = (T) child;
                    if ((predicate == null) || predicate(c)) {
                        result.Add(c);
                    }
                }
                result.AddRange(child.Descendants<T>(t, predicate));
            }
            return result;
        }

        internal ListAdapter<Token> GetRealTokens() {
            return Descendants<Token>(typeof(Token), t => !t.IsUnparsed);
        }

        //
        // Return the very first token that is part of this node.
        // It may be an unparsed (i.e. special) token.
        //
        public Token FirstToken {
            get {
                var first = FirstChild;
                if (first == null) {
                    return null;
                }
                if (first is Token) {
                    var tok = first as Token;
                    while ((tok.PreviousCachedToken != null) && tok.PreviousCachedToken.IsUnparsed) {
                        tok = tok.PreviousCachedToken;
                    }
                    return tok;
                }
                return first.FirstToken;
            }
        }

        public Token LastToken {
            get {
                var last = LastChild;
                if (last == null) {
                    return null;
                }
                if (last is Token) {
                    return last as Token;
                }
                return last.LastToken;
            }
        }

[/#if]
    }

    public class BaseNode : Node {
        public Node Parent { get; set; }
        public int BeginOffset { get; set; }
        public int EndOffset { get; set; }

        // TODO us default implementations in interface
        public int BeginLine {
            get {
                return (TokenSource == null) ? 0 : TokenSource.GetLineFromOffset(BeginOffset);
            }
        }

        public int EndLine {
            get {
                return (TokenSource == null) ? 0 : TokenSource.GetLineFromOffset(EndOffset - 1);
            }
        }

        public int BeginColumn {
            get {
                return (TokenSource == null) ? 0 : TokenSource.GetCodePointColumnFromOffset(BeginOffset);
            }
        }

        public int EndColumn {
            get {
                return (TokenSource == null) ? 0 : TokenSource.GetCodePointColumnFromOffset(EndOffset - 1);
            }
        }
        
        public T FirstChildOfType<T>(System.Type t) where T : Node {
            var result = default(T);

            for (int i = 0; i < ChildCount; i++) {
                Node child = GetChild(i);
                if (t.IsInstanceOfType(child)) {
                    result = (T) child;
                    break;
                }
            }
            return result;
        }

        public ListAdapter<T> ChildrenOfType<T>(System.Type t) where T : Node {
            var result = new ListAdapter<T>();

            for (int i = 0; i < ChildCount; i++) {
                Node child = GetChild(i);
                if (t.IsInstanceOfType(child)) {
                    result.Add((T) child);
                }
            }
            return result;
        }

        internal Lexer tokenSource;
        protected ListAdapter<Node> children { get; private set; } = new ListAdapter<Node>();

        public Lexer TokenSource {
            get {
                if (tokenSource == null) {
                    foreach (var child in children) {
                        tokenSource = child.TokenSource;
                        if (tokenSource != null) {
                            break;
                        }
                    }
                }
                return tokenSource;
            }
            set {
                tokenSource = value;
            }
        }

        public ListAdapter<Node> Children {get => new ListAdapter<Node>(children); }

        public Node GetChild(int i) {
            return children[i];
        }

        public void SetChild(int i, Node n) {
            children[i] = n;
            n.Parent = this;
        }

        public void AddChild(Node n) {
            children.Add(n);
            n.Parent = this;
        }

        public void AddChild(int i, Node n) {
            children.Insert(i, n);
            n.Parent = this;
        }

        public void ClearChildren() => children.Clear();

[#if grammar.nodeUsesParser]
        internal Parser parser;
[/#if]

[#if grammar.nodeUsesParser]
        public BaseNode(Parser parser) {
            this.parser = parser;
            this(parser.InputSource);
        }

[/#if]
        public BaseNode(Lexer tokenSource) {
            this.tokenSource = tokenSource;
        }

        public void AddChild(BaseNode node) {
            AddChild(node, -1);
        }

        public void AddChild(BaseNode node, int index) {
            if (index < 0) {
                children.Add(node);
            }
            else {
                children.Insert(index, node);
            }
            node.Parent = this;
        }

        public void RemoveChild(int index) {
            children.RemoveAt(index);
        }

        public int ChildCount {
            get => children.Count;
        }

        protected IDictionary<string, Node> NamedChildMap;
        protected IDictionary<string, IList<Node>> NamedChildListMap;

        public Node GetNamedChild(string name) {
            if (NamedChildMap == null) {
                return null;
            }
            if (!NamedChildMap.ContainsKey(name)) {
                return null;
            }
            return NamedChildMap[name];
        }

        public void SetNamedChild(String name, Node node) {
            if (NamedChildMap == null) {
                NamedChildMap = new Dictionary<string, Node>();
            }
            if (NamedChildMap.ContainsKey(name)) {
                string msg = @"Duplicate named child not allowed: {name}";
                throw new ApplicationException(msg);
            }
            NamedChildMap[name] = node;
        }

        public IList<Node> GetNamedChildList(string name) {
            if (NamedChildListMap == null) {
                return null;
            }
            if (!NamedChildListMap.ContainsKey(name)) {
                return null;
            }
            return NamedChildListMap[name];
        }

        public void AddToNamedChildList(string name, Node node) {
            if (NamedChildListMap == null) {
                NamedChildListMap = new Dictionary<string, IList<Node>>();
            }

            IList<Node> nodeList;

            if (NamedChildListMap.ContainsKey(name)) {
                nodeList = NamedChildListMap[name];
            }
            else {
                nodeList = new List<Node>();
                NamedChildListMap[name] = nodeList;
            }
            nodeList.Add(node);
        }
    }

    public class Token[#if grammar.treeBuildingEnabled] : Node[/#if] {

        public Lexer TokenSource { get; set; }
        public int BeginOffset { get; set; }
        public int EndOffset { get; set; }
        public Node Parent { get; set; }
        public int ChildCount => 0;
        public Node GetChild(int i) => null;
        public ListAdapter<Node> Children => new ListAdapter<Node>();
        public void SetChild(int i, Node n) { throw new NotSupportedException(); }
        public void AddChild(Node n) { throw new NotSupportedException(); }
        public void AddChild(int i, Node n) { throw new NotSupportedException(); }
        public void RemoveChild(int i) { throw new NotSupportedException(); }
        public void ClearChildren() {}

        // TODO us default implementations in interface
        public int BeginLine {
            get {
                return (TokenSource == null) ? 0 : TokenSource.GetLineFromOffset(BeginOffset);
            }
        }

        public int EndLine {
            get {
                return (TokenSource == null) ? 0 : TokenSource.GetLineFromOffset(EndOffset - 1);
            }
        }

        public int BeginColumn {
            get {
                return (TokenSource == null) ? 0 : TokenSource.GetCodePointColumnFromOffset(BeginOffset);
            }
        }

        public int EndColumn {
            get {
                return (TokenSource == null) ? 0 : TokenSource.GetCodePointColumnFromOffset(EndOffset - 1);
            }
        }
        
        public TokenType Type { get; internal set; }

[#if !grammar.treeBuildingEnabled]
        internal bool IsUnparsed;
[#else]
        public bool IsUnparsed { get; internal set; }
[/#if]

[#if !grammar.minimalToken || grammar.faultTolerant]
        private string _image;

        public string Image {
            get {
                return _image != null ? _image: Source;
            }
            set { _image = value; }
        }
[#else]
        public string Image => Source;
[/#if]

        virtual public bool IsSkipped() {
[#if grammar.faultTolerant]
           return skipped;
[#else]
           return false;
[/#if]
        }

        virtual public bool IsVirtual() {
[#if grammar.faultTolerant]
           return virtual || Type == TokenType.EOF;
[#else]
           return Type == TokenType.EOF;
[/#if]
        }

[#if grammar.faultTolerant]
        private bool virtual, skipped, dirty;

        internal void SetVirtual(bool value) {
            virtual = value;
            if (virtual) {
                dirty = true;
            }
        }

        internal void SetSkipped(bool value) {
            skipped = value;
            if (skipped) {
                dirty = true;
            }
        }

        public bool IsDirty() {
            return dirty;
        }

        public void SetDirty(bool value) {
            dirty = value;
        }

[/#if]

        /**
        * @param type the #TokenType of the token being constructed
        * @param image the String content of the token
        * @param tokenSource the object that vended this token.
        */
        public Token(TokenType kind, Lexer tokenSource, int beginOffset, int endOffset) {
            Type = kind;
            TokenSource = tokenSource;
            BeginOffset = beginOffset;
            EndOffset = endOffset;
[#if !grammar.treeBuildingEnabled]
            TokenSource = tokenSource;
[/#if]
        }

[#if !grammar.minimalToken]

        internal Token prependedToken, appendedToken;

        internal bool isInserted;

        internal void PreInsert(Token prependedToken) {
            if (prependedToken == this.prependedToken) {
                return;
            }
            prependedToken.appendedToken = this;
            Token existingPreviousToken = this.PreviousCachedToken;
            if (existingPreviousToken != null) {
                existingPreviousToken.appendedToken = prependedToken;
                prependedToken.prependedToken = existingPreviousToken;
            }
            prependedToken.isInserted = true;
            prependedToken.BeginOffset = prependedToken.EndOffset = this.BeginOffset;
            this.prependedToken = prependedToken;
        }
        
        internal void UnsetAppendedToken() {
            appendedToken = null;
        }

        internal static Token NewToken(TokenType type, String image, Lexer tokenSource) {
            Token result = NewToken(type, tokenSource, 0, 0);
            result.Image = image;
            return result;
        }
    [/#if]

        internal static Token NewToken(TokenType type, Lexer tokenSource, int beginOffset, int endOffset) {
[#if grammar.treeBuildingEnabled]
            switch(type) {
  [#list grammar.orderedNamedTokens as re]
    [#if re.generatedClassName != "Token" && !re.private]
            case TokenType.${re.label} : return new ${grammar.nodePrefix}${re.generatedClassName}(TokenType.${re.label}, tokenSource, beginOffset, endOffset);
    [/#if]
  [/#list]
  [#list grammar.extraTokenNames as tokenName]
            case TokenType.${tokenName} : return new ${grammar.nodePrefix}${grammar.extraTokens[tokenName]}(TokenType.${tokenName}, tokenSource, beginOffset, endOffset);
  [/#list]
            case TokenType.INVALID : return new InvalidToken(tokenSource, beginOffset, endOffset);
            default : return new Token(type, tokenSource, beginOffset, endOffset);
            }
[#else]
            return new Token(type, tokenSource, beginOffset, endOffset);
[/#if]
        }

        internal string NormalizedText => (Type == TokenType.EOF) ? "EOF" : Image;

        internal Token NextToken { get; set; }
        internal string Location {
            get {
                Node n = (Node) this;

                return $"{TokenSource.InputSource}:{n.BeginLine}:{n.BeginColumn}";
            }
        }

[#if grammar.treeBuildingEnabled && !grammar.minimalToken]
        // Copy the location info from another node or start/end nodes
        internal void CopyLocationInfo(Node start, Node end = null) {
            ((Node) this).CopyLocationInfo(start, end);
            if (start is Token otherTok) {
                appendedToken = otherTok.appendedToken;
                prependedToken = otherTok.prependedToken;
            }
            if (end != null) {
                if (end is Token endToken) {
                    appendedToken = endToken.appendedToken;
                }
            }
        }
[#else]
        internal void CopyLocationInfo(Token start, Token end = null) {
            TokenSource = start.TokenSource;
            BeginOffset = start.BeginOffset;
            EndOffset = start.EndOffset;
[#if !grammar.minimalToken]
            appendedToken = start.appendedToken;
            prependedToken = start.prependedToken;
[/#if]
            if (end != null) {
[#if !grammar.minimalToken]
                appendedToken = end.appendedToken;
[/#if]
            }
        }

[/#if]
        internal Token Next {
            get {
                return NextParsedToken;
            }
        }

        internal Token Previous {
            get {
                var result = PreviousCachedToken;
                while ((result != null) && result.IsUnparsed) {
                    result = result.PreviousCachedToken;
                }
                return result;
            }
        }

        internal Token NextParsedToken {
            get {
                var result = NextCachedToken;
                while ((result != null) && result.IsUnparsed) {
                    result = result.NextCachedToken;
                }
                return result;
            }
        }

        internal Token NextCachedToken {
            get {
[#if !grammar.minimalToken]        
                if (appendedToken != null) {
                    return appendedToken;
                }
[/#if]
                return TokenSource == null ? null : TokenSource.NextCachedToken(EndOffset);
            }
        }

        internal Token PreviousCachedToken {
            get {
[#if !grammar.minimalToken]        
                if (prependedToken !=null) {
                    return prependedToken;
                }
[/#if]        
                return TokenSource == null ? null : TokenSource.PreviousCachedToken(BeginOffset);
            }
        }

        internal Token PreviousToken {
            get {
                return PreviousCachedToken;
            }
        }

        internal Token ReplaceType(TokenType type) {
            Token result = NewToken(Type, TokenSource, BeginOffset, EndOffset);
[#if !grammar.minimalToken] 
            result.prependedToken = prependedToken;
            result.appendedToken = appendedToken;
            result.isInserted = isInserted;
            if (result.appendedToken != null) {
                result.appendedToken.prependedToken = result;
            }
            if (result.prependedToken != null) {
                result.prependedToken.appendedToken = result;
            }
            if (!result.isInserted) {
                TokenSource.CacheToken(result);
            }
[#else]
            TokenSource.CacheToken(result);
[/#if]
            return result;
        }

        public string Source {
            get {
                if (Type == TokenType.EOF) {
                    return "";
                }
                return (TokenSource == null) ? null : TokenSource.GetText(BeginOffset, EndOffset);
            }
        }

        private IEnumerable<Token> precedingTokens() {
            Token current = this;
            Token t;

            while ((t = current.PreviousCachedToken) != null) {
                current = t;
                yield return current;
            }
        }

        internal Iterator<Token> PrecedingTokens() {
            return new GenWrapper<Token>(precedingTokens());
        }

[#if unwanted!false]
        private IEnumerable<Token> followingTokens() {
            Token current = this;
            Token t;

            while ((t = current.NextCachedToken) != null) {
                current = t;
                yield return current;
            }
        }

        internal ListIterator<Token>? FollowingTokens() {
            return null;
        }

[/#if]

${grammar.utils.translateTokenInjections(true)}

${grammar.utils.translateTokenInjections(false)}

    }

    // Token subclasses

[#var tokenSubClassInfo = grammar.utils.tokenSubClassInfo()]
[#list tokenSubClassInfo.sortedNames as name]
    public class ${name} : ${tokenSubClassInfo.tokenClassMap[name]} {
        public ${name}(TokenType kind, Lexer tokenSource, int beginOffset, int endOffset) : base(kind, tokenSource, beginOffset, endOffset) {}
    }

[/#list]

[#if grammar.extraTokens?size > 0]
  [#list grammar.extraTokenNames as name]
    [#var cn = grammar.extraTokens[name]]
    public class ${cn} : Token {
        public ${cn}(TokenType kind, Lexer tokenSource, int beginOffset, int endOffset) : base(kind, tokenSource, beginOffset, endOffset) {}

${grammar.utils.translateTokenSubclassInjections(cn, true)}
${grammar.utils.translateTokenSubclassInjections(cn, false)}
    }

  [/#list]
[/#if]


    public class InvalidToken : Token {
        public InvalidToken(Lexer tokenSource, int beginOffset, int endOffset) : base(TokenType.INVALID, tokenSource, beginOffset, endOffset) {}
    }
}
