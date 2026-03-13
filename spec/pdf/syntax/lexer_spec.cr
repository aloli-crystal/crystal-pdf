require "../../spec_helper"
require "../../../src/pdf/syntax"

describe PDF::Syntax do
  describe PDF::Syntax::CrystalLexer do
    it "tokenises keywords" do
      lexer = PDF::Syntax::CrystalLexer.new
      tokens = lexer.tokenise("def hello")
      keyword = tokens.find { |t| t.text == "def" }
      keyword.should_not be_nil
      keyword.not_nil!.type.should eq PDF::Syntax::TokenType::Keyword
    end

    it "tokenises string literals" do
      lexer = PDF::Syntax::CrystalLexer.new
      tokens = lexer.tokenise(%(puts "hello"))
      str = tokens.find { |t| t.text == %("hello") }
      str.should_not be_nil
      str.not_nil!.type.should eq PDF::Syntax::TokenType::StringLiteral
    end

    it "tokenises comments" do
      lexer = PDF::Syntax::CrystalLexer.new
      tokens = lexer.tokenise("# this is a comment")
      comment = tokens.find { |t| t.type == PDF::Syntax::TokenType::Comment }
      comment.should_not be_nil
      comment.not_nil!.text.should eq "# this is a comment"
    end

    it "tokenises integer literals" do
      lexer = PDF::Syntax::CrystalLexer.new
      tokens = lexer.tokenise("x = 42")
      num = tokens.find { |t| t.type == PDF::Syntax::TokenType::Number }
      num.should_not be_nil
      num.not_nil!.text.should eq "42"
    end

    it "tokenises float literals" do
      lexer = PDF::Syntax::CrystalLexer.new
      tokens = lexer.tokenise("pi = 3.14")
      num = tokens.find { |t| t.type == PDF::Syntax::TokenType::Number }
      num.should_not be_nil
      num.not_nil!.text.should eq "3.14"
    end

    it "tokenises type names" do
      lexer = PDF::Syntax::CrystalLexer.new
      tokens = lexer.tokenise("class MyClass")
      type_tok = tokens.find { |t| t.type == PDF::Syntax::TokenType::TypeName }
      type_tok.should_not be_nil
      type_tok.not_nil!.text.should eq "MyClass"
    end

    it "tokenises symbol literals as attributes" do
      lexer = PDF::Syntax::CrystalLexer.new
      tokens = lexer.tokenise(":hello")
      sym = tokens.find { |t| t.type == PDF::Syntax::TokenType::Attribute }
      sym.should_not be_nil
    end

    it "tokenises instance variables as attributes" do
      lexer = PDF::Syntax::CrystalLexer.new
      tokens = lexer.tokenise("@name = 1")
      ivar = tokens.find { |t| t.type == PDF::Syntax::TokenType::Attribute }
      ivar.should_not be_nil
      ivar.not_nil!.text.should eq "@name"
    end

    it "preserves all text when reassembled" do
      source = "def add(a, b)\n  a + b\nend"
      lexer = PDF::Syntax::CrystalLexer.new
      tokens = lexer.tokenise(source)
      tokens.map(&.text).join.should eq source
    end
  end

  describe PDF::Syntax::PythonLexer do
    it "tokenises Python keywords" do
      lexer = PDF::Syntax::PythonLexer.new
      tokens = lexer.tokenise("def foo():")
      kw = tokens.find { |t| t.text == "def" }
      kw.should_not be_nil
      kw.not_nil!.type.should eq PDF::Syntax::TokenType::Keyword
    end

    it "tokenises triple-quoted strings" do
      lexer = PDF::Syntax::PythonLexer.new
      tokens = lexer.tokenise(%["""hello world"""])
      str = tokens.find { |t| t.type == PDF::Syntax::TokenType::StringLiteral }
      str.should_not be_nil
    end
  end

  describe PDF::Syntax::JavaScriptLexer do
    it "tokenises JavaScript keywords" do
      lexer = PDF::Syntax::JavaScriptLexer.new
      tokens = lexer.tokenise("const x = 1")
      kw = tokens.find { |t| t.text == "const" }
      kw.should_not be_nil
      kw.not_nil!.type.should eq PDF::Syntax::TokenType::Keyword
    end

    it "tokenises template literals" do
      lexer = PDF::Syntax::JavaScriptLexer.new
      tokens = lexer.tokenise("`hello ${name}`")
      str = tokens.find { |t| t.type == PDF::Syntax::TokenType::StringLiteral }
      str.should_not be_nil
    end
  end

  describe PDF::Syntax::JsonLexer do
    it "tokenises JSON strings" do
      lexer = PDF::Syntax::JsonLexer.new
      tokens = lexer.tokenise(%[{"key": "value"}])
      strings = tokens.select { |t| t.type == PDF::Syntax::TokenType::StringLiteral }
      strings.size.should be >= 2
    end

    it "tokenises JSON booleans as keywords" do
      lexer = PDF::Syntax::JsonLexer.new
      tokens = lexer.tokenise("true")
      kw = tokens.find { |t| t.type == PDF::Syntax::TokenType::Keyword }
      kw.should_not be_nil
    end

    it "tokenises JSON numbers" do
      lexer = PDF::Syntax::JsonLexer.new
      tokens = lexer.tokenise("42")
      num = tokens.find { |t| t.type == PDF::Syntax::TokenType::Number }
      num.should_not be_nil
    end
  end

  describe PDF::Syntax::YamlLexer do
    it "tokenises YAML keys as attr names" do
      lexer = PDF::Syntax::YamlLexer.new
      tokens = lexer.tokenise("name: value")
      key = tokens.find { |t| t.type == PDF::Syntax::TokenType::AttrName }
      key.should_not be_nil
      key.not_nil!.text.should eq "name"
    end

    it "tokenises YAML comments" do
      lexer = PDF::Syntax::YamlLexer.new
      tokens = lexer.tokenise("# comment")
      comment = tokens.find { |t| t.type == PDF::Syntax::TokenType::Comment }
      comment.should_not be_nil
    end
  end

  describe PDF::Syntax::XmlLexer do
    it "tokenises XML tag names" do
      lexer = PDF::Syntax::XmlLexer.new
      tokens = lexer.tokenise("<root>")
      tag = tokens.find { |t| t.type == PDF::Syntax::TokenType::TagName }
      tag.should_not be_nil
    end

    it "tokenises XML attribute names and values" do
      lexer = PDF::Syntax::XmlLexer.new
      tokens = lexer.tokenise(%[<a href="url">])
      attr_name = tokens.find { |t| t.type == PDF::Syntax::TokenType::AttrName }
      attr_val = tokens.find { |t| t.type == PDF::Syntax::TokenType::AttrValue }
      attr_name.should_not be_nil
      attr_val.should_not be_nil
    end

    it "tokenises XML comments" do
      lexer = PDF::Syntax::XmlLexer.new
      tokens = lexer.tokenise("<!-- comment -->")
      comment = tokens.find { |t| t.type == PDF::Syntax::TokenType::Comment }
      comment.should_not be_nil
    end
  end

  describe PDF::Syntax::ShellLexer do
    it "tokenises shell keywords" do
      lexer = PDF::Syntax::ShellLexer.new
      tokens = lexer.tokenise("if [ -f file ]; then")
      kw = tokens.find { |t| t.text == "if" }
      kw.should_not be_nil
      kw.not_nil!.type.should eq PDF::Syntax::TokenType::Keyword
    end

    it "tokenises shell variables" do
      lexer = PDF::Syntax::ShellLexer.new
      tokens = lexer.tokenise("echo $HOME")
      var = tokens.find { |t| t.type == PDF::Syntax::TokenType::Attribute }
      var.should_not be_nil
    end
  end

  describe PDF::Syntax::Highlighter do
    it "returns plain text for unknown language" do
      h = PDF::Syntax::Highlighter.new
      frags = h.highlight_source("hello world", "unknown")
      frags.size.should eq 1
      frags.first.text.should eq "hello world"
    end

    it "highlights Crystal code with keyword colours" do
      h = PDF::Syntax::Highlighter.new
      frags = h.highlight_source("def foo", "crystal")
      kw = frags.find { |f| f.text == "def" }
      kw.should_not be_nil
      # keyword color should differ from plain text color
      kw.not_nil!.color.should_not eq PDF::Syntax::DEFAULT_THEME.text
    end

    it "selects the correct lexer for each language" do
      {
        "crystal"    => PDF::Syntax::CrystalLexer,
        "ruby"       => PDF::Syntax::RubyLexer,
        "python"     => PDF::Syntax::PythonLexer,
        "javascript" => PDF::Syntax::JavaScriptLexer,
        "typescript" => PDF::Syntax::TypeScriptLexer,
        "shell"      => PDF::Syntax::ShellLexer,
        "json"       => PDF::Syntax::JsonLexer,
        "yaml"       => PDF::Syntax::YamlLexer,
        "xml"        => PDF::Syntax::XmlLexer,
        "html"       => PDF::Syntax::HtmlLexer,
        "unknown"    => PDF::Syntax::PlainLexer,
      }.each do |lang, klass|
        PDF::Syntax::Highlighter.lexer_for(lang).class.should eq klass
      end
    end
  end
end
