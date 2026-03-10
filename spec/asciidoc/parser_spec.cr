require "../spec_helper"
require "../../src/asciidoc"

describe AsciiDoc::Parser do
  describe "#parse - document header" do
    it "parses a document title" do
      source = "= My Document Title\n"
      doc = AsciiDoc::Parser.new(source).parse
      doc.title.should eq("My Document Title")
    end

    it "parses author and email" do
      source = "= Title\nJohn Doe <john@example.com>\n"
      doc = AsciiDoc::Parser.new(source).parse
      doc.title.should eq("Title")
      doc.author.should eq("John Doe")
      doc.email.should eq("john@example.com")
    end

    it "parses document attributes" do
      source = "= Title\n:toc:\n:icons: font\n:source-highlighter: rouge\n"
      doc = AsciiDoc::Parser.new(source).parse
      doc.doc_attributes["toc"].should eq("")
      doc.doc_attributes["icons"].should eq("font")
      doc.doc_attributes["source-highlighter"].should eq("rouge")
    end
  end

  describe "#parse - sections" do
    it "parses level 1 sections" do
      source = "= Title\n\n== Section One\n\nParagraph.\n\n== Section Two\n\nAnother.\n"
      doc = AsciiDoc::Parser.new(source).parse
      doc.children.size.should be >= 2
      first_section = doc.children.find { |c| c.is_a?(AsciiDoc::Section) }
      first_section.should_not be_nil
      first_section.as(AsciiDoc::Section).title.should eq("Section One")
      first_section.as(AsciiDoc::Section).level.should eq(2)
    end

    it "parses nested sections" do
      source = "= Title\n\n== Level 2\n\n=== Level 3\n\nText.\n"
      doc = AsciiDoc::Parser.new(source).parse
      l2 = doc.children.find { |c| c.is_a?(AsciiDoc::Section) }
      l2.should_not be_nil
      l2 = l2.as(AsciiDoc::Section)
      l2.title.should eq("Level 2")
      l3 = l2.children.find { |c| c.is_a?(AsciiDoc::Section) }
      l3.should_not be_nil
      l3.as(AsciiDoc::Section).title.should eq("Level 3")
      l3.as(AsciiDoc::Section).level.should eq(3)
    end

    it "generates section IDs from titles" do
      source = "= Title\n\n== My Great Section\n\nText.\n"
      doc = AsciiDoc::Parser.new(source).parse
      section = doc.children.find { |c| c.is_a?(AsciiDoc::Section) }.as(AsciiDoc::Section)
      section.id.should eq("_my_great_section")
    end
  end

  describe "#parse - paragraphs" do
    it "parses a simple paragraph" do
      source = "= Title\n\n== Section\n\nThis is a paragraph.\n"
      doc = AsciiDoc::Parser.new(source).parse
      section = doc.children.find { |c| c.is_a?(AsciiDoc::Section) }.as(AsciiDoc::Section)
      para = section.children.find { |c| c.is_a?(AsciiDoc::Paragraph) }
      para.should_not be_nil
      para.as(AsciiDoc::Paragraph).text.should eq("This is a paragraph.")
    end

    it "parses multi-line paragraphs" do
      source = "= Title\n\n== S\n\nLine one\nLine two\nLine three\n"
      doc = AsciiDoc::Parser.new(source).parse
      section = doc.children.find { |c| c.is_a?(AsciiDoc::Section) }.as(AsciiDoc::Section)
      para = section.children.find { |c| c.is_a?(AsciiDoc::Paragraph) }.as(AsciiDoc::Paragraph)
      para.text.should contain("Line one")
      para.text.should contain("Line two")
      para.text.should contain("Line three")
    end
  end

  describe "#parse - lists" do
    it "parses an unordered list" do
      source = "= T\n\n== S\n\n* Item one\n* Item two\n* Item three\n"
      doc = AsciiDoc::Parser.new(source).parse
      section = doc.children.find { |c| c.is_a?(AsciiDoc::Section) }.as(AsciiDoc::Section)
      list = section.children.find { |c| c.is_a?(AsciiDoc::List) }
      list.should_not be_nil
      list = list.as(AsciiDoc::List)
      list.list_type.should eq("unordered")
      list.children.size.should eq(3)
      list.children[0].as(AsciiDoc::ListItem).text.should eq("Item one")
    end

    it "parses an ordered list" do
      source = "= T\n\n== S\n\n. First\n. Second\n. Third\n"
      doc = AsciiDoc::Parser.new(source).parse
      section = doc.children.find { |c| c.is_a?(AsciiDoc::Section) }.as(AsciiDoc::Section)
      list = section.children.find { |c| c.is_a?(AsciiDoc::List) }.as(AsciiDoc::List)
      list.list_type.should eq("ordered")
      list.children.size.should eq(3)
    end

    it "parses a description list" do
      source = "= T\n\n== S\n\nTerm 1:: Description 1\nTerm 2:: Description 2\n"
      doc = AsciiDoc::Parser.new(source).parse
      section = doc.children.find { |c| c.is_a?(AsciiDoc::Section) }.as(AsciiDoc::Section)
      list = section.children.find { |c| c.is_a?(AsciiDoc::List) }.as(AsciiDoc::List)
      list.list_type.should eq("description")
      list.children.size.should eq(2)
      list.children[0].as(AsciiDoc::ListItem).term.should eq("Term 1")
      list.children[0].as(AsciiDoc::ListItem).text.should eq("Description 1")
    end
  end

  describe "#parse - blocks" do
    it "parses a source block" do
      source = "= T\n\n== S\n\n[source,crystal]\n----\nputs \"hello\"\n----\n"
      doc = AsciiDoc::Parser.new(source).parse
      section = doc.children.find { |c| c.is_a?(AsciiDoc::Section) }.as(AsciiDoc::Section)
      block = section.children.find { |c| c.is_a?(AsciiDoc::Block) }
      block.should_not be_nil
      block = block.as(AsciiDoc::Block)
      block.content.should contain("puts")
      block.language.should eq("crystal")
    end

    it "parses an admonition paragraph" do
      source = "= T\n\n== S\n\nNOTE: This is important.\n"
      doc = AsciiDoc::Parser.new(source).parse
      section = doc.children.find { |c| c.is_a?(AsciiDoc::Section) }.as(AsciiDoc::Section)
      block = section.children.find { |c| c.is_a?(AsciiDoc::Block) }.as(AsciiDoc::Block)
      block.block_type.should eq("admonition")
      block.admonition_type.should eq("NOTE")
      block.content.should eq("This is important.")
    end

    it "parses a quote block" do
      source = "= T\n\n== S\n\n____\nTo be or not to be.\n____\n"
      doc = AsciiDoc::Parser.new(source).parse
      section = doc.children.find { |c| c.is_a?(AsciiDoc::Section) }.as(AsciiDoc::Section)
      block = section.children.find { |c| c.is_a?(AsciiDoc::Block) }.as(AsciiDoc::Block)
      block.block_type.should eq("quote")
      block.content.should contain("To be or not to be")
    end
  end

  describe "#parse - tables" do
    it "parses a simple table" do
      source = "= T\n\n== S\n\n|===\n| Header 1 | Header 2\n| Cell 1 | Cell 2\n| Cell 3 | Cell 4\n|===\n"
      doc = AsciiDoc::Parser.new(source).parse
      section = doc.children.find { |c| c.is_a?(AsciiDoc::Section) }.as(AsciiDoc::Section)
      table = section.children.find { |c| c.is_a?(AsciiDoc::Table) }
      table.should_not be_nil
      table = table.as(AsciiDoc::Table)
      table.header_rows.size.should eq(1)
      table.body_rows.size.should be >= 1
    end
  end

  describe "#parse - images" do
    it "parses a block image" do
      source = "= T\n\n== S\n\nimage::photo.png[Photo,300,200]\n"
      doc = AsciiDoc::Parser.new(source).parse
      section = doc.children.find { |c| c.is_a?(AsciiDoc::Section) }.as(AsciiDoc::Section)
      img = section.children.find { |c| c.is_a?(AsciiDoc::Image) }.as(AsciiDoc::Image)
      img.target.should eq("photo.png")
      img.alt.should eq("Photo")
      img.width.should eq("300")
      img.height.should eq("200")
    end
  end

  describe "#parse - special blocks" do
    it "parses a page break" do
      source = "= T\n\n== S\n\nBefore.\n\n<<<\n\nAfter.\n"
      doc = AsciiDoc::Parser.new(source).parse
      section = doc.children.find { |c| c.is_a?(AsciiDoc::Section) }.as(AsciiDoc::Section)
      pb = section.children.find { |c| c.is_a?(AsciiDoc::PageBreak) }
      pb.should_not be_nil
    end

    it "parses a thematic break" do
      source = "= T\n\n== S\n\nBefore.\n\n'''\n\nAfter.\n"
      doc = AsciiDoc::Parser.new(source).parse
      section = doc.children.find { |c| c.is_a?(AsciiDoc::Section) }.as(AsciiDoc::Section)
      tb = section.children.find { |c| c.is_a?(AsciiDoc::ThematicBreak) }
      tb.should_not be_nil
    end

    it "parses a TOC macro" do
      source = "= T\n:toc:\n\ntoc::[]\n\n== Section\n\nText.\n"
      doc = AsciiDoc::Parser.new(source).parse
      toc = doc.children.find { |c| c.is_a?(AsciiDoc::Toc) }
      toc.should_not be_nil
    end
  end

  describe ".parse_inline" do
    it "parses bold text" do
      fragments = AsciiDoc::Parser.parse_inline("This is *bold* text")
      bold_frag = fragments.find { |f| f.bold }
      bold_frag.should_not be_nil
      bold_frag.not_nil!.text.should eq("bold")
    end

    it "parses italic text" do
      fragments = AsciiDoc::Parser.parse_inline("This is _italic_ text")
      italic_frag = fragments.find { |f| f.italic }
      italic_frag.should_not be_nil
      italic_frag.not_nil!.text.should eq("italic")
    end

    it "parses monospace text" do
      fragments = AsciiDoc::Parser.parse_inline("Use `code` here")
      mono_frag = fragments.find { |f| f.mono }
      mono_frag.should_not be_nil
      mono_frag.not_nil!.text.should eq("code")
    end

    it "parses links" do
      fragments = AsciiDoc::Parser.parse_inline("Visit https://example.com for info")
      link_frag = fragments.find { |f| !f.link.empty? }
      link_frag.should_not be_nil
      link_frag.not_nil!.link.should eq("https://example.com")
    end

    it "returns plain text when no markup" do
      fragments = AsciiDoc::Parser.parse_inline("Just plain text")
      fragments.size.should eq(1)
      fragments[0].text.should eq("Just plain text")
    end
  end
end
