require "../pdf"
require "../asciidoc"

module AsciidocPDF
  # Converts an AsciiDoc AST into a PDF document.
  #
  # This is the main class of the asciidoc-pdf converter. It traverses
  # the AST produced by `AsciiDoc::Parser` and generates PDF output
  # using the `PDF::Document` engine.
  #
  # Ported from Asciidoctor::PDF::Converter (Ruby).
  class Converter
    getter document : PDF::Document
    getter theme : Theme
    getter warnings : Array(String) = [] of String

    @current_page : PDF::Page?
    @cursor_y : Float64 = 0.0
    @page_number : Int32 = 0
    @toc_entries : Array(TocEntry) = [] of TocEntry

    # Footnote counter: incremented globally across the whole document.
    getter footnote_counter : Int32 = 0

    # Footnotes collected for the current page (index, text).
    # Exposed for testing; cleared after each page flush.
    getter page_footnotes : Array(Tuple(Int32, String)) = [] of Tuple(Int32, String)

    record TocEntry,
      title : String,
      level : Int32,
      page_number : Int32

    # Metadata tracked per page for header/footer rendering.
    record PageMeta,
      page_number : Int32,
      section_title : String

    # Per-page metadata collected during rendering.
    @page_metas : Array(PageMeta) = [] of PageMeta
    # Title of the section currently being rendered.
    @current_section_title : String = ""

    # Index entry: a term with its page occurrences.
    record IndexEntry,
      primary : String,
      secondary : String,
      page_number : Int32

    # Collected index entries (primary term -> secondary term -> page numbers).
    @index_entries : Array(IndexEntry) = [] of IndexEntry

    # Cross-reference resolution table.
    # Maps anchor_id -> { page_number, display_text }
    record AnchorDef,
      page_number : Int32,
      display_text : String

    @anchor_table : Hash(String, AnchorDef) = {} of String => AnchorDef

    # Loaded TrueType fonts, keyed by role (:base, :base_bold, :base_italic,
    # :base_bold_italic, :heading, :code)
    @ttf_fonts : Hash(Symbol, PDF::Fonts::TrueTypeFont) = {} of Symbol => PDF::Fonts::TrueTypeFont

    def initialize(@theme : Theme = Theme.new)
      @document = PDF::Document.new
      load_truetype_fonts
    end

    # Loads TrueType fonts from the theme paths (if configured).
    private def load_truetype_fonts : Nil
      {
        base:             @theme.base_font_path,
        base_bold:        @theme.base_font_bold_path,
        base_italic:      @theme.base_font_italic_path,
        base_bold_italic: @theme.base_font_bold_italic_path,
        heading:          @theme.heading_font_path,
        code:             @theme.code_font_path,
      }.each do |role, path|
        next if path.nil? || path.empty?
        begin
          @ttf_fonts[role] = @document.load_font(path)
        rescue ex
          @warnings << "Could not load TrueType font for #{role}: #{path} (#{ex.message})"
        end
      end
    end

    # Applies the base TrueType font (or Type1 fallback) to a page.
    private def apply_base_font(page : PDF::Page, size : Float64 = @theme.base_font_size) : Nil
      if ttf = @ttf_fonts[:base]?
        page.font(ttf, size: size)
      else
        page.font(@theme.base_font_family, size: size)
      end
    end

    # Applies the heading TrueType font (or Type1 fallback) to a page.
    private def apply_heading_font(page : PDF::Page, size : Float64) : Nil
      if ttf = @ttf_fonts[:heading]?
        page.font(ttf, size: size)
      elsif ttf = @ttf_fonts[:base_bold]?
        page.font(ttf, size: size)
      else
        page.font(@theme.heading_font_family, size: size)
      end
    end

    # Applies the code TrueType font (or Type1 fallback) to a page.
    private def apply_code_font(page : PDF::Page, size : Float64 = @theme.code_font_size) : Nil
      if ttf = @ttf_fonts[:code]?
        page.font(ttf, size: size)
      else
        page.font(@theme.code_font_family, size: size)
      end
    end

    # Applies the bold TrueType font (or Type1 fallback) to a page.
    private def apply_bold_font(page : PDF::Page, size : Float64) : Nil
      if ttf = @ttf_fonts[:base_bold]?
        page.font(ttf, size: size)
      else
        page.font(@theme.base_font_family, size: size)
      end
    end

    # Applies the italic TrueType font (or Type1 fallback) to a page.
    private def apply_italic_font(page : PDF::Page, size : Float64) : Nil
      if ttf = @ttf_fonts[:base_italic]?
        page.font(ttf, size: size)
      else
        page.font(@theme.base_font_family, size: size)
      end
    end

    # Returns true if any TrueType font is configured.
    def truetype_enabled? : Bool
      !@ttf_fonts.empty?
    end

    # Converts an AsciiDoc source string to a PDF document.
    def self.convert(source : String, theme : Theme = Theme.new) : Converter
      parser = AsciiDoc::Parser.new(source)
      ast = parser.parse
      converter = new(theme)
      converter.convert(ast)
      converter
    end

    # Converts an AsciiDoc AST to PDF.
    def convert(ast : AsciiDoc::Document) : Nil
      # Pre-pass: collect all anchors and section IDs for cross-reference resolution.
      # Page numbers are estimated at 1 for now; they will be updated during rendering.
      collect_anchors(ast, 1)

      # Title page
      if @theme.title_page_enabled && !ast.title.empty?
        render_title_page(ast)
      end

      # TOC placeholder - we'll render it after collecting entries
      has_toc = ast.children.any? { |c| c.is_a?(AsciiDoc::Toc) } ||
                ast.doc_attributes.has_key?("toc")

      # Start content
      new_page
      render_children(ast)

      # Render TOC if requested (insert after title page)
      if has_toc && @toc_entries.size > 0
        render_toc
      end

      # Flush any footnotes remaining on the last page.
      flush_page_footnotes if @current_page

      # Render index if there are any collected terms
      render_index if @index_entries.size > 0

      # Render headers and footers
      render_headers_footers(ast)
    end

    # Pre-pass: walks the AST and registers all anchors and section IDs.
    # Page numbers are approximate (updated during rendering via register_anchor).
    private def collect_anchors(node : AsciiDoc::Node, page_num : Int32) : Nil
      case node
      when AsciiDoc::Section
        unless node.id.empty?
          @anchor_table[node.id] = AnchorDef.new(
            page_number: page_num,
            display_text: node.title
          )
        end
      when AsciiDoc::Anchor
        @anchor_table[node.anchor_id] = AnchorDef.new(
          page_number: page_num,
          display_text: node.anchor_id
        )
      end
      node.children.each { |child| collect_anchors(child, page_num) }
    end

    # Updates the page number for an anchor at render time.
    private def register_anchor(anchor_id : String, display_text : String = "") : Nil
      @anchor_table[anchor_id] = AnchorDef.new(
        page_number: @page_number,
        display_text: display_text.empty? ? anchor_id : display_text
      )
    end

    # Resolves a cross-reference to display text and page number.
    # Returns {display_text, page_number} or {target, 0} if not found.
    def resolve_cross_ref(target : String, display_override : String = "") : Tuple(String, Int32)
      if anchor = @anchor_table[target]?
        display = display_override.empty? ? anchor.display_text : display_override
        {display, anchor.page_number}
      else
        display = display_override.empty? ? target : display_override
        {display, 0}
      end
    end

    # Writes the PDF to an IO.
    def write(io : IO) : Nil
      @document.write(io)
    end

    # Saves the PDF to a file.
    def save(path : String) : Nil
      File.open(path, "w") do |file|
        write(file)
      end
    end

    # ----- Page Management -----

    private def new_page : Nil
      # Flush footnotes accumulated on the current page before moving on.
      flush_page_footnotes if @current_page

      @page_number += 1
      @document.page(width: @theme.page_width, height: @theme.page_height) do |page|
        @current_page = page
        apply_base_font(page)
        @cursor_y = @theme.page_height - @theme.page_margin_top
      end
      # Record metadata for this page (section title at the time of creation)
      @page_metas << PageMeta.new(
        page_number: @page_number,
        section_title: @current_section_title
      )
    end

    private def ensure_space(needed : Float64) : Nil
      if @cursor_y - needed < @theme.page_margin_bottom
        new_page
      end
    end

    private def page : PDF::Page
      @current_page.not_nil!
    end

    private def content_left : Float64
      @theme.page_margin_left
    end

    private def content_right : Float64
      @theme.page_width - @theme.page_margin_right
    end

    private def content_width : Float64
      @theme.content_width
    end

    private def move_down(amount : Float64) : Nil
      @cursor_y -= amount
      if @cursor_y < @theme.page_margin_bottom
        new_page
      end
    end

    # ----- Node Rendering -----

    private def render_children(node : AsciiDoc::Node) : Nil
      node.children.each do |child|
        render_node(child)
      end
    end

    private def render_node(node : AsciiDoc::Node) : Nil
      case node
      when AsciiDoc::Section
        render_section(node)
      when AsciiDoc::Paragraph
        render_paragraph(node)
      when AsciiDoc::Block
        render_block(node)
      when AsciiDoc::List
        render_list(node)
      when AsciiDoc::Table
        render_table(node)
      when AsciiDoc::Image
        render_image(node)
      when AsciiDoc::PageBreak
        new_page
      when AsciiDoc::ThematicBreak
        render_thematic_break
      when AsciiDoc::Anchor
        # Register anchor with accurate page number at render time
        register_anchor(node.anchor_id)
      when AsciiDoc::CrossRef
        # Inline cross-refs are handled in paragraph rendering;
        # block-level cross-refs (rare) are silently skipped here.
      when AsciiDoc::IndexTerm
        # Register the index term with the current page number.
        collect_index_term(node.primary, node.secondary)
      when AsciiDoc::Toc
        # Handled separately after content
      else
        render_children(node)
      end
    end

    # Registers an index term occurrence at the current page.
    private def collect_index_term(primary : String, secondary : String) : Nil
      return if primary.empty?
      @index_entries << IndexEntry.new(
        primary: primary,
        secondary: secondary,
        page_number: @page_number
      )
    end

    # ----- Title Page -----

    private def render_title_page(ast : AsciiDoc::Document) : Nil
      @page_number += 1
      @document.page(width: @theme.page_width, height: @theme.page_height) do |pg|
        @current_page = pg

        # Title centered vertically
        title_y = @theme.page_height * 0.55
        apply_heading_font(pg, @theme.title_page_font_size)
        r, g, b = @theme.title_page_font_color
        pg.fill_color(r, g, b)
        # Center the title
        pg.text(ast.title, at: {content_left, title_y})

        # Author
        if !ast.author.empty?
          apply_base_font(pg, @theme.title_page_author_font_size)
          r, g, b = @theme.base_font_color
          pg.fill_color(r, g, b)
          pg.text(ast.author, at: {content_left, title_y - 50.0})
        end

        # Revision / Date
        if !ast.revision.empty?
          apply_base_font(pg, @theme.title_page_revision_font_size)
          pg.text(ast.revision, at: {content_left, title_y - 75.0})
        end

        @cursor_y = @theme.page_margin_bottom
      end
    end

    # ----- Section -----

    private def render_section(section : AsciiDoc::Section) : Nil
      font_size = @theme.heading_font_size(section.level)
      space_needed = @theme.heading_margin_top + font_size + @theme.heading_margin_bottom

      ensure_space(space_needed)
      move_down(@theme.heading_margin_top)

      # Track current section title for header/footer
      @current_section_title = section.title
      # Update the metadata for the current page with the new section title
      if !@page_metas.empty?
        last = @page_metas.last
        @page_metas[@page_metas.size - 1] = PageMeta.new(
          page_number: last.page_number,
          section_title: section.title
        )
      end

      # Register anchor with accurate page number for cross-reference resolution
      unless section.id.empty?
        register_anchor(section.id, section.title)
      end

      # Record TOC entry
      @toc_entries << TocEntry.new(
        title: section.title,
        level: section.level,
        page_number: @page_number
      )

      # Render heading
      apply_heading_font(page, font_size)
      r, g, b = @theme.heading_font_color
      page.fill_color(r, g, b)
      page.text(section.title, at: {content_left, @cursor_y})

      move_down(font_size + @theme.heading_margin_bottom)

      # Reset to base font
      apply_base_font(page)
      r, g, b = @theme.base_font_color
      page.fill_color(r, g, b)

      # Render section children
      render_children(section)
    end

    # ----- Paragraph -----

    private def render_paragraph(para : AsciiDoc::Paragraph) : Nil
      return if para.text.strip.empty?

      font_size = @theme.base_font_size
      font_color = @theme.base_font_color

      # Lead paragraph
      if para.role == "lead"
        font_size = @theme.lead_font_size
        font_color = @theme.lead_font_color
      end

      # Parse inline markup (may include footnote fragments with index=-1)
      fragments = AsciiDoc::Parser.parse_inline(para.text)

      # Assign sequential indices to footnote fragments and collect them.
      # Also collect inline index terms (footnote_index == -2).
      fragments = fragments.map do |frag|
        if frag.footnote_index == -1
          @footnote_counter += 1
          idx = @footnote_counter
          @page_footnotes << {idx, frag.footnote_text}
          AsciiDoc::InlineText.new(
            text: frag.text,
            bold: frag.bold,
            italic: frag.italic,
            mono: frag.mono,
            link: frag.link,
            role: frag.role,
            footnote_index: idx,
            footnote_text: frag.footnote_text
          )
        elsif frag.footnote_index == -2
          # Inline index term: "indexterm:Primary|Secondary"
          if frag.footnote_text.starts_with?("indexterm:")
            payload = frag.footnote_text["indexterm:".size..]
            parts = payload.split("|", 2)
            collect_index_term(parts[0], parts.size > 1 ? parts[1] : "")
          end
          # Invisible — emit empty fragment
          AsciiDoc::InlineText.new(text: "")
        else
          frag
        end
      end

      # Estimate height needed
      line_height = font_size * @theme.base_line_height
      estimated_lines = estimate_lines(para.text, font_size)

      ensure_space(line_height) # at least one line

      # Render each fragment
      x = content_left
      fragments.each do |frag|
        # Footnote reference: render superscript index
        if frag.footnote_index > 0
          render_footnote_reference(frag.footnote_index, x, font_size, line_height)
          next
        end

        # Cross-reference: render as coloured link text with page number
        if !frag.cross_ref_target.empty?
          display, ref_page = resolve_cross_ref(frag.cross_ref_target, frag.cross_ref_display)
          ref_text = ref_page > 0 ? "#{display} (p. #{ref_page})" : display
          apply_base_font(page, font_size)
          r, g, b = @theme.link_font_color
          page.fill_color(r, g, b)
          render_wrapped_text(ref_text, x, font_size, line_height)
          # Restore normal color for subsequent fragments
          r, g, b = font_color
          page.fill_color(r, g, b)
          next
        end

        if frag.bold
          apply_bold_font(page, font_size)
          # Bold simulation: render twice with slight offset
        elsif frag.italic
          apply_italic_font(page, font_size)
        elsif frag.mono
          apply_code_font(page)
        else
          apply_base_font(page, font_size)
        end

        if !frag.link.empty?
          r, g, b = @theme.link_font_color
          page.fill_color(r, g, b)
        else
          r, g, b = font_color
          page.fill_color(r, g, b)
        end

        # Simple line wrapping for paragraphs
        render_wrapped_text(frag.text, x, font_size, line_height)
      end

      move_down(@theme.paragraph_margin_bottom)
    end

    # ----- Block -----

    private def render_block(block : AsciiDoc::Block) : Nil
      case block.block_type
      when "admonition"
        render_admonition(block)
      when "listing", "source"
        render_listing(block)
      when "literal"
        render_literal(block)
      when "sidebar"
        render_sidebar(block)
      when "quote"
        render_quote(block)
      when "example"
        render_example(block)
      else
        # Render content as paragraph
        if !block.content.empty?
          para = AsciiDoc::Paragraph.new
          para.text = block.content
          render_paragraph(para)
        end
        render_children(block)
      end
    end

    private def render_admonition(block : AsciiDoc::Block) : Nil
      adm_type = block.admonition_type
      bg_color = @theme.admonition_background_color[adm_type]? || {0.95, 0.95, 0.95}
      border_color = @theme.admonition_border_color[adm_type]? || {0.5, 0.5, 0.5}

      content = block.content
      line_height = @theme.base_font_size * @theme.base_line_height
      lines = estimate_lines(content, @theme.base_font_size)
      box_height = (lines * line_height) + @theme.admonition_padding * 2 + @theme.admonition_label_font_size + 8.0

      ensure_space(box_height)

      # Background
      r, g, b = bg_color
      page.fill_color(r, g, b)
      page.rectangle(content_left, @cursor_y, content_width, box_height)
      page.fill

      # Left border
      r, g, b = border_color
      page.stroke_color(r, g, b)
      page.line_width(@theme.admonition_border_width * 4)
      page.move_to(content_left, @cursor_y)
      page.line_to(content_left, @cursor_y - box_height)
      page.stroke

      # Label
      label_x = content_left + @theme.admonition_padding
      label_y = @cursor_y - @theme.admonition_padding - @theme.admonition_label_font_size
      apply_base_font(page, @theme.admonition_label_font_size)
      r, g, b = border_color
      page.fill_color(r, g, b)
      page.text(adm_type, at: {label_x, label_y})

      # Content
      text_y = label_y - @theme.admonition_label_font_size - 4.0
      apply_base_font(page)
      r, g, b = @theme.base_font_color
      page.fill_color(r, g, b)
      page.text(content, at: {label_x, text_y})

      move_down(box_height + @theme.paragraph_margin_bottom)
    end

    private def render_listing(block : AsciiDoc::Block) : Nil
      content = block.content
      line_height = @theme.code_font_size * 1.3
      lines = content.lines
      box_height = (lines.size * line_height) + @theme.code_padding * 2

      ensure_space(Math.min(box_height, @theme.content_height * 0.5))

      # Title
      if !block.title.empty?
        apply_base_font(page)
        r, g, b = @theme.base_font_color
        page.fill_color(r, g, b)
        page.text(block.title, at: {content_left, @cursor_y})
        move_down(@theme.base_font_size + 4.0)
      end

      # Background
      r, g, b = @theme.code_background_color
      page.fill_color(r, g, b)
      page.rectangle(content_left, @cursor_y, content_width, box_height)
      page.fill

      # Border
      r, g, b = @theme.code_border_color
      page.stroke_color(r, g, b)
      page.line_width(@theme.code_border_width)
      page.rectangle(content_left, @cursor_y, content_width, box_height)
      page.stroke

      # Code text
      apply_code_font(page)

      text_x = content_left + @theme.code_padding
      text_y = @cursor_y - @theme.code_padding - @theme.code_font_size

      lang = block.language
      if @theme.syntax_highlight_enabled && !lang.empty?
        # Tokenise each line and render with per-token colours
        lines.each do |line|
          render_highlighted_line(line, lang, text_x, text_y)
          text_y -= line_height
        end
      else
        # Plain monochrome rendering
        r, g, b = @theme.code_font_color
        page.fill_color(r, g, b)
        lines.each do |line|
          page.text(line, at: {text_x, text_y})
          text_y -= line_height
        end
      end

      move_down(box_height + @theme.paragraph_margin_bottom)

      # Reset font
      apply_base_font(page)
    end

    # Renders a single line of source code with syntax-highlighted tokens.
    #
    # Uses the PDF::Syntax engine (8 languages, 17 token types) to tokenise
    # each line and draws each token at the correct x position with its colour.
    # Courier is a fixed-width font: each character is ~0.6 × font_size wide.
    private def render_highlighted_line(line : String, lang : String, base_x : Float64, y : Float64) : Nil
      lexer = PDF::Syntax::Highlighter.lexer_for(lang)
      tokens = lexer.tokenise(line)
      x = base_x
      tokens.each do |token|
        r, g, b = syntax_token_color(token.type)
        page.fill_color(r, g, b)
        page.text(token.text, at: {x, y})
        # Advance x by an approximation of the token width.
        x += token.text.size * @theme.code_font_size * 0.6
      end
    end

    # Maps a PDF::Syntax::TokenType to an RGB colour from the theme.
    private def syntax_token_color(type : PDF::Syntax::TokenType) : Tuple(Float64, Float64, Float64)
      case type
      when PDF::Syntax::TokenType::Keyword       then @theme.syntax_keyword_color
      when PDF::Syntax::TokenType::StringLiteral then @theme.syntax_string_color
      when PDF::Syntax::TokenType::Comment       then @theme.syntax_comment_color
      when PDF::Syntax::TokenType::Number        then @theme.syntax_number_color
      when PDF::Syntax::TokenType::Operator      then @theme.syntax_identifier_color
      when PDF::Syntax::TokenType::Punctuation   then @theme.syntax_punctuation_color
      when PDF::Syntax::TokenType::TypeName      then @theme.syntax_identifier_color
      when PDF::Syntax::TokenType::Builtin       then @theme.syntax_identifier_color
      when PDF::Syntax::TokenType::Attribute     then @theme.syntax_identifier_color
      when PDF::Syntax::TokenType::Constant      then @theme.syntax_keyword_color
      when PDF::Syntax::TokenType::TagName       then @theme.syntax_keyword_color
      when PDF::Syntax::TokenType::AttrName      then @theme.syntax_identifier_color
      when PDF::Syntax::TokenType::AttrValue     then @theme.syntax_string_color
      else                                        @theme.syntax_plain_color
      end
    end

    private def render_literal(block : AsciiDoc::Block) : Nil
      # Same as listing but without border
      render_listing(block)
    end

    private def render_sidebar(block : AsciiDoc::Block) : Nil
      content = block.content
      line_height = @theme.base_font_size * @theme.base_line_height
      lines = estimate_lines(content, @theme.base_font_size)
      box_height = (lines * line_height) + @theme.sidebar_padding * 2

      if !block.title.empty?
        box_height += @theme.base_font_size + 8.0
      end

      ensure_space(box_height)

      # Background
      r, g, b = @theme.sidebar_background_color
      page.fill_color(r, g, b)
      page.rectangle(content_left, @cursor_y, content_width, box_height)
      page.fill

      # Border
      r, g, b = @theme.sidebar_border_color
      page.stroke_color(r, g, b)
      page.line_width(@theme.sidebar_border_width)
      page.rectangle(content_left, @cursor_y, content_width, box_height)
      page.stroke

      text_y = @cursor_y - @theme.sidebar_padding

      # Title
      if !block.title.empty?
        apply_heading_font(page, @theme.base_font_size)
        r, g, b = @theme.heading_font_color
        page.fill_color(r, g, b)
        text_y -= @theme.base_font_size
        page.text(block.title, at: {content_left + @theme.sidebar_padding, text_y})
        text_y -= 8.0
      end

      # Content
      apply_base_font(page)
      r, g, b = @theme.base_font_color
      page.fill_color(r, g, b)
      text_y -= @theme.base_font_size
      page.text(content, at: {content_left + @theme.sidebar_padding, text_y})

      move_down(box_height + @theme.paragraph_margin_bottom)
    end

    private def render_quote(block : AsciiDoc::Block) : Nil
      content = block.content
      line_height = @theme.base_font_size * @theme.base_line_height
      lines = estimate_lines(content, @theme.base_font_size)
      box_height = lines * line_height + 8.0

      ensure_space(box_height)

      # Left border bar
      r, g, b = @theme.blockquote_border_color
      page.stroke_color(r, g, b)
      page.line_width(@theme.blockquote_border_width)
      page.move_to(content_left, @cursor_y)
      page.line_to(content_left, @cursor_y - box_height)
      page.stroke

      # Text
      apply_base_font(page)
      r, g, b = @theme.blockquote_font_color
      page.fill_color(r, g, b)
      text_x = content_left + @theme.blockquote_padding_left
      text_y = @cursor_y - @theme.base_font_size
      page.text(content, at: {text_x, text_y})

      move_down(box_height + @theme.paragraph_margin_bottom)

      # Reset color
      r, g, b = @theme.base_font_color
      page.fill_color(r, g, b)
    end

    private def render_example(block : AsciiDoc::Block) : Nil
      render_sidebar(block) # Similar rendering
    end

    # ----- List -----

    private def render_list(list : AsciiDoc::List) : Nil
      case list.list_type
      when "unordered"
        render_unordered_list(list)
      when "ordered"
        render_ordered_list(list)
      when "description"
        render_description_list(list)
      end
    end

    private def render_unordered_list(list : AsciiDoc::List) : Nil
      list.children.each_with_index do |child, _idx|
        next unless child.is_a?(AsciiDoc::ListItem)
        item = child

        indent = content_left + @theme.list_indent * (item.level + 1)
        line_height = @theme.base_font_size * @theme.base_line_height

        ensure_space(line_height)

        # Bullet marker
        apply_base_font(page)
        r, g, b = @theme.list_marker_font_color
        page.fill_color(r, g, b)
        page.text(@theme.ulist_marker, at: {indent - 12.0, @cursor_y - @theme.base_font_size})

        # Item text
        r, g, b = @theme.base_font_color
        page.fill_color(r, g, b)
        render_wrapped_text(item.text, indent, @theme.base_font_size, line_height)

        move_down(@theme.list_item_spacing)

        # Render nested children
        render_children(item)
      end

      move_down(@theme.paragraph_margin_bottom - @theme.list_item_spacing)
    end

    private def render_ordered_list(list : AsciiDoc::List) : Nil
      list.children.each_with_index do |child, idx|
        next unless child.is_a?(AsciiDoc::ListItem)
        item = child

        indent = content_left + @theme.list_indent * (item.level + 1)
        line_height = @theme.base_font_size * @theme.base_line_height

        ensure_space(line_height)

        # Number marker
        apply_base_font(page)
        r, g, b = @theme.list_marker_font_color
        page.fill_color(r, g, b)
        marker = "#{idx + 1}."
        page.text(marker, at: {indent - 18.0, @cursor_y - @theme.base_font_size})

        # Item text
        r, g, b = @theme.base_font_color
        page.fill_color(r, g, b)
        render_wrapped_text(item.text, indent, @theme.base_font_size, line_height)

        move_down(@theme.list_item_spacing)

        render_children(item)
      end

      move_down(@theme.paragraph_margin_bottom - @theme.list_item_spacing)
    end

    private def render_description_list(list : AsciiDoc::List) : Nil
      list.children.each do |child|
        next unless child.is_a?(AsciiDoc::ListItem)
        item = child

        line_height = @theme.base_font_size * @theme.base_line_height
        ensure_space(line_height * 2)

        # Term (bold)
        apply_bold_font(page, @theme.base_font_size)
        r, g, b = @theme.base_font_color
        page.fill_color(r, g, b)
        page.text(item.term, at: {content_left, @cursor_y - @theme.base_font_size})
        move_down(line_height)

        # Description (indented)
        if !item.text.empty?
          indent = content_left + @theme.list_indent
          render_wrapped_text(item.text, indent, @theme.base_font_size, line_height)
          move_down(@theme.list_item_spacing)
        end

        render_children(item)
      end

      move_down(@theme.paragraph_margin_bottom)
    end

    # ----- Table -----

    private def render_table(table : AsciiDoc::Table) : Nil
      # Title
      if !table.title.empty?
        ensure_space(@theme.base_font_size * 2)
        apply_base_font(page)
        r, g, b = @theme.base_font_color
        page.fill_color(r, g, b)
        page.text("Table: #{table.title}", at: {content_left, @cursor_y - @theme.base_font_size})
        move_down(@theme.base_font_size + 6.0)
      end

      all_rows = table.header_rows + table.body_rows
      return if all_rows.empty?

      num_cols = table.columns.size
      num_cols = all_rows.map(&.cells.size).max if num_cols == 0

      col_width = content_width / num_cols
      row_height = @theme.base_font_size * @theme.base_line_height + @theme.table_cell_padding * 2

      all_rows.each_with_index do |row, row_idx|
        ensure_space(row_height)

        y_top = @cursor_y
        is_header = row_idx < table.header_rows.size

        # Background
        if is_header
          r, g, b = @theme.table_header_background_color
          page.fill_color(r, g, b)
          page.rectangle(content_left, y_top, content_width, row_height)
          page.fill
        elsif row_idx.odd?
          r, g, b = @theme.table_stripe_background_color
          page.fill_color(r, g, b)
          page.rectangle(content_left, y_top, content_width, row_height)
          page.fill
        end

        # Cell borders and text
        row.cells.each_with_index do |cell, col_idx|
          break if col_idx >= num_cols
          cell_x = content_left + col_idx * col_width

          # Border
          r, g, b = @theme.table_border_color
          page.stroke_color(r, g, b)
          page.line_width(@theme.table_border_width)
          page.rectangle(cell_x, y_top, col_width, row_height)
          page.stroke

          # Text
          if is_header
            apply_bold_font(page, @theme.base_font_size)
          else
            apply_base_font(page)
          end
          r, g, b = @theme.base_font_color
          page.fill_color(r, g, b)

          text_x = cell_x + @theme.table_cell_padding
          text_y = y_top - @theme.table_cell_padding - @theme.base_font_size
          page.text(cell.text, at: {text_x, text_y})
        end

        move_down(row_height)
      end

      move_down(@theme.paragraph_margin_bottom)
    end

    # ----- Image -----

    private def render_image(img : AsciiDoc::Image) : Nil
      return if img.target.empty?

      # Try to load the image
      begin
        if File.exists?(img.target)
          image_data = PDF::Images::Image.load(img.target)

          # Calculate dimensions
          max_width = content_width
          img_width = max_width
          img_height = img_width * (image_data.height.to_f / image_data.width.to_f)

          if !img.width.empty?
            if w = img.width.to_f?
              img_width = Math.min(w, max_width)
              img_height = img_width * (image_data.height.to_f / image_data.width.to_f)
            end
          end

          ensure_space(img_height + 20.0)

          # Center image
          x = content_left + (content_width - img_width) / 2.0

          page.image(image_data, at: {x, @cursor_y}, width: img_width)
          move_down(img_height + 8.0)

          # Caption
          if !img.title.empty?
            apply_base_font(page, @theme.image_caption_font_size)
            r, g, b = @theme.image_caption_font_color
            page.fill_color(r, g, b)
            page.text(img.title, at: {content_left, @cursor_y - @theme.image_caption_font_size})
            move_down(@theme.image_caption_font_size + 8.0)

            # Reset font
            apply_base_font(page)
            r, g, b = @theme.base_font_color
            page.fill_color(r, g, b)
          end
        else
          # Image not found - render placeholder
          @warnings << "Image not found: #{img.target}"
          render_image_placeholder(img)
        end
      rescue ex
        @warnings << "Error loading image #{img.target}: #{ex.message}"
        render_image_placeholder(img)
      end
    end

    private def render_image_placeholder(img : AsciiDoc::Image) : Nil
      box_height = 40.0
      ensure_space(box_height)

      page.stroke_color(0.8, 0.8, 0.8)
      page.line_width(0.5)
      page.rectangle(content_left, @cursor_y, content_width, box_height)
      page.stroke

      apply_base_font(page)
      r, g, b = @theme.base_font_color
      page.fill_color(r, g, b)
      alt = img.alt.empty? ? img.target : img.alt
      page.text("[Image: #{alt}]", at: {content_left + 10.0, @cursor_y - 25.0})

      move_down(box_height + @theme.paragraph_margin_bottom)
    end

    # ----- Thematic Break -----

    private def render_thematic_break : Nil
      ensure_space(@theme.thematic_break_margin * 2 + 2.0)
      move_down(@theme.thematic_break_margin)

      r, g, b = @theme.thematic_break_color
      page.stroke_color(r, g, b)
      page.line_width(@theme.thematic_break_width)
      y = @cursor_y
      page.move_to(content_left, y)
      page.line_to(content_right, y)
      page.stroke

      move_down(@theme.thematic_break_margin)
    end

    # ----- TOC -----

    private def render_toc : Nil
      # TOC is rendered on a separate page inserted after the title page
      # For simplicity, we add it at the end with a note
      return if @toc_entries.empty?

      new_page

      # TOC title
      apply_heading_font(page, @theme.heading_h2_font_size)
      r, g, b = @theme.heading_font_color
      page.fill_color(r, g, b)
      page.text(@theme.toc_title, at: {content_left, @cursor_y - @theme.heading_h2_font_size})
      move_down(@theme.heading_h2_font_size + @theme.heading_margin_bottom)

      # TOC entries
      apply_base_font(page, @theme.toc_font_size)
      r, g, b = @theme.base_font_color
      page.fill_color(r, g, b)

      line_height = @theme.toc_font_size * @theme.toc_line_height

      @toc_entries.each do |entry|
        ensure_space(line_height)

        indent = content_left + @theme.toc_indent * (entry.level - 1)
        text = entry.title

        # Dot leader and page number
        if @theme.toc_dot_leader
          text = "#{entry.title} "
          page_text = " #{entry.page_number}"
        else
          page_text = "  #{entry.page_number}"
        end

        page.text(text, at: {indent, @cursor_y - @theme.toc_font_size})

        # Page number right-aligned
        page.text(page_text, at: {content_right - 30.0, @cursor_y - @theme.toc_font_size})

        move_down(line_height)
      end
    end

    # ----- Index -----

    # Renders an alphabetical index section at the end of the document.
    #
    # Index entries are grouped by primary term (sorted alphabetically).
    # Each primary term lists its page occurrences; secondary terms are
    # indented beneath the primary term.
    #
    # Ported from Asciidoctor::PDF::Converter#convert_index_list (Ruby).
    private def render_index : Nil
      return if @index_entries.empty?

      new_page

      # Index title
      apply_heading_font(page, @theme.heading_h2_font_size)
      r, g, b = @theme.heading_font_color
      page.fill_color(r, g, b)
      page.text(@theme.index_title, at: {content_left, @cursor_y - @theme.heading_h2_font_size})
      move_down(@theme.heading_h2_font_size + @theme.heading_margin_bottom)

      # Group entries: primary -> secondary -> sorted unique page numbers
      # Structure: Hash(primary, Hash(secondary, Array(Int32)))
      grouped = {} of String => Hash(String, Array(Int32))
      @index_entries.each do |entry|
        grouped[entry.primary] ||= {} of String => Array(Int32)
        grouped[entry.primary][entry.secondary] ||= [] of Int32
        unless grouped[entry.primary][entry.secondary].includes?(entry.page_number)
          grouped[entry.primary][entry.secondary] << entry.page_number
        end
      end

      # Sort primary terms alphabetically (case-insensitive)
      sorted_primaries = grouped.keys.sort_by(&.downcase)

      line_height = @theme.index_font_size * @theme.index_line_height
      apply_base_font(page, @theme.index_font_size)

      sorted_primaries.each do |primary|
        secondaries = grouped[primary]

        # Primary entry with page numbers for the "" secondary key
        primary_pages = secondaries[""]? || [] of Int32
        primary_pages_sorted = primary_pages.sort

        ensure_space(line_height)
        r, g, b = @theme.base_font_color
        page.fill_color(r, g, b)
        apply_base_font(page, @theme.index_font_size)

        if primary_pages_sorted.empty?
          page.text(primary, at: {content_left, @cursor_y - @theme.index_font_size})
        else
          pages_str = primary_pages_sorted.map(&.to_s).join(", ")
          page.text("#{primary} \u2014 #{pages_str}", at: {content_left, @cursor_y - @theme.index_font_size})
        end
        move_down(line_height)

        # Secondary entries (sorted alphabetically, skip empty key)
        sorted_secondaries = secondaries.keys.reject(&.empty?).sort_by(&.downcase)
        sorted_secondaries.each do |secondary|
          sec_pages = secondaries[secondary].sort
          pages_str = sec_pages.map(&.to_s).join(", ")

          ensure_space(line_height)
          r, g, b = @theme.base_font_color
          page.fill_color(r, g, b)
          apply_base_font(page, @theme.index_font_size)
          page.text("  #{secondary} \u2014 #{pages_str}",
            at: {content_left + @theme.index_indent, @cursor_y - @theme.index_font_size})
          move_down(line_height)
        end
      end
    end

    # Exposes the collected index entries for testing.
    getter index_entries

    # ----- Footnotes -----

    # Renders the footnote superscript reference inline (e.g. "[1]").
    # The reference is rendered at the current cursor position on the same
    # baseline as the surrounding text, using a smaller font size.
    private def render_footnote_reference(index : Int32, x : Float64, font_size : Float64, line_height : Float64) : Nil
      ref_text = "[#{index}]"
      ref_size = (font_size * 0.7).round(1)
      apply_base_font(page, ref_size)
      r, g, b = @theme.footnote_font_color
      page.fill_color(r, g, b)
      # Position slightly above the baseline (superscript effect)
      page.text(ref_text, at: {x, @cursor_y - font_size + ref_size * 0.5})
      # Restore base font
      apply_base_font(page, font_size)
      r, g, b = @theme.base_font_color
      page.fill_color(r, g, b)
    end

    # Renders all footnotes accumulated for the current page at the bottom
    # of the page, preceded by a short separator line.
    # Clears @page_footnotes afterwards.
    private def flush_page_footnotes : Nil
      return if @page_footnotes.empty?

      footnotes = @page_footnotes.dup
      @page_footnotes.clear

      fn_size = @theme.footnote_font_size
      fn_line_height = fn_size * @theme.footnote_line_height

      # Calculate the total height needed for the footnote block.
      total_height = @theme.footnote_margin_top + 4.0 + footnotes.size * fn_line_height

      # Position the footnote block at the bottom of the current page.
      fn_y = @theme.page_margin_bottom + total_height

      # Separator line
      r, g, b = @theme.footnote_separator_color
      page.stroke_color(r, g, b)
      page.line_width(@theme.footnote_separator_width)
      page.move_to(content_left, fn_y)
      page.line_to(content_left + @theme.footnote_separator_length, fn_y)
      page.stroke

      # Footnote entries
      apply_base_font(page, fn_size)
      r, g, b = @theme.footnote_font_color
      page.fill_color(r, g, b)

      footnotes.each_with_index do |(idx, text), i|
        entry_y = fn_y - @theme.footnote_margin_top - (i + 1) * fn_line_height
        page.text("#{idx}. #{text}", at: {content_left, entry_y})
      end

      # Restore base font
      apply_base_font(page)
      r, g, b = @theme.base_font_color
      page.fill_color(r, g, b)
    end

    # ----- Headers & Footers -----

    private def render_headers_footers(ast : AsciiDoc::Document) : Nil
      total_pages = @page_number
      doc_title = ast.title

      @document.pages.each_with_index do |pg, idx|
        page_num = idx + 1
        meta = @page_metas.find { |m| m.page_number == page_num }
        section_title = meta ? meta.section_title : ""

        # Render header
        if @theme.header_enabled
          skip = @theme.header_skip_first_page && page_num == 1
          unless skip
            render_header_on_page(pg, page_num, total_pages, doc_title, section_title)
          end
        end

        # Render footer
        if @theme.footer_enabled
          skip = @theme.footer_skip_first_page && page_num == 1
          unless skip
            render_footer_on_page(pg, page_num, total_pages, doc_title, section_title)
          end
        end
      end
    end

    # Renders the header band on a given page.
    private def render_header_on_page(pg : PDF::Page, page_num : Int32, total_pages : Int32,
                                       doc_title : String, section_title : String) : Nil
      h = @theme.header_height
      y_top = @theme.page_height - h
      y_text = y_top + h * 0.4  # vertical center of band

      apply_base_font(pg, @theme.header_font_size)
      r, g, b = @theme.header_font_color
      pg.fill_color(r, g, b)

      # Border line at bottom of header band
      r2, g2, b2 = @theme.header_border_color
      pg.stroke_color(r2, g2, b2)
      pg.line_width(@theme.header_border_width)
      pg.move_to(@theme.page_margin_left, y_top)
      pg.line_to(@theme.page_width - @theme.page_margin_right, y_top)
      pg.stroke

      # Restore fill color
      r, g, b = @theme.header_font_color
      pg.fill_color(r, g, b)

      # Left slot
      left_text = resolve_tokens(@theme.header_left, page_num, total_pages, doc_title, section_title)
      pg.text(left_text, at: {@theme.page_margin_left, y_text}) unless left_text.empty?

      # Center slot
      center_text = resolve_tokens(@theme.header_center, page_num, total_pages, doc_title, section_title)
      unless center_text.empty?
        center_x = @theme.page_width / 2.0 - (center_text.size * @theme.header_font_size * 0.3)
        pg.text(center_text, at: {center_x, y_text})
      end

      # Right slot
      right_text = resolve_tokens(@theme.header_right, page_num, total_pages, doc_title, section_title)
      unless right_text.empty?
        right_x = @theme.page_width - @theme.page_margin_right - (right_text.size * @theme.header_font_size * 0.5)
        pg.text(right_text, at: {right_x, y_text})
      end
    end

    # Renders the footer band on a given page.
    private def render_footer_on_page(pg : PDF::Page, page_num : Int32, total_pages : Int32,
                                       doc_title : String, section_title : String) : Nil
      h = @theme.footer_height
      y_bottom = @theme.page_margin_bottom
      y_text = y_bottom - h * 0.6  # below margin

      apply_base_font(pg, @theme.footer_font_size)
      r, g, b = @theme.footer_font_color
      pg.fill_color(r, g, b)

      # Border line at top of footer band
      r2, g2, b2 = @theme.footer_border_color
      pg.stroke_color(r2, g2, b2)
      pg.line_width(@theme.footer_border_width)
      pg.move_to(@theme.page_margin_left, y_bottom)
      pg.line_to(@theme.page_width - @theme.page_margin_right, y_bottom)
      pg.stroke

      # Restore fill color
      r, g, b = @theme.footer_font_color
      pg.fill_color(r, g, b)

      # Left slot
      left_text = resolve_tokens(@theme.footer_left, page_num, total_pages, doc_title, section_title)
      pg.text(left_text, at: {@theme.page_margin_left, y_text}) unless left_text.empty?

      # Center slot
      center_text = resolve_tokens(@theme.footer_center, page_num, total_pages, doc_title, section_title)
      unless center_text.empty?
        center_x = @theme.page_width / 2.0 - (center_text.size * @theme.footer_font_size * 0.3)
        pg.text(center_text, at: {center_x, y_text})
      end

      # Right slot
      right_text = resolve_tokens(@theme.footer_right, page_num, total_pages, doc_title, section_title)
      unless right_text.empty?
        right_x = @theme.page_width - @theme.page_margin_right - (right_text.size * @theme.footer_font_size * 0.5)
        pg.text(right_text, at: {right_x, y_text})
      end
    end

    # Resolves token placeholders in a header/footer content string.
    #
    # Supported tokens:
    #   {page_number}    — current page number
    #   {page_count}     — total number of pages
    #   {document_title} — document title
    #   {section_title}  — current section title
    private def resolve_tokens(template : String, page_num : Int32, total_pages : Int32,
                                doc_title : String, section_title : String) : String
      template
        .gsub("{page_number}", page_num.to_s)
        .gsub("{page_count}", total_pages.to_s)
        .gsub("{document_title}", doc_title)
        .gsub("{section_title}", section_title)
    end

    # ----- Text Helpers -----

    private def render_wrapped_text(text : String, x : Float64, font_size : Float64, line_height : Float64) : Nil
      # Simple word-wrapping
      available_width = content_right - x
      chars_per_line = (available_width / (font_size * 0.5)).to_i
      chars_per_line = 10 if chars_per_line < 10

      lines = wrap_text(text, chars_per_line)
      lines.each do |line|
        ensure_space(line_height)
        page.text(line, at: {x, @cursor_y - font_size})
        move_down(line_height)
      end
    end

    private def wrap_text(text : String, max_chars : Int32) : Array(String)
      result = [] of String
      text.lines.each do |paragraph_line|
        words = paragraph_line.split(/\s+/)
        current_line = ""

        words.each do |word|
          if current_line.empty?
            current_line = word
          elsif (current_line.size + 1 + word.size) <= max_chars
            current_line += " " + word
          else
            result << current_line
            current_line = word
          end
        end

        result << current_line unless current_line.empty?
      end

      result << "" if result.empty?
      result
    end

    private def estimate_lines(text : String, font_size : Float64) : Int32
      chars_per_line = (content_width / (font_size * 0.5)).to_i
      chars_per_line = 10 if chars_per_line < 10
      lines = wrap_text(text, chars_per_line)
      lines.size
    end
  end
end
