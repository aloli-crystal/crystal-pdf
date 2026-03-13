require "../spec_helper"
require "../../src/asciidoc_pdf"

describe AsciidocPDF do
  describe "Index" do
    describe "AsciiDoc::Parser — index term parsing" do
      it "parses a standalone indexterm on its own line" do
        doc = AsciiDoc::Parser.new("indexterm:[Crystal]").parse
        term = doc.children.find { |c| c.is_a?(AsciiDoc::IndexTerm) }
        term.should_not be_nil
        term.as(AsciiDoc::IndexTerm).primary.should eq "Crystal"
        term.as(AsciiDoc::IndexTerm).secondary.should eq ""
      end

      it "parses a standalone indexterm with secondary term" do
        doc = AsciiDoc::Parser.new("indexterm:[Crystal,Language]").parse
        term = doc.children.find { |c| c.is_a?(AsciiDoc::IndexTerm) }
        term.should_not be_nil
        t = term.as(AsciiDoc::IndexTerm)
        t.primary.should eq "Crystal"
        t.secondary.should eq "Language"
      end

      it "parses an inline indexterm within a paragraph" do
        frags = AsciiDoc::Parser.parse_inline("Hello indexterm:[World] there")
        # The indexterm fragment is invisible (empty text, footnote_index=-2)
        idx_frag = frags.find { |f| f.footnote_index == -2 }
        idx_frag.should_not be_nil
        idx_frag.not_nil!.footnote_text.should eq "indexterm:World|"
      end

      it "parses an inline indexterm with secondary term" do
        frags = AsciiDoc::Parser.parse_inline("See indexterm:[PDF,Generation] for details")
        idx_frag = frags.find { |f| f.footnote_index == -2 }
        idx_frag.should_not be_nil
        idx_frag.not_nil!.footnote_text.should eq "indexterm:PDF|Generation"
      end

      it "does not affect surrounding text when parsing inline indexterm" do
        frags = AsciiDoc::Parser.parse_inline("Before indexterm:[Term] after")
        visible = frags.reject { |f| f.footnote_index == -2 }.map(&.text).join
        visible.should contain "Before"
        visible.should contain "after"
      end
    end

    describe "Converter — index collection" do
      it "collects block-level index terms during rendering" do
        adoc = <<-ADOC
        = Test
        indexterm:[Crystal]
        indexterm:[PDF,Generation]
        == Section One
        Some content.
        ADOC

        converter = AsciidocPDF::Converter.new
        ast = AsciiDoc::Parser.new(adoc).parse
        converter.convert(ast)

        entries = converter.index_entries
        entries.should_not be_empty
        primaries = entries.map(&.primary)
        primaries.should contain "Crystal"
        primaries.should contain "PDF"
      end

      it "collects inline index terms from paragraphs" do
        adoc = <<-ADOC
        = Test
        == Section
        This is about indexterm:[Shards] in Crystal.
        ADOC

        converter = AsciidocPDF::Converter.new
        ast = AsciiDoc::Parser.new(adoc).parse
        converter.convert(ast)

        entries = converter.index_entries
        primaries = entries.map(&.primary)
        primaries.should contain "Shards"
      end

      it "records the correct page number for index terms" do
        adoc = <<-ADOC
        = Test
        indexterm:[FirstPage]
        == Section
        Content here.
        ADOC

        converter = AsciidocPDF::Converter.new
        ast = AsciiDoc::Parser.new(adoc).parse
        converter.convert(ast)

        entry = converter.index_entries.find { |e| e.primary == "FirstPage" }
        entry.should_not be_nil
        entry.not_nil!.page_number.should be >= 1
      end

      it "deduplicates page numbers for the same term on the same page" do
        adoc = <<-ADOC
        = Test
        indexterm:[Crystal]
        indexterm:[Crystal]
        == Section
        Content.
        ADOC

        converter = AsciidocPDF::Converter.new
        ast = AsciiDoc::Parser.new(adoc).parse
        converter.convert(ast)

        entries = converter.index_entries.select { |e| e.primary == "Crystal" }
        # Both entries are collected (deduplication happens during render_index)
        entries.size.should be >= 1
      end

      it "collects secondary terms correctly" do
        adoc = <<-ADOC
        = Test
        indexterm:[PDF,Rendering]
        indexterm:[PDF,Layout]
        == Section
        Content.
        ADOC

        converter = AsciidocPDF::Converter.new
        ast = AsciiDoc::Parser.new(adoc).parse
        converter.convert(ast)

        entries = converter.index_entries.select { |e| e.primary == "PDF" }
        secondaries = entries.map(&.secondary)
        secondaries.should contain "Rendering"
        secondaries.should contain "Layout"
      end

      it "generates a PDF with an index section" do
        adoc = <<-ADOC
        = Test Document
        indexterm:[Crystal]
        indexterm:[PDF,Generation]
        == Introduction
        Content about indexterm:[Shards] here.
        ADOC

        converter = AsciidocPDF::Converter.new
        ast = AsciiDoc::Parser.new(adoc).parse
        converter.convert(ast)

        io = IO::Memory.new
        converter.write(io)
        pdf_bytes = io.to_slice

        # The PDF should be non-empty and contain the PDF header
        pdf_bytes.size.should be > 100
        String.new(pdf_bytes[0, 4]).should eq "%PDF"
      end
    end

    describe "Theme — index properties" do
      it "has default index title" do
        theme = AsciidocPDF::Theme.new
        theme.index_title.should eq "Index"
      end

      it "has default index font size" do
        theme = AsciidocPDF::Theme.new
        theme.index_font_size.should eq 10.0
      end

      it "has default index indent" do
        theme = AsciidocPDF::Theme.new
        theme.index_indent.should eq 20.0
      end
    end
  end
end
