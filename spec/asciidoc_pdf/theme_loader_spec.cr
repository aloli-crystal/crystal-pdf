require "../spec_helper"
require "../../src/asciidoc_pdf"

describe AsciidocPDF::ThemeLoader do
  describe ".from_yaml" do
    it "returns a Theme with default values when given empty YAML" do
      theme = AsciidocPDF::ThemeLoader.from_yaml("{}")
      theme.page_width.should eq(595.28)
      theme.base_font_family.should eq("Helvetica")
      theme.base_font_size.should eq(10.5)
    end

    it "overrides page dimensions" do
      yaml = <<-YAML
      page:
        width: 612.0
        height: 792.0
      YAML
      theme = AsciidocPDF::ThemeLoader.from_yaml(yaml)
      theme.page_width.should eq(612.0)
      theme.page_height.should eq(792.0)
    end

    it "overrides page margins" do
      yaml = <<-YAML
      page:
        margin:
          top: 54.0
          right: 54.0
          bottom: 54.0
          left: 54.0
      YAML
      theme = AsciidocPDF::ThemeLoader.from_yaml(yaml)
      theme.page_margin_top.should eq(54.0)
      theme.page_margin_right.should eq(54.0)
      theme.page_margin_bottom.should eq(54.0)
      theme.page_margin_left.should eq(54.0)
    end

    it "overrides base font settings" do
      yaml = <<-YAML
      base:
        font_family: Times-Roman
        font_size: 12.0
        font_color: [0.1, 0.1, 0.1]
        line_height: 1.5
      YAML
      theme = AsciidocPDF::ThemeLoader.from_yaml(yaml)
      theme.base_font_family.should eq("Times-Roman")
      theme.base_font_size.should eq(12.0)
      theme.base_font_color.should eq({0.1, 0.1, 0.1})
      theme.base_line_height.should eq(1.5)
    end

    it "overrides heading settings" do
      yaml = <<-YAML
      heading:
        font_family: Helvetica-Bold
        h1_font_size: 32.0
        h2_font_size: 24.0
        margin_top: 24.0
        margin_bottom: 16.0
      YAML
      theme = AsciidocPDF::ThemeLoader.from_yaml(yaml)
      theme.heading_font_family.should eq("Helvetica-Bold")
      theme.heading_h1_font_size.should eq(32.0)
      theme.heading_h2_font_size.should eq(24.0)
      theme.heading_margin_top.should eq(24.0)
      theme.heading_margin_bottom.should eq(16.0)
    end

    it "overrides code block settings" do
      yaml = <<-YAML
      code:
        font_family: Courier-Bold
        font_size: 10.0
        background_color: [0.9, 0.9, 0.9]
        padding: 12.0
      YAML
      theme = AsciidocPDF::ThemeLoader.from_yaml(yaml)
      theme.code_font_family.should eq("Courier-Bold")
      theme.code_font_size.should eq(10.0)
      theme.code_background_color.should eq({0.9, 0.9, 0.9})
      theme.code_padding.should eq(12.0)
    end

    it "overrides list settings" do
      yaml = <<-YAML
      list:
        indent: 30.0
        item_spacing: 8.0
        ulist_marker: "-"
      YAML
      theme = AsciidocPDF::ThemeLoader.from_yaml(yaml)
      theme.list_indent.should eq(30.0)
      theme.list_item_spacing.should eq(8.0)
      theme.ulist_marker.should eq("-")
    end

    it "overrides table settings" do
      yaml = <<-YAML
      table:
        border_color: [0.5, 0.5, 0.5]
        border_width: 1.0
        cell_padding: 8.0
      YAML
      theme = AsciidocPDF::ThemeLoader.from_yaml(yaml)
      theme.table_border_color.should eq({0.5, 0.5, 0.5})
      theme.table_border_width.should eq(1.0)
      theme.table_cell_padding.should eq(8.0)
    end

    it "overrides admonition background colors" do
      yaml = <<-YAML
      admonition:
        background_color:
          NOTE: [0.9, 0.9, 1.0]
          TIP: [0.9, 1.0, 0.9]
      YAML
      theme = AsciidocPDF::ThemeLoader.from_yaml(yaml)
      theme.admonition_background_color["NOTE"].should eq({0.9, 0.9, 1.0})
      theme.admonition_background_color["TIP"].should eq({0.9, 1.0, 0.9})
      # Other types should keep defaults
      theme.admonition_background_color["WARNING"].should eq({1.0, 0.97, 0.93})
    end

    it "overrides TOC settings" do
      yaml = <<-YAML
      toc:
        title: "Sommaire"
        font_size: 11.0
        indent: 20.0
        dot_leader: false
      YAML
      theme = AsciidocPDF::ThemeLoader.from_yaml(yaml)
      theme.toc_title.should eq("Sommaire")
      theme.toc_font_size.should eq(11.0)
      theme.toc_indent.should eq(20.0)
      theme.toc_dot_leader.should be_false
    end

    it "overrides title page settings" do
      yaml = <<-YAML
      title_page:
        enabled: false
        font_size: 36.0
      YAML
      theme = AsciidocPDF::ThemeLoader.from_yaml(yaml)
      theme.title_page_enabled.should be_false
      theme.title_page_font_size.should eq(36.0)
    end

    it "ignores unknown keys silently" do
      yaml = <<-YAML
      unknown_section:
        unknown_key: value
      base:
        font_size: 11.0
        unknown_property: ignored
      YAML
      theme = AsciidocPDF::ThemeLoader.from_yaml(yaml)
      theme.base_font_size.should eq(11.0)
    end

    it "handles integer values for float properties" do
      yaml = <<-YAML
      base:
        font_size: 12
        line_height: 1
      YAML
      theme = AsciidocPDF::ThemeLoader.from_yaml(yaml)
      theme.base_font_size.should eq(12.0)
      theme.base_line_height.should eq(1.0)
    end
  end

  describe ".load" do
    it "loads a theme from a YAML file" do
      # Write a temporary theme file
      path = "/tmp/test-theme-#{Process.pid}.yml"
      File.write(path, "base:\n  font_size: 13.0\n")
      begin
        theme = AsciidocPDF::ThemeLoader.load(path)
        theme.base_font_size.should eq(13.0)
      ensure
        File.delete(path)
      end
    end

    it "raises File::NotFoundError for missing files" do
      expect_raises(File::NotFoundError) do
        AsciidocPDF::ThemeLoader.load("/nonexistent/theme.yml")
      end
    end

    it "loads the built-in default theme file" do
      path = AsciidocPDF::ThemeLoader.default_theme_path
      File.exists?(path).should be_true
      theme = AsciidocPDF::ThemeLoader.load(path)
      theme.page_width.should eq(595.28)
      theme.base_font_size.should eq(10.5)
      theme.toc_title.should eq("Table of Contents")
    end
  end

  describe "integration with Converter" do
    it "converts a document using a custom YAML theme" do
      yaml = <<-YAML
      base:
        font_size: 12.0
      heading:
        h1_font_size: 30.0
      YAML
      theme = AsciidocPDF::ThemeLoader.from_yaml(yaml)
      source = "= Test\n\n== Section\n\nHello world.\n"
      converter = AsciidocPDF::Converter.convert(source, theme)
      converter.should_not be_nil
    end
  end
end
