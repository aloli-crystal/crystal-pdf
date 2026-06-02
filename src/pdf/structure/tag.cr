module PDF
  module Structure
    # Standard structure types (PDF 32000-1 § 14.8.4, "Standard
    # Structure Types") used as the `/S` entry of a structure
    # element. These are the building blocks of a Tagged PDF and the
    # vocabulary PDF/UA-1 validators understand.
    #
    # Custom (non-standard) roles are allowed too, but they must be
    # mapped to a standard role via the StructTreeRoot `/RoleMap`.
    # `Tag.standard?` tells the two apart.
    module Tag
      # --- Grouping elements (§ 14.8.4.3) ---
      DOCUMENT   = "Document"
      PART       = "Part"
      ART        = "Art"  # article
      SECT       = "Sect" # section
      DIV        = "Div"
      BLOCKQUOTE = "BlockQuote"
      CAPTION    = "Caption"
      TOC        = "TOC"  # table of contents
      TOCI       = "TOCI" # TOC item
      INDEX      = "Index"
      NONSTRUCT  = "NonStruct"
      PRIVATE    = "Private"

      # --- Block-level structure (§ 14.8.4.4) ---
      P  = "P" # paragraph
      H  = "H" # generic heading
      H1 = "H1"
      H2 = "H2"
      H3 = "H3"
      H4 = "H4"
      H5 = "H5"
      H6 = "H6"

      # --- Lists (§ 14.8.4.4) ---
      L     = "L"     # list
      LI    = "LI"    # list item
      LBL   = "Lbl"   # list item label
      LBODY = "LBody" # list item body

      # --- Tables (§ 14.8.4.4) ---
      TABLE = "Table"
      TR    = "TR" # table row
      TH    = "TH" # table header cell
      TD    = "TD" # table data cell
      THEAD = "THead"
      TBODY = "TBody"
      TFOOT = "TFoot"

      # --- Inline-level structure (§ 14.8.4.5) ---
      SPAN      = "Span"
      QUOTE     = "Quote"
      NOTE      = "Note"
      REFERENCE = "Reference"
      BIBENTRY  = "BibEntry"
      CODE      = "Code"
      LINK      = "Link"
      ANNOT     = "Annot"

      # --- Illustration elements (§ 14.8.4.6) ---
      FIGURE  = "Figure"
      FORMULA = "Formula"
      FORM    = "Form" # interactive form field (AcroForm widget)

      # All standard structure type names.
      STANDARD = Set{
        DOCUMENT, PART, ART, SECT, DIV, BLOCKQUOTE, CAPTION, TOC, TOCI,
        INDEX, NONSTRUCT, PRIVATE,
        P, H, H1, H2, H3, H4, H5, H6,
        L, LI, LBL, LBODY,
        TABLE, TR, TH, TD, THEAD, TBODY, TFOOT,
        SPAN, QUOTE, NOTE, REFERENCE, BIBENTRY, CODE, LINK, ANNOT,
        FIGURE, FORMULA, FORM,
      }

      # `true` if `name` is one of the standard structure types.
      # Non-standard roles are valid only when mapped through the
      # StructTreeRoot /RoleMap.
      def self.standard?(name : String) : Bool
        STANDARD.includes?(name)
      end

      # Maps a heading level (1..6) to its `Hn` tag. Levels outside
      # 1..6 fall back to the generic `H` tag (PDF has no H7+).
      def self.heading(level : Int32) : String
        case level
        when 1 then H1
        when 2 then H2
        when 3 then H3
        when 4 then H4
        when 5 then H5
        when 6 then H6
        else        H
        end
      end
    end
  end
end
