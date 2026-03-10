module AsciiDoc
  # Abstract Syntax Tree nodes for AsciiDoc documents.
  #
  # The AST closely mirrors the Asciidoctor Ruby model, providing a
  # tree of nodes that the PDF converter can traverse.

  # Base class for all AST nodes.
  abstract class Node
    # The parent node (nil for the Document root).
    property parent : Node?

    # Child nodes.
    getter children : Array(Node) = [] of Node

    # Source location (line number, 1-based).
    property source_line : Int32 = 0

    # Node-level attributes (key-value pairs).
    getter attributes : Hash(String, String) = {} of String => String

    def add_child(child : Node) : Node
      child.parent = self
      @children << child
      child
    end

    # Returns the node type as a symbol-like string.
    abstract def node_type : String
  end

  # The root document node.
  class Document < Node
    # Document title (level 0 heading).
    property title : String = ""

    # Document-level attributes (author, date, etc.).
    getter doc_attributes : Hash(String, String) = {} of String => String

    # Document header (author, revision, etc.).
    property author : String = ""
    property email : String = ""
    property revision : String = ""
    property date : String = ""

    def node_type : String
      "document"
    end

    # Convenience: returns all Section children at any depth.
    def sections : Array(Section)
      collect_sections(self)
    end

    private def collect_sections(node : Node) : Array(Section)
      result = [] of Section
      node.children.each do |child|
        if child.is_a?(Section)
          result << child
          result.concat(collect_sections(child))
        end
      end
      result
    end
  end

  # A section (== through ======).
  class Section < Node
    # Section level (1-6).
    property level : Int32 = 1

    # Section title text.
    property title : String = ""

    # Section ID (for cross-references).
    property id : String = ""

    def node_type : String
      "section"
    end
  end

  # A paragraph of text.
  class Paragraph < Node
    # The raw text content (may contain inline markup).
    property text : String = ""

    # Optional role/style (e.g., "lead", "text-center").
    property role : String = ""

    def node_type : String
      "paragraph"
    end
  end

  # A block (generic container for admonitions, sidebars, etc.).
  class Block < Node
    # Block type: "admonition", "sidebar", "example", "quote", "verse",
    # "listing", "literal", "open", "pass".
    property block_type : String = ""

    # Block title (optional).
    property title : String = ""

    # Admonition type: "NOTE", "TIP", "WARNING", "CAUTION", "IMPORTANT".
    property admonition_type : String = ""

    # Source language (for listing/source blocks).
    property language : String = ""

    # Raw content (for literal/listing blocks).
    property content : String = ""

    def node_type : String
      "block"
    end
  end

  # An ordered or unordered list.
  class List < Node
    # List type: "unordered", "ordered", "description".
    property list_type : String = "unordered"

    def node_type : String
      "list"
    end
  end

  # A list item.
  class ListItem < Node
    # The text content of the list item.
    property text : String = ""

    # For description lists: the term.
    property term : String = ""

    # Nesting level (0-based).
    property level : Int32 = 0

    def node_type : String
      "list_item"
    end
  end

  # A table.
  class Table < Node
    # Table title (optional).
    property title : String = ""

    # Column specifications.
    getter columns : Array(TableColumn) = [] of TableColumn

    # Header rows.
    getter header_rows : Array(TableRow) = [] of TableRow

    # Body rows.
    getter body_rows : Array(TableRow) = [] of TableRow

    # Footer rows.
    getter footer_rows : Array(TableRow) = [] of TableRow

    def node_type : String
      "table"
    end
  end

  # A table column specification.
  class TableColumn
    # Column width (proportional or absolute).
    property width : Float64 = 1.0

    # Horizontal alignment: "left", "center", "right".
    property h_align : String = "left"

    # Vertical alignment: "top", "middle", "bottom".
    property v_align : String = "top"

    def initialize(@width = 1.0, @h_align = "left", @v_align = "top")
    end
  end

  # A table row.
  class TableRow
    getter cells : Array(TableCell) = [] of TableCell

    def initialize
    end
  end

  # A table cell.
  class TableCell
    # Cell text content.
    property text : String = ""

    # Column span.
    property colspan : Int32 = 1

    # Row span.
    property rowspan : Int32 = 1

    # Horizontal alignment override.
    property h_align : String = ""

    def initialize(@text = "", @colspan = 1, @rowspan = 1)
    end
  end

  # An inline image or block image.
  class Image < Node
    # Image path or URL.
    property target : String = ""

    # Alt text.
    property alt : String = ""

    # Optional width.
    property width : String = ""

    # Optional height.
    property height : String = ""

    # Caption/title.
    property title : String = ""

    # Whether this is an inline image.
    property inline : Bool = false

    def node_type : String
      "image"
    end
  end

  # A page break.
  class PageBreak < Node
    def node_type : String
      "page_break"
    end
  end

  # A thematic break (horizontal rule).
  class ThematicBreak < Node
    def node_type : String
      "thematic_break"
    end
  end

  # A table of contents placeholder.
  class Toc < Node
    def node_type : String
      "toc"
    end
  end

  # Inline text with formatting.
  record InlineText,
    text : String,
    bold : Bool = false,
    italic : Bool = false,
    mono : Bool = false,
    link : String = "",
    role : String = ""
end
