module PDF
  module Syntax
    # A token type classifies a piece of source code for coloring.
    enum TokenType
      # Generic / unknown
      Text
      # Keywords: if, def, class, etc.
      Keyword
      # Built-in names: puts, print, nil, true, false
      Builtin
      # String literals: "hello", 'world'
      StringLiteral
      # Numeric literals: 42, 3.14, 0xFF
      Number
      # Comments: # comment, // comment, /* ... */
      Comment
      # Operators: +, -, ==, !=, etc.
      Operator
      # Punctuation: (, ), {, }, [, ], ;, ,
      Punctuation
      # Type / class names: MyClass, Int32
      TypeName
      # Attribute / decorator: @var, :symbol
      Attribute
      # Function / method names in definitions
      FunctionName
      # Constants: CONSTANT, MY_CONST
      Constant
      # Preprocessor / macro directives
      Preprocessor
      # XML/HTML tag names
      TagName
      # XML/HTML attribute names
      AttrName
      # XML/HTML attribute values
      AttrValue
    end

    # A single token: a piece of text with a type.
    record Token,
      text : String,
      type : TokenType
  end
end
