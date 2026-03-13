require "../spec_helper"
require "../../src/asciidoc_pdf"

describe "AsciidocPDF cross-references" do
  describe "AsciiDoc::Parser anchor detection" do
    it "parses an explicit anchor on its own line" do
      source = <<-ADOC
      = Doc

      [[my-anchor]]

      Some paragraph.
      ADOC

      parser = AsciiDoc::Parser.new(source)
      ast = parser.parse

      anchors = [] of AsciiDoc::Anchor
      ast.children.each do |child|
        anchors << child if child.is_a?(AsciiDoc::Anchor)
      end
      anchors.size.should eq(1)
      anchors.first.anchor_id.should eq("my-anchor")
    end

    it "parses a cross-reference inline fragment" do
      text = "See <<section-one>> for details."
      frags = AsciiDoc::Parser.parse_inline(text)

      cross_ref = frags.find { |f| !f.cross_ref_target.empty? }
      cross_ref.should_not be_nil
      cross_ref.not_nil!.cross_ref_target.should eq("section-one")
      cross_ref.not_nil!.cross_ref_display.should eq("")
      cross_ref.not_nil!.text.should eq("section-one")
    end

    it "parses a cross-reference with display text" do
      text = "See <<section-one,Section One>> for details."
      frags = AsciiDoc::Parser.parse_inline(text)

      cross_ref = frags.find { |f| !f.cross_ref_target.empty? }
      cross_ref.should_not be_nil
      cross_ref.not_nil!.cross_ref_target.should eq("section-one")
      cross_ref.not_nil!.cross_ref_display.should eq("Section One")
      cross_ref.not_nil!.text.should eq("Section One")
    end

    it "parses multiple cross-references in one paragraph" do
      text = "See <<ch1>> and <<ch2,Chapter Two>>."
      frags = AsciiDoc::Parser.parse_inline(text)

      cross_refs = frags.select { |f| !f.cross_ref_target.empty? }
      cross_refs.size.should eq(2)
      cross_refs[0].cross_ref_target.should eq("ch1")
      cross_refs[1].cross_ref_target.should eq("ch2")
      cross_refs[1].cross_ref_display.should eq("Chapter Two")
    end

    it "auto-generates section IDs from titles" do
      source = <<-ADOC
      = Doc

      == My Section Title

      Content.
      ADOC

      parser = AsciiDoc::Parser.new(source)
      ast = parser.parse

      section = ast.children.find { |c| c.is_a?(AsciiDoc::Section) }
      section.should_not be_nil
      section.as(AsciiDoc::Section).id.should eq("_my_section_title")
    end

    it "uses explicit ID when provided in section title" do
      source = <<-ADOC
      = Doc

      == [[custom-id]] My Section

      Content.
      ADOC

      parser = AsciiDoc::Parser.new(source)
      ast = parser.parse

      section = ast.children.find { |c| c.is_a?(AsciiDoc::Section) }
      section.should_not be_nil
      section.as(AsciiDoc::Section).id.should eq("custom-id")
    end
  end

  describe "Converter#resolve_cross_ref" do
    it "resolves a known section anchor" do
      source = <<-ADOC
      = Doc

      == Introduction

      Content.
      ADOC

      converter = AsciidocPDF::Converter.convert(source)
      display, page_num = converter.resolve_cross_ref("_introduction")
      display.should eq("Introduction")
      page_num.should be > 0
    end

    it "returns target as display text for unknown anchor" do
      source = "= Doc\n\nContent.\n"
      converter = AsciidocPDF::Converter.convert(source)
      display, page_num = converter.resolve_cross_ref("unknown-anchor")
      display.should eq("unknown-anchor")
      page_num.should eq(0)
    end

    it "uses display_override when provided" do
      source = <<-ADOC
      = Doc

      == Chapter One

      Content.
      ADOC

      converter = AsciidocPDF::Converter.convert(source)
      display, _ = converter.resolve_cross_ref("_chapter_one", "Custom Display")
      display.should eq("Custom Display")
    end

    it "resolves explicit anchors" do
      source = <<-ADOC
      = Doc

      [[my-anchor]]

      Some content after the anchor.
      ADOC

      converter = AsciidocPDF::Converter.convert(source)
      display, page_num = converter.resolve_cross_ref("my-anchor")
      display.should eq("my-anchor")
      page_num.should be > 0
    end
  end

  describe "Cross-reference rendering integration" do
    it "renders a document with cross-references without errors" do
      source = <<-ADOC
      = Document with Cross-References

      == Introduction

      See <<_methods,the methods section>> for details.

      == Methods

      This is the methods section. See <<_introduction>> for background.
      ADOC

      converter = AsciidocPDF::Converter.convert(source)
      converter.warnings.should be_empty

      io = IO::Memory.new
      converter.write(io)
      io.size.should be > 0

      io.rewind
      header = Bytes.new(5)
      io.read(header)
      String.new(header).should start_with("%PDF-")
    end

    it "renders cross-refs with explicit anchors" do
      source = <<-ADOC
      = Doc

      [[intro]]

      == Introduction

      See <<appendix-a,Appendix A>> for more.

      [[appendix-a]]

      == Appendix A

      Appendix content.
      ADOC

      converter = AsciidocPDF::Converter.convert(source)
      converter.warnings.should be_empty

      io = IO::Memory.new
      converter.write(io)
      io.size.should be > 0
    end

    it "handles unresolved cross-references gracefully" do
      source = <<-ADOC
      = Doc

      == Chapter

      See <<non-existent-section>> for details.
      ADOC

      converter = AsciidocPDF::Converter.convert(source)
      # Should not raise; unresolved refs render as plain text
      converter.warnings.should be_empty

      io = IO::Memory.new
      converter.write(io)
      io.size.should be > 0
    end
  end
end
