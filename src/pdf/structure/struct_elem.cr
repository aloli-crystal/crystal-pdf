module PDF
  module Structure
    # A structure element — a node in the logical structure tree
    # (PDF 32000-1 § 14.7.2). Each element carries a structure type
    # (`/S`, one of `Tag`'s constants or a custom role) and may hold
    # child structure elements and/or marked-content leaves.
    #
    # Optional accessibility attributes :
    # * `title`        → `/T`   human-readable title of the element
    # * `alt`          → `/Alt` alternate description (figures, etc.)
    # * `actual_text`  → `/ActualText` exact text the element stands for
    # * `lang`         → `/Lang` BCP-47 language tag for this subtree
    # * `expansion`    → `/E`   expanded form of an abbreviation
    #
    # Marked-content leaves (palier 0.7.1) tie the element to the
    # glyphs actually drawn on a page : `add_mcid(page, mcid)` records
    # a (page, MCID) pair which is emitted in `/K` as a marked-content
    # reference (MCR) dictionary. This is what a PDF/UA validator
    # follows from the structure tree down to the rendered content.
    class StructElem
      # Structure type (`/S`). A `Tag` constant or a custom role.
      property type : String

      property title : String?
      property alt : String?
      property actual_text : String?
      property lang : String?
      property expansion : String?

      # Child structure elements, in document order.
      getter children : Array(StructElem)

      # Marked-content leaves : (page, MCID) pairs on which this
      # element's content was drawn.
      getter mcids : Array({Page, Int32})

      # Object ID assigned during `StructTree#finalize!`, so children
      # can reference this element as their `/P` (parent). Nil until
      # finalized.
      property pdf_object_id : Int32?

      def initialize(
        @type : String,
        *,
        title : String? = nil,
        alt : String? = nil,
        actual_text : String? = nil,
        lang : String? = nil,
        expansion : String? = nil,
      )
        @title = title
        @alt = alt
        @actual_text = actual_text
        @lang = lang
        @expansion = expansion
        @children = [] of StructElem
        @mcids = [] of {Page, Int32}
      end

      # Appends a child structure element and returns it (so callers
      # can chain `add`/`<<` to build nested trees fluently).
      def add(child : StructElem) : StructElem
        @children << child
        child
      end

      # ditto
      def <<(child : StructElem) : StructElem
        add(child)
      end

      # Convenience : create a child element of the given type, append
      # it, and return it.
      def add(type : String, **opts) : StructElem
        add(StructElem.new(type, **opts))
      end

      # Links this element to a marked-content sequence (MCID) drawn
      # on `page` (the value returned by `Page#marked_content`).
      # Returns self for chaining.
      def add_mcid(page : Page, mcid : Int32) : StructElem
        @mcids << {page, mcid}
        self
      end

      # Builds the `/StructElem` dictionary. `parent_ref` is the `/P`
      # back-reference ; `kid_refs` are the already-registered child
      # *element* references in document order. Marked-content leaves
      # are emitted as MCR dictionaries built from `@mcids`. The
      # caller (StructTree) owns object registration so parent/child
      # IDs are consistent.
      def to_dictionary(parent_ref : Objects::Reference, kid_refs : Array(Objects::Reference)) : Objects::Dictionary
        dict = Objects::Dictionary.new
        dict["Type"] = Objects::Name.new("StructElem")
        dict["S"] = Objects::Name.new(@type)
        dict["P"] = parent_ref

        if t = @title
          dict["T"] = Objects::Str.unicode(t)
        end
        if a = @alt
          dict["Alt"] = Objects::Str.unicode(a)
        end
        if at = @actual_text
          dict["ActualText"] = Objects::Str.unicode(at)
        end
        if l = @lang
          dict["Lang"] = Objects::Str.new(l)
        end
        if e = @expansion
          dict["E"] = Objects::Str.unicode(e)
        end

        # Build /K from child element refs followed by MCR dicts for
        # the marked-content leaves.
        kids = [] of Objects::Base
        kid_refs.each { |r| kids << r.as(Objects::Base) }
        @mcids.each { |(page, mcid)| kids << build_mcr(page, mcid).as(Objects::Base) }

        case kids.size
        when 0
          # no children — leaf with no content (unusual but allowed)
        when 1
          dict["K"] = kids.first
        else
          arr = Objects::Array.new
          kids.each { |k| arr << k }
          dict["K"] = arr
        end

        dict
      end

      # Builds a marked-content reference (MCR) dictionary pointing at
      # MCID `mcid` on `page` (PDF 32000-1 § 14.7.4.3, table 324).
      private def build_mcr(page : Page, mcid : Int32) : Objects::Dictionary
        mcr = Objects::Dictionary.new
        mcr["Type"] = Objects::Name.new("MCR")
        mcr["Pg"] = page.page_reference
        mcr["MCID"] = Objects::Number.new(mcid)
        mcr
      end
    end
  end
end
