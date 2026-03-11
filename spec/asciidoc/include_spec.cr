require "../spec_helper"
require "../../src/asciidoc"
require "file_utils"

# Helper to create temp files and clean them up
private def with_temp_dir(&block : String -> Nil)
  dir = "/tmp/asciidoc_include_test_#{Process.pid}"
  Dir.mkdir_p(dir)
  begin
    block.call(dir)
  ensure
    FileUtils.rm_rf(dir) if Dir.exists?(dir)
  end
end

describe "AsciiDoc::Parser include:: directive" do
  describe "basic inclusion" do
    it "includes a simple file" do
      with_temp_dir do |dir|
        File.write("#{dir}/chapter.adoc", "== Included Chapter\n\nIncluded content.\n")
        source = "= Main Doc\n\ninclude::#{dir}/chapter.adoc[]\n"
        doc = AsciiDoc::Parser.new(source).parse
        section = doc.children.find { |c| c.is_a?(AsciiDoc::Section) }
        section.should_not be_nil
        section.as(AsciiDoc::Section).title.should eq("Included Chapter")
      end
    end

    it "includes a file with relative path when base_dir is set" do
      with_temp_dir do |dir|
        File.write("#{dir}/part.adoc", "== Part One\n\nPart content.\n")
        File.write("#{dir}/main.adoc", "= Main\n\ninclude::part.adoc[]\n")
        source = File.read("#{dir}/main.adoc")
        doc = AsciiDoc::Parser.new(source, base_dir: dir).parse
        section = doc.children.find { |c| c.is_a?(AsciiDoc::Section) }
        section.should_not be_nil
        section.as(AsciiDoc::Section).title.should eq("Part One")
      end
    end

    it "includes multiple files in sequence" do
      with_temp_dir do |dir|
        # Use level-2 sections (==) so both appear as top-level children of the document
        File.write("#{dir}/ch1.adoc", "== Chapter 1\n\nFirst.\n")
        File.write("#{dir}/ch2.adoc", "== Chapter 2\n\nSecond.\n")
        source = "= Book\n\ninclude::#{dir}/ch1.adoc[]\n\ninclude::#{dir}/ch2.adoc[]\n"
        doc = AsciiDoc::Parser.new(source).parse
        # Both sections are level-2; the parser nests them under the document root.
        # Find all sections recursively.
        all_sections = [] of AsciiDoc::Section
        doc.children.each do |child|
          if s = child.as?(AsciiDoc::Section)
            all_sections << s
            s.children.each do |sub|
              all_sections << sub.as(AsciiDoc::Section) if sub.is_a?(AsciiDoc::Section)
            end
          end
        end
        all_sections.map(&.title).should contain("Chapter 1")
        all_sections.map(&.title).should contain("Chapter 2")
      end
    end

    it "includes a file with paragraphs" do
      with_temp_dir do |dir|
        File.write("#{dir}/intro.adoc", "This is the introduction paragraph.\n")
        source = "= Doc\n\n== Section\n\ninclude::#{dir}/intro.adoc[]\n"
        doc = AsciiDoc::Parser.new(source).parse
        section = doc.children.find { |c| c.is_a?(AsciiDoc::Section) }.as(AsciiDoc::Section)
        para = section.children.find { |c| c.is_a?(AsciiDoc::Paragraph) }
        para.should_not be_nil
        para.as(AsciiDoc::Paragraph).text.should contain("introduction")
      end
    end
  end

  describe "nested inclusion" do
    it "resolves nested includes" do
      with_temp_dir do |dir|
        File.write("#{dir}/leaf.adoc", "=== Leaf Section\n\nLeaf content.\n")
        File.write("#{dir}/middle.adoc", "== Middle Section\n\ninclude::leaf.adoc[]\n")
        source = "= Root\n\ninclude::#{dir}/middle.adoc[]\n"
        doc = AsciiDoc::Parser.new(source).parse
        middle = doc.children.find { |c| c.is_a?(AsciiDoc::Section) }.as(AsciiDoc::Section)
        middle.title.should eq("Middle Section")
        leaf = middle.children.find { |c| c.is_a?(AsciiDoc::Section) }
        leaf.should_not be_nil
        leaf.as(AsciiDoc::Section).title.should eq("Leaf Section")
      end
    end
  end

  describe "error handling" do
    it "raises File::NotFoundError for missing include files" do
      source = "= Doc\n\ninclude::/nonexistent/file.adoc[]\n"
      expect_raises(File::NotFoundError) do
        AsciiDoc::Parser.new(source).parse
      end
    end

    it "raises an error on circular inclusion" do
      with_temp_dir do |dir|
        # a.adoc includes b.adoc which includes a.adoc
        File.write("#{dir}/a.adoc", "include::b.adoc[]\n")
        File.write("#{dir}/b.adoc", "include::a.adoc[]\n")
        source = "= Doc\n\ninclude::#{dir}/a.adoc[]\n"
        expect_raises(Exception, /[Cc]ircular/) do
          AsciiDoc::Parser.new(source).parse
        end
      end
    end
  end

  describe "non-include lines are unaffected" do
    it "does not alter lines without include::" do
      source = "= Doc\n\n== Section\n\nNormal paragraph.\n"
      doc = AsciiDoc::Parser.new(source).parse
      section = doc.children.find { |c| c.is_a?(AsciiDoc::Section) }.as(AsciiDoc::Section)
      para = section.children.find { |c| c.is_a?(AsciiDoc::Paragraph) }.as(AsciiDoc::Paragraph)
      para.text.should eq("Normal paragraph.")
    end

    it "does not treat inline include mentions as directives" do
      source = "= Doc\n\n== Section\n\nSee include::file.adoc[] for details.\n"
      # This line starts with "See", not "include::", so it should be a paragraph
      # Actually the regex is anchored to start of line, so this should be a paragraph
      doc = AsciiDoc::Parser.new(source).parse
      section = doc.children.find { |c| c.is_a?(AsciiDoc::Section) }.as(AsciiDoc::Section)
      para = section.children.find { |c| c.is_a?(AsciiDoc::Paragraph) }
      para.should_not be_nil
    end
  end
end
