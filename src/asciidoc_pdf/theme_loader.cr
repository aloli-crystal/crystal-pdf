require "yaml"

module AsciidocPDF
  # Loads a Theme from a YAML file.
  #
  # The YAML format mirrors the asciidoctor-pdf theming system.
  # Unknown keys are silently ignored, and missing keys fall back
  # to the default Theme values.
  #
  # Example usage:
  #
  #   theme = ThemeLoader.load("my-theme.yml")
  #   converter = Converter.convert(source, theme)
  #
  class ThemeLoader
    # Loads a theme from the given YAML file path.
    # Raises `File::NotFoundError` if the file does not exist.
    # Raises `YAML::ParseException` if the YAML is malformed.
    def self.load(path : String) : Theme
      raise File::NotFoundError.new("Theme file not found: #{path}", file: path) unless File.exists?(path)
      yaml_content = File.read(path)
      from_yaml(yaml_content)
    end

    # Parses a YAML string and returns a populated Theme.
    def self.from_yaml(yaml_content : String) : Theme
      theme = Theme.new
      data = YAML.parse(yaml_content)
      apply(theme, data)
      theme
    end

    # Returns the path to the built-in default theme file.
    def self.default_theme_path : String
      File.join(File.dirname(__FILE__), "..", "..", "themes", "default-theme.yml")
    end

    private def self.apply(theme : Theme, data : YAML::Any) : Nil
      return unless data.as_h?

      # ----- Page -----
      if page = data["page"]?
        theme.page_width = float(page["width"]?) if page["width"]?
        theme.page_height = float(page["height"]?) if page["height"]?
        if margin = page["margin"]?
          theme.page_margin_top = float(margin["top"]?) if margin["top"]?
          theme.page_margin_right = float(margin["right"]?) if margin["right"]?
          theme.page_margin_bottom = float(margin["bottom"]?) if margin["bottom"]?
          theme.page_margin_left = float(margin["left"]?) if margin["left"]?
        end
      end

      # ----- TrueType Font Paths -----
      if fonts = data["fonts"]?
        theme.base_font_path = str(fonts["base"]?) if fonts["base"]?
        theme.base_font_bold_path = str(fonts["base_bold"]?) if fonts["base_bold"]?
        theme.base_font_italic_path = str(fonts["base_italic"]?) if fonts["base_italic"]?
        theme.base_font_bold_italic_path = str(fonts["base_bold_italic"]?) if fonts["base_bold_italic"]?
        theme.heading_font_path = str(fonts["heading"]?) if fonts["heading"]?
        theme.code_font_path = str(fonts["code"]?) if fonts["code"]?
      end

      # ----- Base Font -----
      if base = data["base"]?
        theme.base_font_family = str(base["font_family"]?) if base["font_family"]?
        theme.base_font_size = float(base["font_size"]?) if base["font_size"]?
        theme.base_font_color = color(base["font_color"]?) if base["font_color"]?
        theme.base_line_height = float(base["line_height"]?) if base["line_height"]?
      end

      # ----- Heading -----
      if heading = data["heading"]?
        theme.heading_font_family = str(heading["font_family"]?) if heading["font_family"]?
        theme.heading_font_color = color(heading["font_color"]?) if heading["font_color"]?
        theme.heading_font_style = str(heading["font_style"]?) if heading["font_style"]?
        theme.heading_margin_top = float(heading["margin_top"]?) if heading["margin_top"]?
        theme.heading_margin_bottom = float(heading["margin_bottom"]?) if heading["margin_bottom"]?
        theme.heading_h1_font_size = float(heading["h1_font_size"]?) if heading["h1_font_size"]?
        theme.heading_h2_font_size = float(heading["h2_font_size"]?) if heading["h2_font_size"]?
        theme.heading_h3_font_size = float(heading["h3_font_size"]?) if heading["h3_font_size"]?
        theme.heading_h4_font_size = float(heading["h4_font_size"]?) if heading["h4_font_size"]?
        theme.heading_h5_font_size = float(heading["h5_font_size"]?) if heading["h5_font_size"]?
        theme.heading_h6_font_size = float(heading["h6_font_size"]?) if heading["h6_font_size"]?
      end

      # ----- Title Page -----
      if tp = data["title_page"]?
        theme.title_page_enabled = bool(tp["enabled"]?) if tp["enabled"]?
        theme.title_page_font_size = float(tp["font_size"]?) if tp["font_size"]?
        theme.title_page_font_color = color(tp["font_color"]?) if tp["font_color"]?
        theme.title_page_subtitle_font_size = float(tp["subtitle_font_size"]?) if tp["subtitle_font_size"]?
        theme.title_page_author_font_size = float(tp["author_font_size"]?) if tp["author_font_size"]?
        theme.title_page_revision_font_size = float(tp["revision_font_size"]?) if tp["revision_font_size"]?
      end

      # ----- Paragraph -----
      if para = data["paragraph"]?
        theme.paragraph_margin_bottom = float(para["margin_bottom"]?) if para["margin_bottom"]?
        theme.paragraph_indent = float(para["indent"]?) if para["indent"]?
      end

      # ----- Lead -----
      if lead = data["lead"]?
        theme.lead_font_size = float(lead["font_size"]?) if lead["font_size"]?
        theme.lead_font_color = color(lead["font_color"]?) if lead["font_color"]?
      end

      # ----- Link -----
      if link = data["link"]?
        theme.link_font_color = color(link["font_color"]?) if link["font_color"]?
      end

      # ----- Code -----
      if code = data["code"]?
        theme.code_font_family = str(code["font_family"]?) if code["font_family"]?
        theme.code_font_size = float(code["font_size"]?) if code["font_size"]?
        theme.code_font_color = color(code["font_color"]?) if code["font_color"]?
        theme.code_background_color = color(code["background_color"]?) if code["background_color"]?
        theme.code_border_color = color(code["border_color"]?) if code["border_color"]?
        theme.code_padding = float(code["padding"]?) if code["padding"]?
        theme.code_border_width = float(code["border_width"]?) if code["border_width"]?
        theme.code_border_radius = float(code["border_radius"]?) if code["border_radius"]?
      end

      # ----- List -----
      if list = data["list"]?
        theme.list_indent = float(list["indent"]?) if list["indent"]?
        theme.list_item_spacing = float(list["item_spacing"]?) if list["item_spacing"]?
        theme.list_marker_font_color = color(list["marker_font_color"]?) if list["marker_font_color"]?
        theme.ulist_marker = str(list["ulist_marker"]?) if list["ulist_marker"]?
      end

      # ----- Table -----
      if table = data["table"]?
        theme.table_border_color = color(table["border_color"]?) if table["border_color"]?
        theme.table_border_width = float(table["border_width"]?) if table["border_width"]?
        theme.table_header_background_color = color(table["header_background_color"]?) if table["header_background_color"]?
        theme.table_header_font_style = str(table["header_font_style"]?) if table["header_font_style"]?
        theme.table_cell_padding = float(table["cell_padding"]?) if table["cell_padding"]?
        theme.table_stripe_background_color = color(table["stripe_background_color"]?) if table["stripe_background_color"]?
      end

      # ----- Admonition -----
      if adm = data["admonition"]?
        theme.admonition_border_width = float(adm["border_width"]?) if adm["border_width"]?
        theme.admonition_padding = float(adm["padding"]?) if adm["padding"]?
        theme.admonition_label_font_style = str(adm["label_font_style"]?) if adm["label_font_style"]?
        theme.admonition_label_font_size = float(adm["label_font_size"]?) if adm["label_font_size"]?

        if bg = adm["background_color"]?
          new_bg = theme.admonition_background_color.dup
          %w[NOTE TIP WARNING CAUTION IMPORTANT].each do |type|
            new_bg[type] = color(bg[type]?) if bg[type]?
          end
          theme.admonition_background_color = new_bg
        end

        if bc = adm["border_color"]?
          new_bc = theme.admonition_border_color.dup
          %w[NOTE TIP WARNING CAUTION IMPORTANT].each do |type|
            new_bc[type] = color(bc[type]?) if bc[type]?
          end
          theme.admonition_border_color = new_bc
        end
      end

      # ----- Sidebar -----
      if sidebar = data["sidebar"]?
        theme.sidebar_background_color = color(sidebar["background_color"]?) if sidebar["background_color"]?
        theme.sidebar_border_color = color(sidebar["border_color"]?) if sidebar["border_color"]?
        theme.sidebar_border_width = float(sidebar["border_width"]?) if sidebar["border_width"]?
        theme.sidebar_padding = float(sidebar["padding"]?) if sidebar["padding"]?
      end

      # ----- Blockquote -----
      if bq = data["blockquote"]?
        theme.blockquote_border_color = color(bq["border_color"]?) if bq["border_color"]?
        theme.blockquote_border_width = float(bq["border_width"]?) if bq["border_width"]?
        theme.blockquote_padding_left = float(bq["padding_left"]?) if bq["padding_left"]?
        theme.blockquote_font_color = color(bq["font_color"]?) if bq["font_color"]?
        theme.blockquote_font_style = str(bq["font_style"]?) if bq["font_style"]?
      end

      # ----- Image -----
      if image = data["image"]?
        theme.image_align = str(image["align"]?) if image["align"]?
        theme.image_caption_font_size = float(image["caption_font_size"]?) if image["caption_font_size"]?
        theme.image_caption_font_color = color(image["caption_font_color"]?) if image["caption_font_color"]?
      end

      # ----- Thematic Break -----
      if tb = data["thematic_break"]?
        theme.thematic_break_color = color(tb["color"]?) if tb["color"]?
        theme.thematic_break_width = float(tb["width"]?) if tb["width"]?
        theme.thematic_break_margin = float(tb["margin"]?) if tb["margin"]?
      end

      # ----- Header -----
      if header = data["header"]?
        theme.header_enabled = bool(header["enabled"]?) if header["enabled"]?
        theme.header_font_size = float(header["font_size"]?) if header["font_size"]?
        theme.header_font_color = color(header["font_color"]?) if header["font_color"]?
        theme.header_height = float(header["height"]?) if header["height"]?
        theme.header_border_width = float(header["border_width"]?) if header["border_width"]?
        theme.header_border_color = color(header["border_color"]?) if header["border_color"]?
        theme.header_left = str(header["left"]?) if header["left"]?
        theme.header_center = str(header["center"]?) if header["center"]?
        theme.header_right = str(header["right"]?) if header["right"]?
        theme.header_skip_first_page = bool(header["skip_first_page"]?) if header["skip_first_page"]?
      end

      # ----- Footer -----
      if footer = data["footer"]?
        theme.footer_enabled = bool(footer["enabled"]?) if footer["enabled"]?
        theme.footer_font_size = float(footer["font_size"]?) if footer["font_size"]?
        theme.footer_font_color = color(footer["font_color"]?) if footer["font_color"]?
        theme.footer_height = float(footer["height"]?) if footer["height"]?
        theme.footer_border_width = float(footer["border_width"]?) if footer["border_width"]?
        theme.footer_border_color = color(footer["border_color"]?) if footer["border_color"]?
        theme.footer_left = str(footer["left"]?) if footer["left"]?
        theme.footer_center = str(footer["center"]?) if footer["center"]?
        theme.footer_right = str(footer["right"]?) if footer["right"]?
        theme.footer_skip_first_page = bool(footer["skip_first_page"]?) if footer["skip_first_page"]?
      end

      # ----- TOC -----
      if toc = data["toc"]?
        theme.toc_title = str(toc["title"]?) if toc["title"]?
        theme.toc_font_size = float(toc["font_size"]?) if toc["font_size"]?
        theme.toc_indent = float(toc["indent"]?) if toc["indent"]?
        theme.toc_line_height = float(toc["line_height"]?) if toc["line_height"]?
        theme.toc_dot_leader = bool(toc["dot_leader"]?) if toc["dot_leader"]?
      end
    end

    # ----- Type coercion helpers -----

    private def self.float(val : YAML::Any?) : Float64
      return 0.0 if val.nil?
      case raw = val.raw
      when Float64 then raw
      when Int64   then raw.to_f64
      when String  then raw.to_f64
      else              0.0
      end
    end

    private def self.str(val : YAML::Any?) : String
      return "" if val.nil?
      val.as_s? || val.raw.to_s
    end

    private def self.bool(val : YAML::Any?) : Bool
      return false if val.nil?
      case raw = val.raw
      when Bool   then raw
      when String then raw == "true"
      else             false
      end
    end

    private def self.color(val : YAML::Any?) : Tuple(Float64, Float64, Float64)
      return {0.0, 0.0, 0.0} if val.nil?
      if arr = val.as_a?
        r = float(arr[0]?)
        g = float(arr[1]?)
        b = float(arr[2]?)
        {r, g, b}
      else
        {0.0, 0.0, 0.0}
      end
    end
  end
end
