require "../spec_helper"
require "../../src/asciidoc_pdf"

# Integration tests for the Syntax Highlighting feature.
#
# These tests verify that:
#   1. The `SyntaxHighlighter` tokenises Crystal code correctly.
#   2. The `Theme` exposes the expected colour properties.
#   3. `Converter#render_listing` produces valid PDF output when a
#      language is specified on a source block.
#   4. Syntax highlighting can be disabled via the theme flag.

describe "Syntax Highlighting" do
  # -----------------------------------------------------------------------
  # SyntaxHighlighter unit tests
  # -----------------------------------------------------------------------

  describe AsciidocPDF::SyntaxHighlighter do
    it "tokenises Crystal keywords" do
      tokens = AsciidocPDF::SyntaxHighlighter.highlight("def end class module", "crystal")
      keyword_values = tokens.select(&.type.keyword?).map(&.value)
      keyword_values.should contain("def")
      keyword_values.should contain("end")
      keyword_values.should contain("class")
      keyword_values.should contain("module")
    end

    it "tokenises Crystal string literals" do
      tokens = AsciidocPDF::SyntaxHighlighter.highlight("\"hello world\"", "crystal")
      string_tokens = tokens.select(&.type.string?)
      string_tokens.size.should eq(1)
      string_tokens[0].value.should eq("\"hello world\"")
    end

    it "tokenises Crystal line comments" do
      tokens = AsciidocPDF::SyntaxHighlighter.highlight("# this is a comment", "crystal")
      comment_tokens = tokens.select(&.type.comment?)
      comment_tokens.size.should eq(1)
      comment_tokens[0].value.should eq("# this is a comment")
    end

    it "tokenises Crystal integer and float literals" do
      tokens = AsciidocPDF::SyntaxHighlighter.highlight("42 3.14", "crystal")
      number_values = tokens.select(&.type.number?).map(&.value)
      number_values.should contain("42")
      number_values.should contain("3.14")
    end

    it "tokenises Crystal identifiers" do
      tokens = AsciidocPDF::SyntaxHighlighter.highlight("my_variable", "crystal")
      id_tokens = tokens.select(&.type.identifier?)
      id_tokens.size.should eq(1)
      id_tokens[0].value.should eq("my_variable")
    end

    it "returns a single PLAIN token for unsupported languages" do
      tokens = AsciidocPDF::SyntaxHighlighter.highlight("some code", "cobol")
      tokens.size.should eq(1)
      tokens[0].type.should eq(AsciidocPDF::SyntaxHighlighter::TokenType::PLAIN)
    end

    it "handles an empty source string" do
      tokens = AsciidocPDF::SyntaxHighlighter.highlight("", "crystal")
      tokens.should be_empty
    end

    it "tokenises a multi-token Crystal expression" do
      source = "x = 1 + 2"
      tokens = AsciidocPDF::SyntaxHighlighter.highlight(source, "crystal")
      tokens.should_not be_empty
      # There must be at least one number token
      tokens.any?(&.type.number?).should be_true
    end
  end

  # -----------------------------------------------------------------------
  # Theme colour properties
  # -----------------------------------------------------------------------

  describe AsciidocPDF::Theme do
    it "exposes syntax highlight colour properties with sensible defaults" do
      theme = AsciidocPDF::Theme.new
      theme.syntax_highlight_enabled.should be_true
      # Keyword colour should be a blue-ish tuple
      r, _g, b = theme.syntax_keyword_color
      b.should be > r  # more blue than red
      # Comment colour should be grey-ish
      cr, cg, cb = theme.syntax_comment_color
      cr.should be_close(cg, 0.1)
      cg.should be_close(cb, 0.1)
    end

    it "allows disabling syntax highlighting" do
      theme = AsciidocPDF::Theme.new
      theme.syntax_highlight_enabled = false
      theme.syntax_highlight_enabled.should be_false
    end

    it "allows customising token colours" do
      theme = AsciidocPDF::Theme.new
      theme.syntax_keyword_color = {1.0, 0.0, 0.0}
      r, g, b = theme.syntax_keyword_color
      r.should eq(1.0)
      g.should eq(0.0)
      b.should eq(0.0)
    end
  end

  # -----------------------------------------------------------------------
  # Converter integration tests
  # -----------------------------------------------------------------------

  describe AsciidocPDF::Converter do
    it "converts a source block with Crystal syntax highlighting to PDF" do
      source = <<-ADOC
      = Highlighted Code

      == Example

      [source,crystal]
      ----
      def greet(name : String)
        puts "Hello, " + name + "!"
      end
      ----
      ADOC

      converter = AsciidocPDF::Converter.convert(source)
      io = IO::Memory.new
      converter.write(io)
      io.size.should be > 0
      # Verify it is a valid PDF
      io.rewind
      io.read_string(5).should start_with("%PDF")
    end

    it "converts a source block without a language (plain rendering) to PDF" do
      source = <<-ADOC
      = Plain Code

      == Example

      ----
      some plain code here
      ----
      ADOC

      converter = AsciidocPDF::Converter.convert(source)
      io = IO::Memory.new
      converter.write(io)
      io.size.should be > 0
    end

    it "produces a larger PDF when syntax highlighting is enabled vs disabled" do
      source = <<-ADOC
      = Code Doc

      [source,crystal]
      ----
      def hello
        puts "world"
      end
      ----
      ADOC

      # Highlighted PDF
      theme_on = AsciidocPDF::Theme.new
      theme_on.syntax_highlight_enabled = true
      conv_on = AsciidocPDF::Converter.convert(source, theme_on)
      io_on = IO::Memory.new
      conv_on.write(io_on)

      # Plain PDF (highlighting disabled)
      theme_off = AsciidocPDF::Theme.new
      theme_off.syntax_highlight_enabled = false
      conv_off = AsciidocPDF::Converter.convert(source, theme_off)
      io_off = IO::Memory.new
      conv_off.write(io_off)

      # The highlighted PDF contains more colour commands and is therefore larger.
      io_on.size.should be > io_off.size
    end

    it "converts a multi-language document to PDF without errors" do
      source = <<-ADOC
      = Multi-Language

      [source,crystal]
      ----
      x = 42
      ----

      [source,json]
      ----
      {"key": "value"}
      ----
      ADOC

      converter = AsciidocPDF::Converter.convert(source)
      converter.should_not be_nil
      io = IO::Memory.new
      converter.write(io)
      io.size.should be > 0
    end

    it "saves a highlighted PDF to disk" do
      source = <<-ADOC
      = Save Test

      [source,crystal]
      ----
      puts "saved"
      ----
      ADOC

      path = "/tmp/syntax_highlight_test.pdf"
      converter = AsciidocPDF::Converter.convert(source)
      converter.save(path)
      File.exists?(path).should be_true
      File.size(path).should be > 0
      bytes = File.open(path, "rb") { |f| f.read_string(5) }
      bytes.should start_with("%PDF")
      File.delete(path)
    end
  end
end
