require "../spec_helper"
require "../../src/asciidoc_pdf"

describe "AsciidocPDF::Converter TrueType fonts" do
  describe "Theme TrueType font path properties" do
    it "has nil font paths by default" do
      theme = AsciidocPDF::Theme.new
      theme.base_font_path.should be_nil
      theme.base_font_bold_path.should be_nil
      theme.base_font_italic_path.should be_nil
      theme.base_font_bold_italic_path.should be_nil
      theme.heading_font_path.should be_nil
      theme.code_font_path.should be_nil
    end

    it "allows setting font paths" do
      theme = AsciidocPDF::Theme.new
      theme.base_font_path = "/fonts/regular.ttf"
      theme.base_font_bold_path = "/fonts/bold.ttf"
      theme.base_font_italic_path = "/fonts/italic.ttf"
      theme.base_font_bold_italic_path = "/fonts/bold-italic.ttf"
      theme.heading_font_path = "/fonts/heading.ttf"
      theme.code_font_path = "/fonts/mono.ttf"

      theme.base_font_path.should eq("/fonts/regular.ttf")
      theme.base_font_bold_path.should eq("/fonts/bold.ttf")
      theme.base_font_italic_path.should eq("/fonts/italic.ttf")
      theme.base_font_bold_italic_path.should eq("/fonts/bold-italic.ttf")
      theme.heading_font_path.should eq("/fonts/heading.ttf")
      theme.code_font_path.should eq("/fonts/mono.ttf")
    end
  end

  describe "ThemeLoader YAML font paths" do
    it "loads font paths from YAML fonts section" do
      yaml = <<-YAML
      fonts:
        base: /fonts/regular.ttf
        base_bold: /fonts/bold.ttf
        base_italic: /fonts/italic.ttf
        base_bold_italic: /fonts/bold-italic.ttf
        heading: /fonts/heading.ttf
        code: /fonts/mono.ttf
      YAML

      theme = AsciidocPDF::ThemeLoader.from_yaml(yaml)
      theme.base_font_path.should eq("/fonts/regular.ttf")
      theme.base_font_bold_path.should eq("/fonts/bold.ttf")
      theme.base_font_italic_path.should eq("/fonts/italic.ttf")
      theme.base_font_bold_italic_path.should eq("/fonts/bold-italic.ttf")
      theme.heading_font_path.should eq("/fonts/heading.ttf")
      theme.code_font_path.should eq("/fonts/mono.ttf")
    end

    it "leaves font paths nil when fonts section is absent" do
      yaml = "base:\n  font_size: 12.0\n"
      theme = AsciidocPDF::ThemeLoader.from_yaml(yaml)
      theme.base_font_path.should be_nil
      theme.heading_font_path.should be_nil
      theme.code_font_path.should be_nil
    end

    it "allows partial font path configuration" do
      yaml = <<-YAML
      fonts:
        base: /fonts/regular.ttf
        heading: /fonts/heading.ttf
      YAML

      theme = AsciidocPDF::ThemeLoader.from_yaml(yaml)
      theme.base_font_path.should eq("/fonts/regular.ttf")
      theme.heading_font_path.should eq("/fonts/heading.ttf")
      theme.base_font_bold_path.should be_nil
      theme.code_font_path.should be_nil
    end
  end

  describe "Converter without TrueType fonts" do
    it "truetype_enabled? returns false when no font paths are set" do
      converter = AsciidocPDF::Converter.new
      converter.truetype_enabled?.should be_false
    end

    it "generates PDF without errors using Type1 fallback fonts" do
      source = <<-ADOC
      = Test Document

      == Section One

      A paragraph with *bold*, _italic_, and `mono` text.

      * Item one
      * Item two
      ADOC

      converter = AsciidocPDF::Converter.convert(source)
      converter.warnings.should be_empty

      io = IO::Memory.new
      converter.write(io)
      io.size.should be > 0

      # Verify it's a valid PDF
      io.rewind
      header = Bytes.new(5)
      io.read(header)
      String.new(header).should start_with("%PDF-")
    end

    it "generates PDF with code blocks using Type1 fallback" do
      source = <<-ADOC
      = Code Test

      [source,crystal]
      ----
      def hello
        puts "Hello, World!"
      end
      ----
      ADOC

      converter = AsciidocPDF::Converter.convert(source)
      io = IO::Memory.new
      converter.write(io)
      io.size.should be > 0
    end
  end

  describe "Converter with invalid TrueType font paths" do
    it "adds a warning and falls back to Type1 when font path is invalid" do
      theme = AsciidocPDF::Theme.new
      theme.base_font_path = "/nonexistent/font.ttf"

      converter = AsciidocPDF::Converter.new(theme)
      # Should have a warning about the missing font
      converter.warnings.any? { |w| w.includes?("base") && w.includes?("font") }.should be_true
      # But truetype_enabled? should be false (font not loaded)
      converter.truetype_enabled?.should be_false
    end

    it "still generates valid PDF when font loading fails" do
      theme = AsciidocPDF::Theme.new
      theme.base_font_path = "/nonexistent/font.ttf"

      source = "= Doc\n\nParagraph text.\n"
      converter = AsciidocPDF::Converter.new(theme)
      ast = AsciiDoc::Parser.new(source).parse
      converter.convert(ast)

      io = IO::Memory.new
      converter.write(io)
      io.size.should be > 0

      io.rewind
      header = Bytes.new(5)
      io.read(header)
      String.new(header).should start_with("%PDF-")
    end
  end

  describe "apply_*_font helper methods (via integration)" do
    it "renders headings and paragraphs without font errors" do
      source = <<-ADOC
      = Document Title
      Author Name

      == Chapter One

      First paragraph.

      === Section 1.1

      Nested content.

      == Chapter Two

      Second chapter content.
      ADOC

      converter = AsciidocPDF::Converter.convert(source)
      converter.warnings.should be_empty

      io = IO::Memory.new
      converter.write(io)
      io.size.should be > 0
    end

    it "renders tables with header bold font" do
      source = <<-ADOC
      = Table Test

      |===
      | Header 1 | Header 2

      | Cell 1 | Cell 2
      | Cell 3 | Cell 4
      |===
      ADOC

      converter = AsciidocPDF::Converter.convert(source)
      io = IO::Memory.new
      converter.write(io)
      io.size.should be > 0
    end

    it "renders description list with bold term font" do
      source = <<-ADOC
      = DL Test

      term one::
        Description of term one.

      term two::
        Description of term two.
      ADOC

      converter = AsciidocPDF::Converter.convert(source)
      io = IO::Memory.new
      converter.write(io)
      io.size.should be > 0
    end
  end
end
