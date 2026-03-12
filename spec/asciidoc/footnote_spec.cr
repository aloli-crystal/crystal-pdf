require "../spec_helper"
require "../../src/asciidoc"
require "../../src/asciidoc_pdf"

# Tests for the footnote feature.
#
# Coverage:
#   - AsciiDoc::Parser.parse_inline: recognition of footnote:[text]
#   - Sequential index assignment by the Converter
#   - Collection of page footnotes
#   - Flush of footnotes at end of document (last page)
#   - Multiple footnotes in the same paragraph
#   - Footnotes across multiple paragraphs
#   - Empty footnote body
#   - Footnote adjacent to inline markup

describe "Footnotes – Parser" do
  describe "parse_inline" do
    it "recognises a bare footnote macro and returns a footnote fragment" do
      fragments = AsciiDoc::Parser.parse_inline("Hello footnote:[This is a note] world")
      # Expect 3 fragments: "Hello ", footnote, " world"
      fragments.size.should eq(3)

      fn = fragments[1]
      fn.footnote_index.should eq(-1)
      fn.footnote_text.should eq("This is a note")
      fn.text.should eq("")
    end

    it "returns a plain fragment when there is no footnote macro" do
      fragments = AsciiDoc::Parser.parse_inline("No footnotes here.")
      fragments.size.should eq(1)
      fragments[0].footnote_index.should eq(0)
    end

    it "handles a footnote at the very start of the text" do
      fragments = AsciiDoc::Parser.parse_inline("footnote:[First] then text")
      fn = fragments[0]
      fn.footnote_index.should eq(-1)
      fn.footnote_text.should eq("First")
    end

    it "handles a footnote at the very end of the text" do
      fragments = AsciiDoc::Parser.parse_inline("Some text footnote:[Last]")
      fn = fragments.last
      fn.footnote_index.should eq(-1)
      fn.footnote_text.should eq("Last")
    end

    it "handles multiple footnotes in the same text" do
      fragments = AsciiDoc::Parser.parse_inline(
        "A footnote:[Alpha] and B footnote:[Beta]"
      )
      fn_frags = fragments.select { |f| f.footnote_index == -1 }
      fn_frags.size.should eq(2)
      fn_frags[0].footnote_text.should eq("Alpha")
      fn_frags[1].footnote_text.should eq("Beta")
    end

    it "handles a footnote with brackets inside the text" do
      fragments = AsciiDoc::Parser.parse_inline("See footnote:[cf. [RFC 1234]] here")
      fn = fragments.find { |f| f.footnote_index == -1 }
      fn.should_not be_nil
      fn.not_nil!.footnote_text.should eq("cf. [RFC 1234]")
    end

    it "handles an empty footnote body" do
      fragments = AsciiDoc::Parser.parse_inline("Text footnote:[] end")
      # An empty body: bracket_end > macro_start is false (bracket_end == macro_start+1)
      # The macro is still parsed; footnote_text is empty.
      fn = fragments.find { |f| f.footnote_index == -1 }
      fn.should_not be_nil
      fn.not_nil!.footnote_text.should eq("")
    end

    it "does not confuse footnote: with a plain word containing 'footnote'" do
      fragments = AsciiDoc::Parser.parse_inline("footnoteworthy content")
      # No footnote fragment should be produced
      fn = fragments.find { |f| f.footnote_index == -1 }
      fn.should be_nil
    end

    it "handles footnoteref: macro as well" do
      fragments = AsciiDoc::Parser.parse_inline("Text footnoteref:[id,Note text] end")
      fn = fragments.find { |f| f.footnote_index == -1 }
      fn.should_not be_nil
      fn.not_nil!.footnote_text.should eq("id,Note text")
    end
  end
end

describe "Footnotes – Converter" do
  it "assigns sequential index 1 to the first footnote" do
    source = <<-ADOC
    = Doc

    == Section

    Text footnote:[First note] here.
    ADOC

    converter = AsciidocPDF::Converter.new
    parser = AsciiDoc::Parser.new(source)
    ast = parser.parse
    converter.convert(ast)

    # The footnote counter should be 1 after conversion.
    converter.footnote_counter.should eq(1)
  end

  it "increments the counter for each footnote across paragraphs" do
    source = <<-ADOC
    = Doc

    == Section

    Para one footnote:[Note A].

    Para two footnote:[Note B] and footnote:[Note C].
    ADOC

    converter = AsciidocPDF::Converter.new
    parser = AsciiDoc::Parser.new(source)
    ast = parser.parse
    converter.convert(ast)

    converter.footnote_counter.should eq(3)
  end

  it "converts a document with footnotes without raising" do
    source = <<-ADOC
    = Footnote Test

    == Introduction

    Crystal is a compiled language footnote:[See https://crystal-lang.org].
    It is statically typed footnote:[Type inference is used extensively].
    ADOC

    # Should not raise
    converter = AsciidocPDF::Converter.convert(source)
    converter.should_not be_nil
    converter.footnote_counter.should eq(2)
  end

  it "produces a valid PDF binary when footnotes are present" do
    source = <<-ADOC
    = PDF Test

    == Body

    A paragraph with a note footnote:[Important detail].
    ADOC

    io = IO::Memory.new
    converter = AsciidocPDF::Converter.convert(source)
    converter.write(io)
    pdf_bytes = io.to_s

    # PDF files start with %PDF-
    pdf_bytes.starts_with?("%PDF-").should be_true
  end

  it "resets page footnotes after flushing" do
    source = <<-ADOC
    = Doc

    == Section

    First footnote:[Note 1].
    ADOC

    converter = AsciidocPDF::Converter.new
    parser = AsciiDoc::Parser.new(source)
    ast = parser.parse
    converter.convert(ast)

    # After conversion, page_footnotes should be empty (flushed).
    converter.page_footnotes.should be_empty
  end

  it "handles a document with no footnotes gracefully" do
    source = <<-ADOC
    = Clean Doc

    == Section

    No footnotes in this document.
    ADOC

    converter = AsciidocPDF::Converter.convert(source)
    converter.footnote_counter.should eq(0)
    converter.page_footnotes.should be_empty
  end
end
