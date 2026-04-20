# Annots support for PDF pages.
#
# PDF annotations (Section 12.5 of PDF spec) are interactive elements
# overlaid on page content. This module provides link annotations
# (for hyperlinks and internal navigation) and text annotations (popups).
#
# Ported from PDF::Core::Annots (prawnpdf/pdf-core).

module PDF
  # Represents a PDF annotation to be added to a page.
  #
  # Annots are stored per-page and serialized as indirect objects
  # in the page's /Annots array.
  class Annot
    # The annotation dictionary entries.
    getter dict : Objects::Dictionary

    def initialize
      @dict = Objects::Dictionary.new
      @dict["Type"] = Objects::Name.new("Annot")
    end

    # Creates a link annotation that opens a URI.
    #
    # ```
    # annot = PDF::Annot.link_uri(
    #   rect: {72, 700, 200, 720},
    #   uri: "https://crystal-lang.org"
    # )
    # page.add_annotation(annot)
    # ```
    def self.link_uri(rect : Tuple(Number, Number, Number, Number), uri : String) : Annot
      annot = new
      annot.dict["Subtype"] = Objects::Name.new("Link")
      annot.dict["Rect"] = build_rect(rect)
      annot.dict["Border"] = Objects::Array.new([0, 0, 0]) # No visible border

      # URI action dictionary
      action = Objects::Dictionary.new
      action["S"] = Objects::Name.new("URI")
      action["URI"] = Objects::Str.new(uri)
      annot.dict["A"] = action

      annot
    end

    # Creates a link annotation that navigates to a named destination
    # within the document.
    #
    # ```
    # annot = PDF::Annot.link_dest(
    #   rect: {72, 700, 200, 720},
    #   dest: "chapter-1"
    # )
    # page.add_annotation(annot)
    # ```
    def self.link_dest(rect : Tuple(Number, Number, Number, Number), dest : String) : Annot
      annot = new
      annot.dict["Subtype"] = Objects::Name.new("Link")
      annot.dict["Rect"] = build_rect(rect)
      annot.dict["Border"] = Objects::Array.new([0, 0, 0])
      annot.dict["Dest"] = Objects::Str.new(dest)
      annot
    end

    # Creates a link annotation with an explicit destination array
    # (e.g., from `Destination.xyz` or `Destination.fit`).
    #
    # ```
    # dest = PDF::Destination.fit(page)
    # annot = PDF::Annot.link_dest_array(
    #   rect: {72, 700, 200, 720},
    #   dest: dest
    # )
    # ```
    def self.link_dest_array(rect : Tuple(Number, Number, Number, Number), dest : Objects::Array) : Annot
      annot = new
      annot.dict["Subtype"] = Objects::Name.new("Link")
      annot.dict["Rect"] = build_rect(rect)
      annot.dict["Border"] = Objects::Array.new([0, 0, 0])
      annot.dict["Dest"] = dest
      annot
    end

    # Creates a text (popup) annotation.
    #
    # ```
    # annot = PDF::Annot.text(
    #   rect: {72, 700, 100, 720},
    #   contents: "This is a comment."
    # )
    # page.add_annotation(annot)
    # ```
    def self.text(rect : Tuple(Number, Number, Number, Number), contents : String) : Annot
      annot = new
      annot.dict["Subtype"] = Objects::Name.new("Text")
      annot.dict["Rect"] = build_rect(rect)
      annot.dict["Contents"] = Objects::Str.unicode(contents)
      annot
    end

    private def self.build_rect(rect : Tuple(Number, Number, Number, Number)) : Objects::Array
      Objects::Array.new([rect[0].to_f, rect[1].to_f, rect[2].to_f, rect[3].to_f])
    end
  end
end
