module PDF
  module Syntax
    # A colored fragment ready for PDF rendering.
    # Mirrors the structure expected by PDF::Text::Formatted::Box.
    record Fragment,
      text : String,
      color : Tuple(Float64, Float64, Float64),
      bold : Bool = false,
      italic : Bool = false,
      mono : Bool = true

    # A color theme for syntax highlighting.
    # Colors are RGB tuples with values in [0.0, 1.0].
    record Theme,
      text : Tuple(Float64, Float64, Float64) = {0.2, 0.2, 0.2},
      keyword : Tuple(Float64, Float64, Float64) = {0.0, 0.0, 0.8},
      builtin : Tuple(Float64, Float64, Float64) = {0.0, 0.5, 0.5},
      string_literal : Tuple(Float64, Float64, Float64) = {0.2, 0.6, 0.0},
      number : Tuple(Float64, Float64, Float64) = {0.8, 0.3, 0.0},
      comment : Tuple(Float64, Float64, Float64) = {0.5, 0.5, 0.5},
      operator : Tuple(Float64, Float64, Float64) = {0.6, 0.0, 0.6},
      punctuation : Tuple(Float64, Float64, Float64) = {0.3, 0.3, 0.3},
      type_name : Tuple(Float64, Float64, Float64) = {0.0, 0.3, 0.7},
      attribute : Tuple(Float64, Float64, Float64) = {0.7, 0.3, 0.0},
      function_name : Tuple(Float64, Float64, Float64) = {0.0, 0.5, 0.8},
      constant : Tuple(Float64, Float64, Float64) = {0.7, 0.0, 0.0},
      preprocessor : Tuple(Float64, Float64, Float64) = {0.5, 0.0, 0.5},
      tag_name : Tuple(Float64, Float64, Float64) = {0.0, 0.0, 0.8},
      attr_name : Tuple(Float64, Float64, Float64) = {0.5, 0.0, 0.5},
      attr_value : Tuple(Float64, Float64, Float64) = {0.2, 0.6, 0.0}

    # Default light theme (similar to asciidoctor-pdf default)
    DEFAULT_THEME = Theme.new

    # Monokai-inspired dark theme
    MONOKAI_THEME = Theme.new(
      text: {0.97, 0.97, 0.94},
      keyword: {0.98, 0.15, 0.45},
      builtin: {0.40, 0.86, 0.94},
      string_literal: {0.90, 0.86, 0.45},
      number: {0.68, 0.51, 1.0},
      comment: {0.46, 0.44, 0.37},
      operator: {0.98, 0.15, 0.45},
      punctuation: {0.97, 0.97, 0.94},
      type_name: {0.40, 0.86, 0.94},
      attribute: {0.68, 0.51, 1.0},
      function_name: {0.65, 0.89, 0.18},
      constant: {0.68, 0.51, 1.0},
      preprocessor: {0.98, 0.15, 0.45},
      tag_name: {0.98, 0.15, 0.45},
      attr_name: {0.65, 0.89, 0.18},
      attr_value: {0.90, 0.86, 0.45}
    )

    # Converts a list of tokens into colored PDF fragments using a theme.
    class Highlighter
      def initialize(@theme : Theme = DEFAULT_THEME)
      end

      # Returns a list of Fragment records ready for PDF rendering.
      def highlight(tokens : Array(Token)) : Array(Fragment)
        tokens.map do |token|
          color = color_for(token.type)
          bold = token.type == TokenType::Keyword
          Fragment.new(
            text: token.text,
            color: color,
            bold: bold
          )
        end
      end

      # Highlights source code in a given language and returns fragments.
      def highlight_source(source : String, language : String) : Array(Fragment)
        lexer = Highlighter.lexer_for(language)
        tokens = lexer.tokenise(source)
        highlight(tokens)
      end

      # Returns the appropriate lexer for a language identifier.
      def self.lexer_for(language : String) : Lexer
        case language.downcase
        when "crystal", "cr"
          CrystalLexer.new
        when "ruby", "rb"
          RubyLexer.new
        when "python", "py"
          PythonLexer.new
        when "javascript", "js"
          JavaScriptLexer.new
        when "typescript", "ts"
          TypeScriptLexer.new
        when "shell", "bash", "sh", "zsh"
          ShellLexer.new
        when "json"
          JsonLexer.new
        when "yaml", "yml"
          YamlLexer.new
        when "xml"
          XmlLexer.new
        when "html", "htm"
          HtmlLexer.new
        else
          PlainLexer.new
        end
      end

      private def color_for(type : TokenType) : Tuple(Float64, Float64, Float64)
        case type
        when TokenType::Keyword       then @theme.keyword
        when TokenType::Builtin       then @theme.builtin
        when TokenType::StringLiteral then @theme.string_literal
        when TokenType::Number        then @theme.number
        when TokenType::Comment       then @theme.comment
        when TokenType::Operator      then @theme.operator
        when TokenType::Punctuation   then @theme.punctuation
        when TokenType::TypeName      then @theme.type_name
        when TokenType::Attribute     then @theme.attribute
        when TokenType::FunctionName  then @theme.function_name
        when TokenType::Constant      then @theme.constant
        when TokenType::Preprocessor  then @theme.preprocessor
        when TokenType::TagName       then @theme.tag_name
        when TokenType::AttrName      then @theme.attr_name
        when TokenType::AttrValue     then @theme.attr_value
        else                          @theme.text
        end
      end
    end
  end
end
