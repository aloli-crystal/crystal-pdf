module AsciidocPDF
  # Defines the visual theme for PDF generation.
  #
  # Mirrors the asciidoctor-pdf theming system, providing configurable
  # styles for every document element. A default theme is provided that
  # closely matches the asciidoctor-pdf default output.
  class Theme
    # ----- Page -----
    property page_width : Float64 = 595.28         # A4 width in points
    property page_height : Float64 = 841.89        # A4 height in points
    property page_margin_top : Float64 = 72.0
    property page_margin_right : Float64 = 72.0
    property page_margin_bottom : Float64 = 72.0
    property page_margin_left : Float64 = 72.0

    # ----- Base Font -----
    property base_font_family : String = "Helvetica"
    property base_font_size : Float64 = 10.5
    property base_font_color : Tuple(Float64, Float64, Float64) = {0.2, 0.2, 0.2}
    property base_line_height : Float64 = 1.4

    # ----- Heading -----
    property heading_font_family : String = "Helvetica"
    property heading_font_color : Tuple(Float64, Float64, Float64) = {0.0, 0.0, 0.0}
    property heading_font_style : String = "bold"
    property heading_margin_top : Float64 = 18.0
    property heading_margin_bottom : Float64 = 12.0

    # Per-level heading sizes
    property heading_h1_font_size : Float64 = 24.0
    property heading_h2_font_size : Float64 = 18.0
    property heading_h3_font_size : Float64 = 15.0
    property heading_h4_font_size : Float64 = 13.0
    property heading_h5_font_size : Float64 = 11.0
    property heading_h6_font_size : Float64 = 10.5

    # ----- Title Page -----
    property title_page_enabled : Bool = true
    property title_page_font_size : Float64 = 28.0
    property title_page_font_color : Tuple(Float64, Float64, Float64) = {0.0, 0.0, 0.0}
    property title_page_subtitle_font_size : Float64 = 18.0
    property title_page_author_font_size : Float64 = 14.0
    property title_page_revision_font_size : Float64 = 12.0

    # ----- Paragraph -----
    property paragraph_margin_bottom : Float64 = 10.5
    property paragraph_indent : Float64 = 0.0

    # ----- Lead Paragraph -----
    property lead_font_size : Float64 = 13.0
    property lead_font_color : Tuple(Float64, Float64, Float64) = {0.3, 0.3, 0.3}

    # ----- Link -----
    property link_font_color : Tuple(Float64, Float64, Float64) = {0.0, 0.35, 0.65}

    # ----- Code / Monospace -----
    property code_font_family : String = "Courier"
    property code_font_size : Float64 = 9.5
    property code_font_color : Tuple(Float64, Float64, Float64) = {0.0, 0.0, 0.0}
    property code_background_color : Tuple(Float64, Float64, Float64) = {0.96, 0.96, 0.96}
    property code_border_color : Tuple(Float64, Float64, Float64) = {0.8, 0.8, 0.8}
    property code_padding : Float64 = 10.0
    property code_border_width : Float64 = 0.5
    property code_border_radius : Float64 = 3.0

    # ----- List -----
    property list_indent : Float64 = 20.0
    property list_item_spacing : Float64 = 6.0
    property list_marker_font_color : Tuple(Float64, Float64, Float64) = {0.0, 0.0, 0.0}
    property ulist_marker : String = "\u2022" # bullet

    # ----- Table -----
    property table_border_color : Tuple(Float64, Float64, Float64) = {0.7, 0.7, 0.7}
    property table_border_width : Float64 = 0.5
    property table_header_background_color : Tuple(Float64, Float64, Float64) = {0.9, 0.9, 0.9}
    property table_header_font_style : String = "bold"
    property table_cell_padding : Float64 = 6.0
    property table_stripe_background_color : Tuple(Float64, Float64, Float64) = {0.97, 0.97, 0.97}

    # ----- Admonition -----
    property admonition_border_width : Float64 = 0.5
    property admonition_padding : Float64 = 10.0
    property admonition_label_font_style : String = "bold"
    property admonition_label_font_size : Float64 = 10.5
    property admonition_background_color : Hash(String, Tuple(Float64, Float64, Float64)) = {
      "NOTE"      => {0.93, 0.95, 1.0},
      "TIP"       => {0.93, 1.0, 0.93},
      "WARNING"   => {1.0, 0.97, 0.93},
      "CAUTION"   => {1.0, 0.93, 0.93},
      "IMPORTANT" => {1.0, 0.93, 0.93},
    }
    property admonition_border_color : Hash(String, Tuple(Float64, Float64, Float64)) = {
      "NOTE"      => {0.2, 0.4, 0.8},
      "TIP"       => {0.2, 0.6, 0.2},
      "WARNING"   => {0.8, 0.6, 0.0},
      "CAUTION"   => {0.8, 0.2, 0.2},
      "IMPORTANT" => {0.8, 0.0, 0.0},
    }

    # ----- Sidebar -----
    property sidebar_background_color : Tuple(Float64, Float64, Float64) = {0.95, 0.95, 0.95}
    property sidebar_border_color : Tuple(Float64, Float64, Float64) = {0.85, 0.85, 0.85}
    property sidebar_border_width : Float64 = 0.5
    property sidebar_padding : Float64 = 12.0

    # ----- Blockquote -----
    property blockquote_border_color : Tuple(Float64, Float64, Float64) = {0.7, 0.7, 0.7}
    property blockquote_border_width : Float64 = 3.0
    property blockquote_padding_left : Float64 = 15.0
    property blockquote_font_color : Tuple(Float64, Float64, Float64) = {0.4, 0.4, 0.4}
    property blockquote_font_style : String = "italic"

    # ----- Image -----
    property image_align : String = "center"
    property image_caption_font_size : Float64 = 9.0
    property image_caption_font_color : Tuple(Float64, Float64, Float64) = {0.5, 0.5, 0.5}

    # ----- Thematic Break -----
    property thematic_break_color : Tuple(Float64, Float64, Float64) = {0.8, 0.8, 0.8}
    property thematic_break_width : Float64 = 0.5
    property thematic_break_margin : Float64 = 12.0

    # ----- Header / Footer -----
    property header_enabled : Bool = true
    property header_font_size : Float64 = 8.0
    property header_font_color : Tuple(Float64, Float64, Float64) = {0.5, 0.5, 0.5}
    property header_height : Float64 = 36.0
    property header_border_width : Float64 = 0.5
    property header_border_color : Tuple(Float64, Float64, Float64) = {0.8, 0.8, 0.8}

    property footer_enabled : Bool = true
    property footer_font_size : Float64 = 8.0
    property footer_font_color : Tuple(Float64, Float64, Float64) = {0.5, 0.5, 0.5}
    property footer_height : Float64 = 36.0
    property footer_border_width : Float64 = 0.5
    property footer_border_color : Tuple(Float64, Float64, Float64) = {0.8, 0.8, 0.8}

    # ----- Footnotes -----
    property footnote_font_size : Float64 = 8.0
    property footnote_font_color : Tuple(Float64, Float64, Float64) = {0.3, 0.3, 0.3}
    property footnote_separator_color : Tuple(Float64, Float64, Float64) = {0.7, 0.7, 0.7}
    property footnote_separator_width : Float64 = 0.5
    property footnote_separator_length : Float64 = 100.0
    property footnote_margin_top : Float64 = 8.0
    property footnote_line_height : Float64 = 1.3

    # ----- TOC -----
    property toc_title : String = "Table of Contents"
    property toc_font_size : Float64 = 10.5
    property toc_indent : Float64 = 15.0
    property toc_line_height : Float64 = 1.8
    property toc_dot_leader : Bool = true

    def initialize
    end

    # Returns the heading font size for a given level (1-6).
    def heading_font_size(level : Int32) : Float64
      case level
      when 1 then @heading_h1_font_size
      when 2 then @heading_h2_font_size
      when 3 then @heading_h3_font_size
      when 4 then @heading_h4_font_size
      when 5 then @heading_h5_font_size
      when 6 then @heading_h6_font_size
      else        @heading_h4_font_size
      end
    end

    # Returns the content area width (page width minus margins).
    def content_width : Float64
      @page_width - @page_margin_left - @page_margin_right
    end

    # Returns the content area height (page height minus margins).
    def content_height : Float64
      @page_height - @page_margin_top - @page_margin_bottom
    end
  end
end
