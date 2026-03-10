require "../spec_helper"
require "../../src/asciidoc_pdf"

describe AsciidocPDF::Theme do
  it "has sensible defaults" do
    theme = AsciidocPDF::Theme.new
    theme.page_width.should eq(595.28)
    theme.page_height.should eq(841.89)
    theme.base_font_size.should eq(10.5)
    theme.base_font_family.should eq("Helvetica")
  end

  it "calculates content dimensions" do
    theme = AsciidocPDF::Theme.new
    theme.content_width.should be_close(451.28, 0.01)
    theme.content_height.should be_close(697.89, 0.01)
  end

  it "returns heading font sizes by level" do
    theme = AsciidocPDF::Theme.new
    theme.heading_font_size(1).should eq(24.0)
    theme.heading_font_size(2).should eq(18.0)
    theme.heading_font_size(3).should eq(15.0)
  end
end

describe AsciidocPDF::Converter do
  it "creates a converter with default theme" do
    converter = AsciidocPDF::Converter.new
    converter.theme.should_not be_nil
    converter.document.should_not be_nil
  end

  it "converts a minimal document" do
    source = <<-ADOC
    = Hello World

    == Introduction

    This is a simple document.
    ADOC

    converter = AsciidocPDF::Converter.convert(source)
    converter.should_not be_nil
  end

  it "converts a document with multiple sections" do
    source = <<-ADOC
    = Multi-Section Doc

    == Chapter 1

    First chapter content.

    == Chapter 2

    Second chapter content.

    === Subsection 2.1

    Subsection content.
    ADOC

    converter = AsciidocPDF::Converter.convert(source)
    converter.should_not be_nil
  end

  it "converts a document with lists" do
    source = <<-ADOC
    = Lists Doc

    == Lists

    * Item one
    * Item two
    * Item three

    . First
    . Second
    . Third
    ADOC

    converter = AsciidocPDF::Converter.convert(source)
    converter.should_not be_nil
  end

  it "converts a document with a code block" do
    source = <<-ADOC
    = Code Doc

    == Example

    [source,crystal]
    ----
    puts "Hello, World!"
    ----
    ADOC

    converter = AsciidocPDF::Converter.convert(source)
    converter.should_not be_nil
  end

  it "converts a document with an admonition" do
    source = <<-ADOC
    = Admonition Doc

    == Notes

    NOTE: This is an important note.

    TIP: This is a helpful tip.
    ADOC

    converter = AsciidocPDF::Converter.convert(source)
    converter.should_not be_nil
  end

  it "converts a document with a table" do
    source = <<-ADOC
    = Table Doc

    == Data

    |===
    | Name | Age | City
    | Alice | 30 | Paris
    | Bob | 25 | London
    |===
    ADOC

    converter = AsciidocPDF::Converter.convert(source)
    converter.should_not be_nil
  end

  it "converts a document with page breaks" do
    source = <<-ADOC
    = Page Break Doc

    == Part 1

    Content before break.

    <<<

    == Part 2

    Content after break.
    ADOC

    converter = AsciidocPDF::Converter.convert(source)
    converter.should_not be_nil
  end

  it "converts a document with a blockquote" do
    source = <<-ADOC
    = Quote Doc

    == Quotes

    ____
    To be or not to be, that is the question.
    ____
    ADOC

    converter = AsciidocPDF::Converter.convert(source)
    converter.should_not be_nil
  end

  it "writes PDF to a file" do
    source = "= Test\n\n== Section\n\nHello world.\n"
    converter = AsciidocPDF::Converter.convert(source)

    path = "/tmp/test_output.pdf"
    converter.save(path)
    File.exists?(path).should be_true
    File.size(path).should be > 0

    # Verify it starts with PDF header
    bytes = File.open(path, "rb") { |f| f.read_string(5) }
    bytes.should start_with("%PDF")

    File.delete(path)
  end

  it "writes PDF to IO" do
    source = "= Test\n\n== Section\n\nHello world.\n"
    converter = AsciidocPDF::Converter.convert(source)

    io = IO::Memory.new
    converter.write(io)
    io.size.should be > 0
  end

  it "handles image not found gracefully" do
    source = "= Test\n\n== Section\n\nimage::nonexistent.png[Alt text]\n"
    converter = AsciidocPDF::Converter.convert(source)
    converter.warnings.size.should be > 0
    converter.warnings[0].should contain("nonexistent.png")
  end

  it "converts a comprehensive document" do
    source = <<-ADOC
    = Comprehensive Document
    Author Name <author@example.com>
    v1.0, 2026-01-01

    == Introduction

    This is the _introduction_ to our *comprehensive* document.
    It demonstrates `inline code` and various features.

    == Features

    === Lists

    Unordered list:

    * Feature one
    * Feature two
    * Feature three

    Ordered list:

    . Step one
    . Step two
    . Step three

    === Code

    [source,crystal]
    ----
    class Greeter
      def greet(name : String)
        puts "Hello, " + name + "!"
      end
    end
    ----

    === Tables

    |===
    | Feature | Status | Priority
    | Parser | Done | High
    | Converter | Done | High
    | Theme | Done | Medium
    |===

    === Admonitions

    NOTE: This is a note.

    TIP: This is a tip.

    WARNING: This is a warning.

    == Conclusion

    This concludes our document.
    ADOC

    converter = AsciidocPDF::Converter.convert(source)
    path = "/tmp/comprehensive_test.pdf"
    converter.save(path)
    File.exists?(path).should be_true
    File.size(path).should be > 100
    File.delete(path)
  end
end
