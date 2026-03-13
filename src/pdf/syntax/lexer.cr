module PDF
  module Syntax
    # Base lexer: tokenises source code into a flat list of Token records.
    # Each language subclass overrides `tokenise` to apply its own rules.
    abstract class Lexer
      # Returns an ordered list of tokens for the given source string.
      abstract def tokenise(source : String) : Array(Token)

      # Splits *source* into tokens using a list of {regex, type} rules applied
      # in order. Any text not matched by any rule is emitted as TokenType::Text.
      protected def tokenise_with_rules(source : String, rules : Array(Tuple(Regex, TokenType))) : Array(Token)
        tokens = [] of Token
        remaining = source
        while !remaining.empty?
          matched = false
          rules.each do |pattern, token_type|
            if m = remaining.match(pattern)
              # Emit any unmatched prefix as plain text
              if m.begin(0) > 0
                tokens << Token.new(text: remaining[0...m.begin(0)], type: TokenType::Text)
              end
              tokens << Token.new(text: m[0], type: token_type)
              remaining = remaining[m.end(0)..]
              matched = true
              break
            end
          end
          unless matched
            # Advance one character as plain text
            tokens << Token.new(text: remaining[0..0], type: TokenType::Text)
            remaining = remaining[1..]
          end
        end
        tokens
      end
    end

    # -------------------------------------------------------------------------
    # Crystal / Ruby lexer (shared grammar, very similar)
    # -------------------------------------------------------------------------
    class CrystalLexer < Lexer
      KEYWORDS = %w[
        abstract alias annotation as as? asm begin break case class
        def do else elsif end ensure enum extend false for fun if in
        include instance_sizeof is_a? lib macro module next nil nil?
        of offsetof out pointerof private protected require rescue responds_to?
        return select self sizeof struct super then true type typeof union
        unless until verbatim when while with yield
      ]

      BUILTINS = %w[
        puts print p pp p! raise exit abort sleep rand
        Int8 Int16 Int32 Int64 Int128 UInt8 UInt16 UInt32 UInt64 UInt128
        Float32 Float64 Bool Char String Symbol Array Hash Tuple NamedTuple
        Proc Pointer Slice Range Regex IO File Dir Path Time
        Nil Void NoReturn
      ]

      RULES = [
        # Single-line comment
        {/\A#[^\n]*/, TokenType::Comment},
        # Multi-line string heredoc (simplified)
        {/\A<<-?[A-Z_]+/, TokenType::StringLiteral},
        # Double-quoted string
        {/\A"(?:[^"\\]|\\.)*"/, TokenType::StringLiteral},
        # Single-quoted char/string
        {/\A'(?:[^'\\]|\\.)*'/, TokenType::StringLiteral},
        # Percent string literals
        {/\A%[qQwWi]\{[^}]*\}/, TokenType::StringLiteral},
        # Symbol literal
        {/\A:[a-zA-Z_][a-zA-Z0-9_]*[?!]?/, TokenType::Attribute},
        # Instance variable
        {/\A@@?[a-zA-Z_][a-zA-Z0-9_]*/, TokenType::Attribute},
        # Float literal
        {/\A\d[\d_]*\.\d[\d_]*(?:[eE][+-]?\d+)?(?:_?f(?:32|64))?/, TokenType::Number},
        # Integer literal (hex, octal, binary, decimal)
        {/\A0x[0-9a-fA-F][\da-fA-F_]*(?:_?[iu](?:8|16|32|64|128))?/, TokenType::Number},
        {/\A0o[0-7][0-7_]*(?:_?[iu](?:8|16|32|64|128))?/, TokenType::Number},
        {/\A0b[01][01_]*(?:_?[iu](?:8|16|32|64|128))?/, TokenType::Number},
        {/\A\d[\d_]*(?:_?[iu](?:8|16|32|64|128))?/, TokenType::Number},
        # Operators
        {/\A(?:=>|->|<<|>>|<=|>=|==|!=|&&|\|\||\.\.\.|\.\.|[+\-*\/%&|^~<>!]=?)/, TokenType::Operator},
        # Punctuation
        {/\A[(){}\[\],;.]/, TokenType::Punctuation},
        # Identifiers (keywords, builtins, type names, plain names)
        {/\A[a-zA-Z_][a-zA-Z0-9_]*[?!]?/, TokenType::Text},
        # Whitespace (preserve)
        {/\A\s+/, TokenType::Text},
      ] of Tuple(Regex, TokenType)

      def tokenise(source : String) : Array(Token)
        raw = tokenise_with_rules(source, RULES)
        raw.map do |tok|
          if tok.type == TokenType::Text
            word = tok.text.rstrip("?!")
            if KEYWORDS.includes?(word)
              Token.new(text: tok.text, type: TokenType::Keyword)
            elsif BUILTINS.includes?(word)
              Token.new(text: tok.text, type: TokenType::Builtin)
            elsif word =~ /\A[A-Z][a-zA-Z0-9_]*\z/
              Token.new(text: tok.text, type: TokenType::TypeName)
            elsif word =~ /\A[A-Z][A-Z0-9_]+\z/
              Token.new(text: tok.text, type: TokenType::Constant)
            else
              tok
            end
          else
            tok
          end
        end
      end
    end

    # Ruby uses the same lexer (grammar is nearly identical for highlighting)
    class RubyLexer < CrystalLexer
    end

    # -------------------------------------------------------------------------
    # Python lexer
    # -------------------------------------------------------------------------
    class PythonLexer < Lexer
      KEYWORDS = %w[
        False None True and as assert async await break class continue def
        del elif else except finally for from global if import in is lambda
        nonlocal not or pass raise return try while with yield
      ]

      BUILTINS = %w[
        abs all any ascii bin bool breakpoint bytearray bytes callable chr
        classmethod compile complex delattr dict dir divmod enumerate eval
        exec filter float format frozenset getattr globals hasattr hash help
        hex id input int isinstance issubclass iter len list locals map max
        memoryview min next object oct open ord pow print property range repr
        reversed round set setattr slice sorted staticmethod str sum super
        tuple type vars zip
      ]

      RULES = [
        {/\A#[^\n]*/, TokenType::Comment},
        {/\A"""(?:[^"]|"(?!""))*"""/, TokenType::StringLiteral},
        {/\A'''(?:[^']|'(?!''))*'''/, TokenType::StringLiteral},
        {/\Af?"(?:[^"\\]|\\.)*"/, TokenType::StringLiteral},
        {/\Af?'(?:[^'\\]|\\.)*'/, TokenType::StringLiteral},
        {/\A\d[\d_]*\.\d[\d_]*(?:[eE][+-]?\d+)?/, TokenType::Number},
        {/\A0x[0-9a-fA-F][\da-fA-F_]*/, TokenType::Number},
        {/\A0o[0-7][0-7_]*/, TokenType::Number},
        {/\A0b[01][01_]*/, TokenType::Number},
        {/\A\d[\d_]*/, TokenType::Number},
        {/\A(?:->|:=|<=|>=|==|!=|\*\*|\/\/|<<|>>|[+\-*\/%&|^~<>!]=?)/, TokenType::Operator},
        {/\A[(){}\[\],;:.]/, TokenType::Punctuation},
        {/\A@[a-zA-Z_][a-zA-Z0-9_]*/, TokenType::Attribute},
        {/\A[a-zA-Z_][a-zA-Z0-9_]*/, TokenType::Text},
        {/\A\s+/, TokenType::Text},
      ] of Tuple(Regex, TokenType)

      def tokenise(source : String) : Array(Token)
        raw = tokenise_with_rules(source, RULES)
        raw.map do |tok|
          if tok.type == TokenType::Text
            if KEYWORDS.includes?(tok.text)
              Token.new(text: tok.text, type: TokenType::Keyword)
            elsif BUILTINS.includes?(tok.text)
              Token.new(text: tok.text, type: TokenType::Builtin)
            elsif tok.text =~ /\A[A-Z][a-zA-Z0-9_]*\z/
              Token.new(text: tok.text, type: TokenType::TypeName)
            elsif tok.text =~ /\A[A-Z][A-Z0-9_]+\z/
              Token.new(text: tok.text, type: TokenType::Constant)
            else
              tok
            end
          else
            tok
          end
        end
      end
    end

    # -------------------------------------------------------------------------
    # JavaScript / TypeScript lexer
    # -------------------------------------------------------------------------
    class JavaScriptLexer < Lexer
      KEYWORDS = %w[
        async await break case catch class const continue debugger default
        delete do else export extends false finally for from function get if
        import in instanceof let new null of return set static super switch
        this throw true try typeof undefined var void while with yield
      ]

      BUILTINS = %w[
        Array Boolean console Date Error Function JSON Math Number Object
        Promise RegExp Set String Symbol Map WeakMap WeakSet parseInt parseFloat
        isNaN isFinite decodeURI encodeURI setTimeout clearTimeout setInterval
        clearInterval fetch XMLHttpRequest
      ]

      RULES = [
        {/\A\/\/[^\n]*/, TokenType::Comment},
        {/\A\/\*.*?\*\//m, TokenType::Comment},
        {/\A`(?:[^`\\]|\\.)*`/, TokenType::StringLiteral},
        {/\A"(?:[^"\\]|\\.)*"/, TokenType::StringLiteral},
        {/\A'(?:[^'\\]|\\.)*'/, TokenType::StringLiteral},
        {/\A\d[\d_]*\.\d[\d_]*(?:[eE][+-]?\d+)?n?/, TokenType::Number},
        {/\A0x[0-9a-fA-F][\da-fA-F_]*n?/, TokenType::Number},
        {/\A0b[01][01_]*n?/, TokenType::Number},
        {/\A0o[0-7][0-7_]*n?/, TokenType::Number},
        {/\A\d[\d_]*n?/, TokenType::Number},
        {/\A(?:===|!==|=>|<=|>=|==|!=|\+\+|--|&&|\|\||<<|>>|>>>|[+\-*\/%&|^~<>!]=?)/, TokenType::Operator},
        {/\A[(){}\[\],;:.]/, TokenType::Punctuation},
        {/\A[a-zA-Z_$][a-zA-Z0-9_$]*/, TokenType::Text},
        {/\A\s+/, TokenType::Text},
      ] of Tuple(Regex, TokenType)

      def tokenise(source : String) : Array(Token)
        raw = tokenise_with_rules(source, RULES)
        raw.map do |tok|
          if tok.type == TokenType::Text
            if KEYWORDS.includes?(tok.text)
              Token.new(text: tok.text, type: TokenType::Keyword)
            elsif BUILTINS.includes?(tok.text)
              Token.new(text: tok.text, type: TokenType::Builtin)
            elsif tok.text =~ /\A[A-Z][a-zA-Z0-9_]*\z/
              Token.new(text: tok.text, type: TokenType::TypeName)
            else
              tok
            end
          else
            tok
          end
        end
      end
    end

    # TypeScript reuses the JavaScript lexer
    class TypeScriptLexer < JavaScriptLexer
    end

    # -------------------------------------------------------------------------
    # Shell / Bash lexer
    # -------------------------------------------------------------------------
    class ShellLexer < Lexer
      KEYWORDS = %w[
        if then else elif fi for while do done case esac in function select
        until return break continue exit trap eval exec source export unset
        local readonly declare typeset
      ]

      RULES = [
        {/\A#[^\n]*/, TokenType::Comment},
        {/\A"(?:[^"\\]|\\.)*"/, TokenType::StringLiteral},
        {/\A'[^']*'/, TokenType::StringLiteral},
        {/\A\$(?:\{[^}]*\}|[a-zA-Z_][a-zA-Z0-9_]*|\d+|[@*#?$!])/, TokenType::Attribute},
        {/\A\d+/, TokenType::Number},
        {/\A(?:&&|\|\||>>|<<|[|&;><])/, TokenType::Operator},
        {/\A[(){}\[\]]/, TokenType::Punctuation},
        {/\A[a-zA-Z_][a-zA-Z0-9_]*/, TokenType::Text},
        {/\A\s+/, TokenType::Text},
        {/\A[^\s]/, TokenType::Text},
      ] of Tuple(Regex, TokenType)

      def tokenise(source : String) : Array(Token)
        raw = tokenise_with_rules(source, RULES)
        raw.map do |tok|
          if tok.type == TokenType::Text && KEYWORDS.includes?(tok.text)
            Token.new(text: tok.text, type: TokenType::Keyword)
          else
            tok
          end
        end
      end
    end

    # -------------------------------------------------------------------------
    # JSON lexer
    # -------------------------------------------------------------------------
    class JsonLexer < Lexer
      RULES = [
        {/\A"(?:[^"\\]|\\.)*"/, TokenType::StringLiteral},
        {/\A-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?/, TokenType::Number},
        {/\A(?:true|false|null)/, TokenType::Keyword},
        {/\A[{}\[\],:]/, TokenType::Punctuation},
        {/\A\s+/, TokenType::Text},
      ] of Tuple(Regex, TokenType)

      def tokenise(source : String) : Array(Token)
        tokenise_with_rules(source, RULES)
      end
    end

    # -------------------------------------------------------------------------
    # YAML lexer
    # -------------------------------------------------------------------------
    class YamlLexer < Lexer
      RULES = [
        {/\A#[^\n]*/, TokenType::Comment},
        {/\A"(?:[^"\\]|\\.)*"/, TokenType::StringLiteral},
        {/\A'[^']*'/, TokenType::StringLiteral},
        {/\A---/, TokenType::Operator},
        {/\A\.\.\./, TokenType::Operator},
        {/\A[a-zA-Z_][a-zA-Z0-9_\-]*(?=\s*:)/, TokenType::AttrName},
        {/\A(?:true|false|null|~)/, TokenType::Keyword},
        {/\A-?\d+(?:\.\d+)?/, TokenType::Number},
        {/\A[&*!|>]/, TokenType::Operator},
        {/\A[:{}\[\],]/, TokenType::Punctuation},
        {/\A\s+/, TokenType::Text},
        {/\A[^\s]/, TokenType::Text},
      ] of Tuple(Regex, TokenType)

      def tokenise(source : String) : Array(Token)
        tokenise_with_rules(source, RULES)
      end
    end

    # -------------------------------------------------------------------------
    # XML / HTML lexer
    # -------------------------------------------------------------------------
    class XmlLexer < Lexer
      def tokenise(source : String) : Array(Token)
        tokens = [] of Token
        remaining = source

        while !remaining.empty?
          # XML comment
          if remaining.starts_with?("<!--")
            end_pos = remaining.index("-->")
            if end_pos
              tokens << Token.new(text: remaining[0...end_pos + 3], type: TokenType::Comment)
              remaining = remaining[end_pos + 3..]
              next
            end
          end

          # CDATA
          if remaining.starts_with?("<![CDATA[")
            end_pos = remaining.index("]]>")
            if end_pos
              tokens << Token.new(text: remaining[0...end_pos + 3], type: TokenType::StringLiteral)
              remaining = remaining[end_pos + 3..]
              next
            end
          end

          # Opening or closing tag
          if m = remaining.match(/\A<\/?([a-zA-Z][a-zA-Z0-9_:-]*)/)
            tokens << Token.new(text: m[0], type: TokenType::TagName)
            remaining = remaining[m.end(0)..]

            # Attributes inside the tag
            while !remaining.empty? && !remaining.starts_with?(">") && !remaining.starts_with?("/>")
              if m2 = remaining.match(/\A\s+/)
                tokens << Token.new(text: m2[0], type: TokenType::Text)
                remaining = remaining[m2.end(0)..]
              elsif m2 = remaining.match(/\A([a-zA-Z][a-zA-Z0-9_:-]*)(\s*=\s*)("(?:[^"\\]|\\.)*"|'[^']*')/)
                tokens << Token.new(text: m2[1], type: TokenType::AttrName)
                tokens << Token.new(text: m2[2], type: TokenType::Operator)
                tokens << Token.new(text: m2[3], type: TokenType::AttrValue)
                remaining = remaining[m2.end(0)..]
              elsif m2 = remaining.match(/\A[a-zA-Z][a-zA-Z0-9_:-]*/)
                tokens << Token.new(text: m2[0], type: TokenType::AttrName)
                remaining = remaining[m2.end(0)..]
              else
                tokens << Token.new(text: remaining[0..0], type: TokenType::Text)
                remaining = remaining[1..]
              end
            end

            # Closing > or />
            if remaining.starts_with?("/>")
              tokens << Token.new(text: "/>", type: TokenType::TagName)
              remaining = remaining[2..]
            elsif remaining.starts_with?(">")
              tokens << Token.new(text: ">", type: TokenType::TagName)
              remaining = remaining[1..]
            end
            next
          end

          # Plain text
          if m = remaining.match(/\A[^<]+/)
            tokens << Token.new(text: m[0], type: TokenType::Text)
            remaining = remaining[m.end(0)..]
          else
            tokens << Token.new(text: remaining[0..0], type: TokenType::Text)
            remaining = remaining[1..]
          end
        end

        tokens
      end
    end

    # HTML reuses the XML lexer
    class HtmlLexer < XmlLexer
    end

    # -------------------------------------------------------------------------
    # Plain text fallback lexer (no highlighting)
    # -------------------------------------------------------------------------
    class PlainLexer < Lexer
      def tokenise(source : String) : Array(Token)
        [Token.new(text: source, type: TokenType::Text)]
      end
    end
  end
end
