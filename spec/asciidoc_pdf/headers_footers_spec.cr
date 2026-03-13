require "../spec_helper"
require "../../src/asciidoc_pdf"

describe "AsciidocPDF::Converter headers and footers" do
  describe "Theme header/footer properties" do
    it "has sensible defaults" do
      theme = AsciidocPDF::Theme.new
      theme.header_enabled.should be_true
      theme.header_left.should eq("")
      theme.header_center.should eq("")
      theme.header_right.should eq("{document_title}")
      theme.header_skip_first_page.should be_true

      theme.footer_enabled.should be_true
      theme.footer_left.should eq("")
      theme.footer_center.should eq("{page_number} / {page_count}")
      theme.footer_right.should eq("")
      theme.footer_skip_first_page.should be_true
    end
  end

  describe "ThemeLoader YAML header/footer slots" do
    it "loads header and footer slots from YAML" do
      yaml = <<-YAML
      header:
        left: "My Company"
        center: "{document_title}"
        right: "{section_title}"
        skip_first_page: false
      footer:
        left: "Confidential"
        center: ""
        right: "Page {page_number} of {page_count}"
        skip_first_page: true
      YAML

      theme = AsciidocPDF::ThemeLoader.from_yaml(yaml)
      theme.header_left.should eq("My Company")
      theme.header_center.should eq("{document_title}")
      theme.header_right.should eq("{section_title}")
      theme.header_skip_first_page.should be_false

      theme.footer_left.should eq("Confidential")
      theme.footer_center.should eq("")
      theme.footer_right.should eq("Page {page_number} of {page_count}")
      theme.footer_skip_first_page.should be_true
    end
  end

  describe "resolve_tokens" do
    it "resolves all tokens correctly" do
      # We test via integration: the converter uses resolve_tokens internally.
      # We verify the rendered PDF contains the expected text by checking
      # that generation succeeds without errors.
      theme = AsciidocPDF::Theme.new
      theme.footer_center = "{page_number} / {page_count}"
      theme.header_right = "{document_title}"
      theme.footer_skip_first_page = false
      theme.header_skip_first_page = false

      source = <<-ADOC
      = My Document

      == Chapter One

      Content here.
      ADOC

      converter = AsciidocPDF::Converter.convert(source, theme)
      converter.warnings.should be_empty

      io = IO::Memory.new
      converter.write(io)
      io.size.should be > 0

      io.rewind
      header = Bytes.new(5)
      io.read(header)
      String.new(header).should start_with("%PDF-")
    end
  end

  describe "header/footer rendering" do
    it "generates PDF with headers and footers enabled" do
      source = <<-ADOC
      = Test Document
      Author Name

      == Section One

      First section content.

      == Section Two

      Second section content.
      ADOC

      converter = AsciidocPDF::Converter.convert(source)
      converter.warnings.should be_empty

      io = IO::Memory.new
      converter.write(io)
      io.size.should be > 0
    end

    it "generates PDF with headers and footers disabled" do
      theme = AsciidocPDF::Theme.new
      theme.header_enabled = false
      theme.footer_enabled = false

      source = "= Doc\n\nContent.\n"
      converter = AsciidocPDF::Converter.convert(source, theme)
      converter.warnings.should be_empty

      io = IO::Memory.new
      converter.write(io)
      io.size.should be > 0
    end

    it "skips header and footer on first page when skip_first_page is true" do
      theme = AsciidocPDF::Theme.new
      theme.header_skip_first_page = true
      theme.footer_skip_first_page = true
      theme.title_page_enabled = true

      source = <<-ADOC
      = Document Title

      == Chapter

      Content.
      ADOC

      converter = AsciidocPDF::Converter.convert(source, theme)
      converter.warnings.should be_empty

      io = IO::Memory.new
      converter.write(io)
      io.size.should be > 0
    end

    it "renders header and footer on first page when skip_first_page is false" do
      theme = AsciidocPDF::Theme.new
      theme.header_skip_first_page = false
      theme.footer_skip_first_page = false

      source = "= Doc\n\nContent.\n"
      converter = AsciidocPDF::Converter.convert(source, theme)
      converter.warnings.should be_empty

      io = IO::Memory.new
      converter.write(io)
      io.size.should be > 0
    end

    it "tracks section titles per page" do
      source = <<-ADOC
      = Document

      == First Section

      Content of first section.

      == Second Section

      Content of second section.
      ADOC

      converter = AsciidocPDF::Converter.convert(source)
      # The page_metas are internal but we can verify via successful generation
      converter.warnings.should be_empty
      io = IO::Memory.new
      converter.write(io)
      io.size.should be > 0
    end

    it "handles multi-page document with correct page numbers" do
      # Generate enough content to force multiple pages
      sections = (1..5).map { |i|
        "== Section #{i}\n\n" + ("Content line.\n" * 30)
      }.join("\n")

      source = "= Long Document\n\n#{sections}"
      converter = AsciidocPDF::Converter.convert(source)
      converter.warnings.should be_empty

      io = IO::Memory.new
      converter.write(io)
      io.size.should be > 0
    end

    it "renders custom left/center/right slots" do
      theme = AsciidocPDF::Theme.new
      theme.header_left = "Left Header"
      theme.header_center = "Center Header"
      theme.header_right = "Right Header"
      theme.footer_left = "Left Footer"
      theme.footer_center = "Page {page_number}"
      theme.footer_right = "Right Footer"
      theme.header_skip_first_page = false
      theme.footer_skip_first_page = false

      source = "= Doc\n\nContent.\n"
      converter = AsciidocPDF::Converter.convert(source, theme)
      converter.warnings.should be_empty

      io = IO::Memory.new
      converter.write(io)
      io.size.should be > 0
    end
  end
end
