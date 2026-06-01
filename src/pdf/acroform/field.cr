module PDF
  module AcroForm
    # Base class for an AcroForm field. A field is materialized as a
    # combined Field + Widget annotation dictionary (PDF spec § 12.7.3.1) —
    # the same indirect object is referenced both by /Fields of /AcroForm
    # and by /Annots of its page.
    abstract class Field
      # Field name (`/T`). Must be unique within the document.
      getter name : String

      # Page hosting the widget annotation.
      getter page : Page

      # Widget rectangle on the page : `{x0, y0, x1, y1}` in points.
      getter rect : Tuple(Float64, Float64, Float64, Float64)

      # Field flags integer (`/Ff`). Built from the constituent flags
      # in `#build_flags`.
      property flags : Int32 = 0

      # User-facing flags applicable to every field type.
      property required : Bool = false
      property read_only : Bool = false
      property no_export : Bool = false

      # The combined Field + Widget dictionary. Populated lazily by
      # `#dict` to allow subclasses to customize after construction.
      @dict : Objects::Dictionary?

      def initialize(
        @name : String,
        @page : Page,
        @rect : Tuple(Float64, Float64, Float64, Float64),
      )
      end

      # Returns the combined Field + Widget dictionary, building it
      # once and caching.
      def dict : Objects::Dictionary
        @dict ||= build_dict
      end

      protected def build_dict : Objects::Dictionary
        d = Objects::Dictionary.new

        # Annotation half
        d["Type"] = Objects::Name.new("Annot")
        d["Subtype"] = Objects::Name.new("Widget")
        d["Rect"] = build_rect_array
        d["F"] = Objects::Number.new(4) # Print flag (bit 3) — widget appears on print

        # Field half
        d["FT"] = Objects::Name.new(field_type_name)
        d["T"] = Objects::Str.unicode(@name)
        d["Ff"] = Objects::Number.new(build_flags)

        # Subclass-specific entries (V, DV, Opt, Q, MaxLen…)
        configure(d)

        d
      end

      # Subclasses override to set field-specific entries.
      protected abstract def configure(d : Objects::Dictionary) : Nil

      # Subclasses override to return the PDF field type name
      # (`Tx`, `Btn`, `Ch`, `Sig`).
      protected abstract def field_type_name : String

      # Builds the `/Ff` flags integer. Base implementation handles
      # common flags ; subclasses override and call `super | own_bits`.
      protected def build_flags : Int32
        f = @flags
        f |= 1 << 0 if @read_only # bit 1
        f |= 1 << 1 if @required  # bit 2
        f |= 1 << 2 if @no_export # bit 3
        f
      end

      private def build_rect_array : Objects::Array
        arr = Objects::Array.new
        arr << Objects::Number.new(@rect[0])
        arr << Objects::Number.new(@rect[1])
        arr << Objects::Number.new(@rect[2])
        arr << Objects::Number.new(@rect[3])
        arr
      end
    end
  end
end
