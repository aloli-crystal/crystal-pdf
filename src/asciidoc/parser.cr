module AsciiDoc
  # Parses AsciiDoc text into an AST (Abstract Syntax Tree).
  #
  # This parser implements the subset of AsciiDoc syntax needed for
  # PDF generation, covering:
  # - Document header (title, author, attributes)
  # - Sections (levels 1-6)
  # - Paragraphs
  # - Unordered and ordered lists
  # - Description lists
  # - Source/listing blocks
  # - Literal blocks
  # - Admonition blocks (NOTE, TIP, WARNING, CAUTION, IMPORTANT)
  # - Sidebar, example, quote blocks
  # - Tables
  # - Block and inline images
  # - Page breaks
  # - Thematic breaks
  # - Document attributes
  # - TOC macro
  class Parser
    @lines : Array(String)
    @pos : Int32 = 0
    @document : Document

    def initialize(source : String)
      @lines = source.lines
      @document = Document.new
    end

    # Parses the source and returns the Document AST.
    def parse : Document
      parse_header
      parse_body(@document)
      @document
    end

    # ----- Header Parsing -----

    private def parse_header : Nil
      skip_blank_lines

      # Document title: = Title
      if current_line? && current_line.starts_with?("= ") && !current_line.starts_with?("== ")
        @document.title = current_line[2..].strip
        @document.source_line = @pos + 1
        advance
      end

      # Author line (immediately after title, no blank line)
      if current_line? && !current_line.empty? && !current_line.starts_with?(":")
        author_line = current_line.strip
        if !author_line.starts_with?("=") && !author_line.starts_with?("[")
          @document.author = author_line
          # Extract email if present: Author Name <email>
          if match = author_line.match(/<([^>]+)>/)
            @document.email = match[1]
            @document.author = author_line.gsub(/<[^>]+>/, "").strip
          end
          advance
        end
      end

      # Revision line
      if current_line? && !current_line.empty? && !current_line.starts_with?(":") && !current_line.starts_with?("=")
        rev_line = current_line.strip
        if rev_line.match(/^v?\d/)
          @document.revision = rev_line
          advance
        end
      end

      # Document attributes
      parse_attributes
      skip_blank_lines
    end

    private def parse_attributes : Nil
      while current_line? && current_line.starts_with?(":")
        if match = current_line.match(/^:([^:]+):\s*(.*)$/)
          key = match[1].strip
          value = match[2].strip
          @document.doc_attributes[key] = value
        end
        advance
      end
    end

    # ----- Body Parsing -----

    private def parse_body(parent : Node) : Nil
      while current_line?
        skip_blank_lines
        break unless current_line?

        # Block attributes [source,crystal] or [role]
        block_attrs = parse_block_attributes

        # Re-read current line after consuming block attributes
        break unless current_line?
        line = current_line

        # Section heading
        if line.starts_with?("=")
          level = count_heading_level(line)
          if level > 0 && level <= 6
            section = parse_section(level, parent)
            # If section level is higher than parent section, it's a child
            if parent.is_a?(Section) && level <= parent.level
              # This section belongs to a higher-level parent; backtrack
              @pos -= 1 # undo advance done in parse_section
              break
            end
            next
          end
        end

        # Page break
        if line == "<<<" || line == "<<<\n"
          parent.add_child(PageBreak.new)
          advance
          next
        end

        # Delimited blocks (MUST be checked before thematic breaks)
        if line.starts_with?("----")
          block = parse_delimited_block("----", "listing", block_attrs)
          parent.add_child(block)
          next
        end

        if line.starts_with?("....")
          block = parse_delimited_block("....", "literal", block_attrs)
          parent.add_child(block)
          next
        end

        if line.starts_with?("====")
          block = parse_delimited_block("====", "example", block_attrs)
          parent.add_child(block)
          next
        end

        # Thematic break (after delimited blocks to avoid false matches)
        if line == "'''" || (line.match(/^-{3,}$/) && !line.starts_with?("----")) || line.match(/^\*{3,}$/)
          parent.add_child(ThematicBreak.new)
          advance
          next
        end

        # TOC macro
        if line.strip == "toc::[]"
          parent.add_child(Toc.new)
          advance
          next
        end

        # Block image
        if match = line.match(/^image::([^\[]+)\[([^\]]*)\]/)
          img = parse_block_image(match, block_attrs)
          parent.add_child(img)
          advance
          next
        end

        # Table
        if line.starts_with?("|===")
          table = parse_table(block_attrs)
          parent.add_child(table)
          next
        end

        if line.starts_with?("****")
          block = parse_delimited_block("****", "sidebar", block_attrs)
          parent.add_child(block)
          next
        end

        if line.starts_with?("____")
          block = parse_delimited_block("____", "quote", block_attrs)
          parent.add_child(block)
          next
        end

        # Admonition paragraph: NOTE: text, TIP: text, etc.
        if match = line.match(/^(NOTE|TIP|WARNING|CAUTION|IMPORTANT):\s+(.+)/)
          block = Block.new
          block.block_type = "admonition"
          block.admonition_type = match[1]
          block.content = match[2]
          block.source_line = @pos + 1
          parent.add_child(block)
          advance
          next
        end

        # Unordered list
        if line.match(/^(\*+|\-)\s+/)
          list = parse_unordered_list
          parent.add_child(list)
          next
        end

        # Ordered list
        if line.match(/^\.+\s+\S/) && !line.starts_with?("..")
          list = parse_ordered_list
          parent.add_child(list)
          next
        end

        # Description list
        if line.match(/^.+::(\s|$)/)
          list = parse_description_list
          parent.add_child(list)
          next
        end

        # Block title (. prefix)
        block_title = ""
        if line.starts_with?(".") && !line.starts_with?("..") && !line.starts_with?(". ")
          block_title = line[1..].strip
          advance
          next unless current_line?
          line = current_line
        end

        # Paragraph (default)
        para = parse_paragraph
        para.attributes.merge!(block_attrs) unless block_attrs.empty?
        if role = block_attrs["role"]?
          para.role = role
        end
        parent.add_child(para)
      end
    end

    # ----- Section Parsing -----

    private def parse_section(level : Int32, parent : Node) : Section
      section = Section.new
      section.level = level
      title_text = current_line.lstrip('=').strip
      # Extract ID if present: [[id]] or [#id]
      if match = title_text.match(/\[\[([^\]]+)\]\]/)
        section.id = match[1]
        title_text = title_text.gsub(/\[\[[^\]]+\]\]/, "").strip
      end
      section.title = title_text
      section.source_line = @pos + 1

      # Generate ID from title if not set
      if section.id.empty?
        section.id = "_" + title_text.downcase.gsub(/[^a-z0-9]+/, "_").strip('_')
      end

      parent.add_child(section)
      advance

      # Parse section body
      parse_body(section)

      section
    end

    # ----- List Parsing -----

    private def parse_unordered_list : List
      list = List.new
      list.list_type = "unordered"
      list.source_line = @pos + 1

      while current_line?
        line = current_line
        if match = line.match(/^(\*+|\-)\s+(.+)/)
          marker = match[1]
          text = match[2].strip
          level = marker == "-" ? 0 : marker.size - 1

          item = ListItem.new
          item.text = text
          item.level = level
          item.source_line = @pos + 1
          list.add_child(item)
          advance

          # Continuation lines (+ or indented)
          while current_line? && (current_line.starts_with?("+") || (current_line.starts_with?("  ") && !current_line.strip.empty?))
            if current_line.strip == "+"
              advance
              next
            end
            item.text += "\n" + current_line.strip
            advance
          end
        else
          break
        end

        skip_blank_lines_in_list
      end

      list
    end

    private def parse_ordered_list : List
      list = List.new
      list.list_type = "ordered"
      list.source_line = @pos + 1

      while current_line?
        line = current_line
        if match = line.match(/^(\.+)\s+(.+)/)
          dots = match[1]
          text = match[2].strip
          level = dots.size - 1

          item = ListItem.new
          item.text = text
          item.level = level
          item.source_line = @pos + 1
          list.add_child(item)
          advance

          # Continuation
          while current_line? && (current_line.starts_with?("+") || (current_line.starts_with?("  ") && !current_line.strip.empty?))
            if current_line.strip == "+"
              advance
              next
            end
            item.text += "\n" + current_line.strip
            advance
          end
        else
          break
        end

        skip_blank_lines_in_list
      end

      list
    end

    private def parse_description_list : List
      list = List.new
      list.list_type = "description"
      list.source_line = @pos + 1

      while current_line?
        line = current_line
        if match = line.match(/^(.+?)::(\s+(.*))?$/)
          term = match[1].strip
          desc = (match[3]? || "").strip

          item = ListItem.new
          item.term = term
          item.text = desc
          item.source_line = @pos + 1
          list.add_child(item)
          advance

          # If description is on next line
          if item.text.empty? && current_line? && !current_line.empty? && !current_line.match(/^.+::/)
            item.text = current_line.strip
            advance
          end
        else
          break
        end

        skip_blank_lines_in_list
      end

      list
    end

    # ----- Block Parsing -----

    private def parse_delimited_block(delimiter : String, type : String, attrs : Hash(String, String)) : Block
      block = Block.new
      block.block_type = type
      block.source_line = @pos + 1

      # Check for source language
      if attrs["source"]? || type == "listing"
        if lang = attrs["language"]?
          block.language = lang
        end
        if type == "listing" && attrs.has_key?("source")
          block.block_type = "source"
        end
      end

      # Check for admonition
      if adm = attrs["admonition"]?
        block.block_type = "admonition"
        block.admonition_type = adm
      end

      if title = attrs["title"]?
        block.title = title
      end

      advance # skip opening delimiter

      content_lines = [] of String
      while current_line? && !current_line.starts_with?(delimiter)
        content_lines << current_line
        advance
      end

      block.content = content_lines.join("\n")
      advance if current_line? # skip closing delimiter

      block
    end

    # ----- Table Parsing -----

    private def parse_table(attrs : Hash(String, String)) : Table
      table = Table.new
      table.source_line = @pos + 1

      if title = attrs["title"]?
        table.title = title
      end

      advance # skip |===

      # Parse column specs from attributes if present
      if cols_spec = attrs["cols"]?
        table.columns.concat(parse_column_specs(cols_spec))
      end

      # Detect header row (first row before blank line or explicit opts)
      has_header = attrs["header"]? == "true" || attrs["options"]?.try(&.includes?("header")) || false
      first_row = true
      in_header = has_header || true # First row is header by default unless opts="noheader"
      no_header = attrs["options"]?.try(&.includes?("noheader")) || false

      while current_line? && !current_line.starts_with?("|===")
        skip_blank_lines
        break if !current_line? || current_line.starts_with?("|===")

        row = parse_table_row
        if row.cells.size > 0
          if first_row && !no_header
            table.header_rows << row
            first_row = false
          else
            table.body_rows << row
            first_row = false
          end
        end
      end

      advance if current_line? # skip closing |===

      # Auto-detect columns from first row if not specified
      if table.columns.empty?
        max_cols = 0
        (table.header_rows + table.body_rows).each do |row|
          max_cols = row.cells.size if row.cells.size > max_cols
        end
        max_cols.times { table.columns << TableColumn.new }
      end

      table
    end

    private def parse_table_row : TableRow
      row = TableRow.new

      # Cells can be on one line: | cell1 | cell2 | cell3
      # Or on multiple lines
      line = current_line
      if line.starts_with?("|")
        cells_text = line[1..] # remove leading |
        parts = cells_text.split("|")
        parts.each do |part|
          cell = TableCell.new(text: part.strip)
          row.cells << cell
        end
        advance
      else
        advance
      end

      row
    end

    private def parse_column_specs(spec : String) : Array(TableColumn)
      columns = [] of TableColumn
      parts = spec.split(",")
      parts.each do |part|
        col = TableColumn.new
        part = part.strip

        # Parse alignment: <, >, ^
        if part.starts_with?("<")
          col.h_align = "left"
          part = part[1..]
        elsif part.starts_with?(">")
          col.h_align = "right"
          part = part[1..]
        elsif part.starts_with?("^")
          col.h_align = "center"
          part = part[1..]
        end

        # Parse width
        if w = part.to_f?
          col.width = w
        end

        columns << col
      end
      columns
    end

    # ----- Image Parsing -----

    private def parse_block_image(match : Regex::MatchData, attrs : Hash(String, String)) : Image
      img = Image.new
      img.target = match[1].strip
      img.source_line = @pos + 1

      # Parse image attributes: alt,width,height
      attr_str = match[2]
      parts = attr_str.split(",")
      img.alt = parts[0]?.try(&.strip) || ""
      img.width = parts[1]?.try(&.strip) || ""
      img.height = parts[2]?.try(&.strip) || ""

      if title = attrs["title"]?
        img.title = title
      end

      img
    end

    # ----- Paragraph Parsing -----

    private def parse_paragraph : Paragraph
      para = Paragraph.new
      para.source_line = @pos + 1

      lines = [] of String
      while current_line? && !current_line.empty?
        line = current_line
        # Stop at block boundaries
        break if line.starts_with?("=")
        break if line.starts_with?("|===")
        break if line.starts_with?("----")
        break if line.starts_with?("....")
        break if line.starts_with?("====")
        break if line.starts_with?("****")
        break if line.starts_with?("____")
        break if line == "<<<" || line == "'''"
        break if line.starts_with?("image::")
        break if line.starts_with?("toc::[]")
        break if line.match(/^(\*+|\-)\s+/)
        break if line.match(/^\.+\s+\S/) && !line.starts_with?("..")
        break if line.match(/^.+::(\s|$)/)
        break if line.starts_with?("[")
        break if line.match(/^(NOTE|TIP|WARNING|CAUTION|IMPORTANT):\s+/)

        lines << line
        advance
      end

      para.text = lines.join("\n")
      para
    end

    # ----- Block Attributes -----

    private def parse_block_attributes : Hash(String, String)
      attrs = {} of String => String

      while current_line? && current_line.starts_with?("[")
        line = current_line.strip
        if line.ends_with?("]")
          content = line[1..-2]

          # [source,crystal]
          if content.starts_with?("source")
            attrs["source"] = "true"
            parts = content.split(",")
            if parts.size > 1
              attrs["language"] = parts[1].strip
            end
          # [cols="..."]
          elsif match = content.match(/cols="([^"]+)"/)
            attrs["cols"] = match[1]
          # [options="header"]
          elsif match = content.match(/options="([^"]+)"/)
            attrs["options"] = match[1]
          # [#id] or [.role]
          elsif content.starts_with?("#")
            attrs["id"] = content[1..]
          elsif content.starts_with?(".")
            attrs["role"] = content[1..]
          # [NOTE], [TIP], etc.
          elsif content.match(/^(NOTE|TIP|WARNING|CAUTION|IMPORTANT)$/)
            attrs["admonition"] = content
          else
            # Generic: first positional = style
            attrs["style"] = content.split(",").first.strip
          end
        end
        advance
      end

      # Block title
      if current_line? && current_line.starts_with?(".") && !current_line.starts_with?("..") && !current_line.starts_with?(". ") && !current_line.match(/^\.+\s+\S/)
        attrs["title"] = current_line[1..].strip
        advance
      end

      attrs
    end

    # ----- Inline Parsing -----

    # Parses inline markup in a text string into InlineText fragments.
    # Footnotes are returned as fragments with footnote_index=-1 (index to be
    # assigned later by the Converter) and footnote_text set.
    def self.parse_inline(text : String) : Array(InlineText)
      fragments = [] of InlineText
      remaining = text
      pos = 0

      while pos < remaining.size
        # Footnote: footnote:[text]
        if remaining[pos..].starts_with?("footnote:[") || remaining[pos..].starts_with?("footnoteref:[") 
          macro_name = remaining[pos..].starts_with?("footnoteref:[") ? "footnoteref:" : "footnote:"
          macro_start = pos + macro_name.size
          # Find the matching closing bracket (handle nested brackets)
          bracket_depth = 0
          bracket_end = -1
          i = macro_start
          while i < remaining.size
            if remaining[i] == '['
              bracket_depth += 1
            elsif remaining[i] == ']'
              bracket_depth -= 1
              if bracket_depth == 0
                bracket_end = i
                break
              end
            end
            i += 1
          end
          if bracket_end > macro_start
            footnote_text = remaining[macro_start + 1...bracket_end]
            if pos > 0
              fragments << InlineText.new(text: remaining[0...pos])
            end
            # footnote_index = -1 signals "to be assigned by Converter"
            fragments << InlineText.new(
              text: "",
              footnote_index: -1,
              footnote_text: footnote_text
            )
            remaining = remaining[bracket_end + 1..]
            pos = 0
            next
          end
        end

        # Bold: *text* or **text**
        if remaining[pos..].starts_with?("**")
          end_pos = remaining.index("**", pos + 2)
          if end_pos
            # Flush preceding text
            if pos > 0
              fragments << InlineText.new(text: remaining[0...pos])
            end
            fragments << InlineText.new(text: remaining[pos + 2...end_pos], bold: true)
            remaining = remaining[end_pos + 2..]
            pos = 0
            next
          end
        elsif remaining[pos] == '*' && (pos == 0 || remaining[pos - 1].whitespace?)
          end_pos = remaining.index('*', pos + 1)
          if end_pos && end_pos > pos + 1
            if pos > 0
              fragments << InlineText.new(text: remaining[0...pos])
            end
            fragments << InlineText.new(text: remaining[pos + 1...end_pos], bold: true)
            remaining = remaining[end_pos + 1..]
            pos = 0
            next
          end
        end

        # Italic: _text_ or __text__
        if remaining[pos..].starts_with?("__")
          end_pos = remaining.index("__", pos + 2)
          if end_pos
            if pos > 0
              fragments << InlineText.new(text: remaining[0...pos])
            end
            fragments << InlineText.new(text: remaining[pos + 2...end_pos], italic: true)
            remaining = remaining[end_pos + 2..]
            pos = 0
            next
          end
        elsif remaining[pos] == '_' && (pos == 0 || remaining[pos - 1].whitespace?)
          end_pos = remaining.index('_', pos + 1)
          if end_pos && end_pos > pos + 1
            if pos > 0
              fragments << InlineText.new(text: remaining[0...pos])
            end
            fragments << InlineText.new(text: remaining[pos + 1...end_pos], italic: true)
            remaining = remaining[end_pos + 1..]
            pos = 0
            next
          end
        end

        # Monospace: `text`
        if remaining[pos] == '`'
          end_pos = remaining.index('`', pos + 1)
          if end_pos && end_pos > pos + 1
            if pos > 0
              fragments << InlineText.new(text: remaining[0...pos])
            end
            fragments << InlineText.new(text: remaining[pos + 1...end_pos], mono: true)
            remaining = remaining[end_pos + 1..]
            pos = 0
            next
          end
        end

        # Link: https://... or link:url[text]
        if remaining[pos..].starts_with?("http://") || remaining[pos..].starts_with?("https://")
          # Find end of URL
          url_end = pos
          while url_end < remaining.size && !remaining[url_end].whitespace? && remaining[url_end] != '[' && remaining[url_end] != ']'
            url_end += 1
          end
          url = remaining[pos...url_end]

          # Check for [text] after URL
          link_text = url
          actual_end = url_end
          if url_end < remaining.size && remaining[url_end] == '['
            bracket_end = remaining.index(']', url_end)
            if bracket_end
              link_text = remaining[url_end + 1...bracket_end]
              actual_end = bracket_end + 1
            end
          end

          if pos > 0
            fragments << InlineText.new(text: remaining[0...pos])
          end
          fragments << InlineText.new(text: link_text, link: url)
          remaining = remaining[actual_end..]
          pos = 0
          next
        end

        pos += 1
      end

      # Flush remaining text
      if !remaining.empty?
        fragments << InlineText.new(text: remaining)
      end

      # If no fragments were created, return the original text
      if fragments.empty?
        fragments << InlineText.new(text: text)
      end

      fragments
    end

    # ----- Utility Methods -----

    private def current_line? : Bool
      @pos < @lines.size
    end

    private def current_line : String
      @lines[@pos]
    end

    private def advance : Nil
      @pos += 1
    end

    private def skip_blank_lines : Nil
      while current_line? && current_line.strip.empty?
        advance
      end
    end

    private def skip_blank_lines_in_list : Nil
      # Skip at most one blank line in a list context
      if current_line? && current_line.strip.empty?
        advance
      end
    end

    private def count_heading_level(line : String) : Int32
      count = 0
      line.each_char do |c|
        if c == '='
          count += 1
        else
          break
        end
      end
      # Must be followed by a space
      if count > 0 && count < line.size && line[count] == ' '
        count
      else
        0
      end
    end
  end
end
