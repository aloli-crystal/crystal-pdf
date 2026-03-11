require "string_scanner"

module AsciidocPDF
  module SyntaxHighlighter
    # Represents a single token of highlighted code.
    record Token, type : TokenType, value : String

    # Defines the category of a token for theming purposes.
    enum TokenType
      KEYWORD
      STRING
      COMMENT
      NUMBER
      IDENTIFIER
      PUNCTUATION
      WHITESPACE
      ERROR
      PLAIN
    end

    # Tokenizes source code for a given language.
    def self.highlight(source : String, lang : String) : Array(Token)
      tokenizer = case lang.downcase
                  when "crystal"
                    CrystalTokenizer.new(source)
                  else
                    GenericTokenizer.new(source)
                  end
      tokenizer.tokenize
    end

    # Abstract base class for all tokenizers.
    private abstract class Tokenizer
      getter source : String
      getter tokens : Array(Token) = [] of Token
      @scanner : StringScanner

      def initialize(@source)
        @scanner = StringScanner.new(@source)
      end

      abstract def tokenize : Array(Token)

      protected def scan(regex : Regex) : String?
        @scanner.scan(regex)
      end

      protected def eos? : Bool
        @scanner.eos?
      end
    end

    # A simple tokenizer for unsupported languages.
    private class GenericTokenizer < Tokenizer
      def tokenize : Array(Token)
        [Token.new(TokenType::PLAIN, @source)]
      end
    end

    # A tokenizer for the Crystal language.
    private class CrystalTokenizer < Tokenizer
      KEYWORDS = /\b(def|if|else|end|class|module|require|while|do|case|when|in|new|nil|true|false|self)\b/
      STRINGS  = /"([^"\\]|\\.)*"/ 
      COMMENTS = /#.*$/
      NUMBERS  = /\b\d+(\.\d+)?\b/
      IDENTIFIERS = /[a-zA-Z_][a-zA-Z0-9_]*/
      PUNCTUATION = /[\.,;:\(\)\[\]\{\}<>=!+\-*\/|&%\^~]/
      WHITESPACE = /\s+/

      def tokenize : Array(Token)
        until eos?
          if value = scan(WHITESPACE)
            # skip whitespace
          elsif value = scan(COMMENTS)
            tokens << Token.new(TokenType::COMMENT, value)
          elsif value = scan(STRINGS)
            tokens << Token.new(TokenType::STRING, value)
          elsif value = scan(KEYWORDS)
            tokens << Token.new(TokenType::KEYWORD, value)
          elsif value = scan(NUMBERS)
            tokens << Token.new(TokenType::NUMBER, value)
          elsif value = scan(IDENTIFIERS)
            tokens << Token.new(TokenType::IDENTIFIER, value)
          elsif value = scan(PUNCTUATION)
            tokens << Token.new(TokenType::PUNCTUATION, value)
          else
            # Advance by one character to avoid infinite loops on errors
            char = @scanner.string.char_at(@scanner.offset)
            @scanner.offset += 1
            tokens << Token.new(TokenType::ERROR, char.to_s)
          end
        end
        tokens
      end
    end
  end
end
