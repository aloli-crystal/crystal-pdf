
require "../spec_helper"
require "../../src/asciidoc_pdf/syntax_highlighter"

describe AsciidocPDF::SyntaxHighlighter do
  it "highlights Crystal code" do
    source = "def greet(name : String)\n  puts \"Hello, \" + name + \"!\"\nend"

    tokens = AsciidocPDF::SyntaxHighlighter.highlight(source, "crystal")
    tokens.should_not be_empty


    # Check a few key tokens
    tokens[0].type.should eq(AsciidocPDF::SyntaxHighlighter::TokenType::KEYWORD)
    tokens[0].value.should eq("def")

    tokens[5].type.should eq(AsciidocPDF::SyntaxHighlighter::TokenType::IDENTIFIER)
    tokens[5].value.should eq("String")

    tokens[8].type.should eq(AsciidocPDF::SyntaxHighlighter::TokenType::STRING)
    tokens[8].value.should eq("\"Hello, \"")
  end

  it "handles generic code as plain text" do
    source = "<xml>some content</xml>"
    tokens = AsciidocPDF::SyntaxHighlighter.highlight(source, "xml")
    tokens.size.should eq(1)
    tokens[0].type.should eq(AsciidocPDF::SyntaxHighlighter::TokenType::PLAIN)
    tokens[0].value.should eq(source)
  end
end
