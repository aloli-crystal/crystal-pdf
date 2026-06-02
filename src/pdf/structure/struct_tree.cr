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

        # Build the /ParentTree — a number tree mapping each page's
        # /StructParents index to an array (indexed by MCID) of the
        # structure elements that own each marked-content sequence.
        build_parent_tree(document, root_dict)

        document.objects << Objects::Indirect.new(root_id, root_dict)
        root_ref
      end

      # Builds `/ParentTree` and `/ParentTreeNextKey` on `root_dict`
      # from the marked-content leaves recorded on the elements.
      private def build_parent_tree(document : Document, root_dict : Objects::Dictionary) : Nil
        # Collect, per page, MCID → owning element reference.
        owners = {} of Page => Hash(Int32, Objects::Reference)
        collect_mcid_owners(@roots, owners)

        # Pages that carry marked content, ordered by their assigned
        # /StructParents index (set in Document#finalize!).
        indexed = document.pages.compact_map do |page|
          if idx = page.struct_parents_index
            {idx, page}
          end
        end
        return if indexed.empty? # no marked content anywhere → no ParentTree
        indexed.sort_by! { |(idx, _page)| idx }

        nums = Objects::Array.new
        max_key = -1
        indexed.each do |(idx, page)|
          mcid_map = owners[page]? || {} of Int32 => Objects::Reference

          arr = Objects::Array.new
          (0...page.mcid_count).each do |mcid|
            ref = mcid_map[mcid]? ||
                  raise "StructTree : MCID #{mcid} on a page is not linked to any structure element (call StructElem#add_mcid for every marked_content)"
            arr << ref
          end

          nums << Objects::Number.new(idx)
          nums << arr
          max_key = idx if idx > max_key
        end

        return if max_key < 0

        parent_tree = Objects::Dictionary.new
        parent_tree["Nums"] = nums
        root_dict["ParentTree"] = parent_tree
        root_dict["ParentTreeNextKey"] = Objects::Number.new(max_key + 1)
      end

      # Walks the tree collecting, per page, a map MCID → element ref.
      private def collect_mcid_owners(elems : Array(StructElem), owners : Hash(Page, Hash(Int32, Objects::Reference))) : Nil
        elems.each do |elem|
          unless elem.mcids.empty?
            self_ref = Objects::Reference.new(elem.pdf_object_id.not_nil!)
            elem.mcids.each do |(page, mcid)|
              (owners[page] ||= {} of Int32 => Objects::Reference)[mcid] = self_ref
            end
          end
          collect_mcid_owners(elem.children, owners)
        end
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
