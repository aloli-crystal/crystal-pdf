module PDF
  module Structure
    # A structure element — a node in the logical structure tree
    # (PDF 32000-1 § 14.7.2). Each element carries a structure type
    # (`/S`, one of `Tag`'s constants or a custom role) and may hold
    # child structure elements.
    #
    # Optional accessibility attributes :
    # * `title`        → `/T`   human-readable title of the element
    # * `alt`          → `/Alt` alternate description (figures, etc.)
    # * `actual_text`  → `/ActualText` exact text the element stands for
    # * `lang`         → `/Lang` BCP-47 language tag for this subtree
    # * `expansion`    → `/E`   expanded form of an abbreviation
    #
    # NOTE (palier 0.7.0) : children are restricted to other
    # `StructElem`s. Linking a structure element to *marked content*
    # in a page (via MCID) arrives in palier 0.7.1 — that is what
    # actually ties the tree to rendered glyphs for PDF/UA.
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

      # Builds the `/StructElem` dictionary. `parent_ref` is the `/P`
      # back-reference ; `kid_refs` are the already-registered child
      # element references in document order. The caller (StructTree)
      # owns object registration so parent/child IDs are consistent.
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

        unless kid_refs.empty?
          if kid_refs.size == 1
            dict["K"] = kid_refs.first
          else
            arr = Objects::Array.new
            kid_refs.each { |r| arr << r }
            dict["K"] = arr
          end
        end

        dict
      end
    end
  end
end
