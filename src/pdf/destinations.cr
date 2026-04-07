# Named destinations for PDF documents.
#
# Destinations (Section 12.3.2 of PDF spec) define specific views
# of pages in a document. They are used by annotations, outline items,
# and the document's name tree to enable internal navigation.
#
# Ported from PDF::Core::Destinations (prawnpdf/pdf-core).

module PDF
  # Factory for creating destination arrays.
  #
  # A destination array specifies a page and a view of that page.
  # The first element is always a reference to the target page;
  # the remaining elements define the view type and parameters.
  module Destination
    # Creates a destination that displays the page at the given position
    # and zoom level.
    #
    # ```
    # dest = PDF::Destination.xyz(page_ref, left: 0, top: 842, zoom: 1.0)
    # ```
    def self.xyz(page_ref : Objects::Reference, left : Number? = nil, top : Number? = nil, zoom : Number? = nil) : Objects::Array
      arr = Objects::Array.new
      arr << page_ref
      arr << Objects::Name.new("XYZ")
      arr << (left ? Objects::Number.new(left) : Objects::Null.new)
      arr << (top ? Objects::Number.new(top) : Objects::Null.new)
      arr << (zoom ? Objects::Number.new(zoom) : Objects::Null.new)
      arr
    end

    # Creates a destination that fits the entire page in the window.
    #
    # ```
    # dest = PDF::Destination.fit(page_ref)
    # ```
    def self.fit(page_ref : Objects::Reference) : Objects::Array
      arr = Objects::Array.new
      arr << page_ref
      arr << Objects::Name.new("Fit")
      arr
    end

    # Creates a destination that fits the page width in the window,
    # with the given top coordinate at the top of the window.
    #
    # ```
    # dest = PDF::Destination.fit_horizontally(page_ref, top: 842)
    # ```
    def self.fit_horizontally(page_ref : Objects::Reference, top : Number) : Objects::Array
      arr = Objects::Array.new
      arr << page_ref
      arr << Objects::Name.new("FitH")
      arr << Objects::Number.new(top)
      arr
    end

    # Creates a destination that fits the page height in the window,
    # with the given left coordinate at the left of the window.
    #
    # ```
    # dest = PDF::Destination.fit_vertically(page_ref, left: 0)
    # ```
    def self.fit_vertically(page_ref : Objects::Reference, left : Number) : Objects::Array
      arr = Objects::Array.new
      arr << page_ref
      arr << Objects::Name.new("FitV")
      arr << Objects::Number.new(left)
      arr
    end

    # Creates a destination that fits the given rectangle in the window.
    #
    # ```
    # dest = PDF::Destination.fit_rect(page_ref, left: 0, bottom: 0, right: 595, top: 842)
    # ```
    def self.fit_rect(page_ref : Objects::Reference, left : Number, bottom : Number, right : Number, top : Number) : Objects::Array
      arr = Objects::Array.new
      arr << page_ref
      arr << Objects::Name.new("FitR")
      arr << Objects::Number.new(left)
      arr << Objects::Number.new(bottom)
      arr << Objects::Number.new(right)
      arr << Objects::Number.new(top)
      arr
    end

    # Creates a destination that fits the page's bounding box in the window.
    #
    # ```
    # dest = PDF::Destination.fit_bounds(page_ref)
    # ```
    def self.fit_bounds(page_ref : Objects::Reference) : Objects::Array
      arr = Objects::Array.new
      arr << page_ref
      arr << Objects::Name.new("FitB")
      arr
    end

    # Creates a destination that fits the bounding box width,
    # with the given top coordinate.
    def self.fit_bounds_horizontally(page_ref : Objects::Reference, top : Number) : Objects::Array
      arr = Objects::Array.new
      arr << page_ref
      arr << Objects::Name.new("FitBH")
      arr << Objects::Number.new(top)
      arr
    end

    # Creates a destination that fits the bounding box height,
    # with the given left coordinate.
    def self.fit_bounds_vertically(page_ref : Objects::Reference, left : Number) : Objects::Array
      arr = Objects::Array.new
      arr << page_ref
      arr << Objects::Name.new("FitBV")
      arr << Objects::Number.new(left)
      arr
    end
  end
end
