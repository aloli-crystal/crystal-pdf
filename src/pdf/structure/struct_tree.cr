module PDF
  module Structure
    # The document logical structure tree — materialised as the
    # `/StructTreeRoot` (PDF 32000-1 § 14.7.2). Holds the top-level
    # structure elements and an optional `/RoleMap` that maps custom
    # roles to standard ones.
    #
    # Built lazily and emitted by `Document` only when it contains at
    # least one element, so untagged documents are completely
    # unaffected (no `/StructTreeRoot`, no `/MarkInfo`).
    #
    # NOTE (palier 0.7.0) : this builds the *element hierarchy* only.
    # The `/ParentTree` (number tree mapping marked-content IDs back
    # to their structure element) and the marked-content operators in
    # page streams come in palier 0.7.1. Until then the tree is valid
    # PDF but does not yet point at rendered content — it is the
    # scaffolding the next palier fills in.
    class StructTree
      # Top-level structure elements (typically a single Document).
      getter roots : Array(StructElem)

      # Optional custom-role → standard-role map (`/RoleMap`).
      getter role_map : Hash(String, String)

      def initialize
        @roots = [] of StructElem
        @role_map = {} of String => String
      end

      # `true` if no structure element has been added.
      def empty? : Bool
        @roots.empty?
      end

      # Appends a top-level structure element and returns it.
      def add(elem : StructElem) : StructElem
        @roots << elem
        elem
      end

      # ditto
      def <<(elem : StructElem) : StructElem
        add(elem)
      end

      # Convenience : create a top-level element of `type`, append it,
      # return it.
      def add(type : String, **opts) : StructElem
        add(StructElem.new(type, **opts))
      end

      # Registers a custom-role → standard-role mapping.
      def map_role(custom : String, standard : String) : Nil
        @role_map[custom] = standard
      end

      # Builds the `/StructTreeRoot` and every descendant element as
      # indirect objects in `document`, and returns the root
      # reference for the catalog.
      #
      # Object IDs are pre-allocated in a first pass so each element's
      # `/P` (parent) and `/K` (kids) references resolve correctly
      # despite the circular nature of the tree.
      def finalize!(document : Document) : Objects::Reference
        root_id = document.allocate_object_id
        root_ref = Objects::Reference.new(root_id)

        # Pre-allocate IDs for the whole tree (DFS), so kids can name
        # their parent and parents can name their kids.
        assign_ids(@roots, document)

        # Build and register each element dict.
        @roots.each { |elem| build_element(elem, root_ref, document) }

        # Build the StructTreeRoot dict.
        root_dict = Objects::Dictionary.new
        root_dict["Type"] = Objects::Name.new("StructTreeRoot")

        kids = @roots.map { |e| Objects::Reference.new(e.pdf_object_id.not_nil!) }
        if kids.size == 1
          root_dict["K"] = kids.first
        elsif kids.size > 1
          arr = Objects::Array.new
          kids.each { |r| arr << r }
          root_dict["K"] = arr
        end

        unless @role_map.empty?
          rm = Objects::Dictionary.new
          @role_map.each { |custom, std| rm[custom] = Objects::Name.new(std) }
          root_dict["RoleMap"] = rm
        end

        document.objects << Objects::Indirect.new(root_id, root_dict)
        root_ref
      end

      # First pass : assign an object ID to every element (DFS order).
      private def assign_ids(elems : Array(StructElem), document : Document) : Nil
        elems.each do |elem|
          elem.pdf_object_id = document.allocate_object_id
          assign_ids(elem.children, document)
        end
      end

      # Second pass : build & register an element and its descendants.
      private def build_element(elem : StructElem, parent_ref : Objects::Reference, document : Document) : Nil
        self_ref = Objects::Reference.new(elem.pdf_object_id.not_nil!)

        # Recurse first so children are registered ; collect their refs.
        kid_refs = elem.children.map do |child|
          build_element(child, self_ref, document)
          Objects::Reference.new(child.pdf_object_id.not_nil!)
        end

        dict = elem.to_dictionary(parent_ref, kid_refs)
        document.objects << Objects::Indirect.new(elem.pdf_object_id.not_nil!, dict)
      end
    end
  end
end
