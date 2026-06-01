module PDF
  module AcroForm
    # Checkbox — `/FT /Btn` without `Pushbutton`/`Radio` flags
    # (PDF spec § 12.7.4.2).
    #
    # State values : `/Yes` (checked) and `/Off` (unchecked).
    #
    # ```
    # form.checkbox("rgpd_consent", page: page, x: 100, y: 650, size: 12)
    # form.checkbox("newsletter", page: page, x: 100, y: 620, checked: true)
    # ```
    class Checkbox < Field
      property checked : Bool = false

      def initialize(
        name : String,
        page : Page,
        rect : Tuple(Float64, Float64, Float64, Float64),
        @checked : Bool = false,
      )
        super(name, page, rect)
      end

      protected def field_type_name : String
        "Btn"
      end

      protected def configure(d : Objects::Dictionary) : Nil
        state = @checked ? "Yes" : "Off"
        d["V"] = Objects::Name.new(state)
        d["DV"] = Objects::Name.new(state)
        # `/AS` (current appearance state) — same value as V for
        # widgets without a separate appearance stream.
        d["AS"] = Objects::Name.new(state)

        # /AP /N appearance dictionary with two states. This matches
        # what reliable viewers expect (Acrobat, Preview) and avoids
        # leaning on /NeedAppearances true alone, which is unreliable
        # for non-text fields across viewers.
        on_ref = page.document.register_object(build_appearance(true))
        off_ref = page.document.register_object(build_appearance(false))
        ap_n = Objects::Dictionary.new
        ap_n["Yes"] = on_ref.reference
        ap_n["Off"] = off_ref.reference
        ap = Objects::Dictionary.new
        ap["N"] = ap_n
        d["AP"] = ap
      end

      # Form XObject that draws the checkbox in its `on` or `off`
      # state. Both states draw the bordering square ; the `on`
      # state additionally draws a diagonal cross inside.
      private def build_appearance(checked : Bool) : Objects::Stream
        size = (@rect[2] - @rect[0]).to_f
        stream = Objects::Stream.new
        stream["Type"] = Objects::Name.new("XObject")
        stream["Subtype"] = Objects::Name.new("Form")
        stream["FormType"] = Objects::Number.new(1)

        bbox = Objects::Array.new
        bbox << Objects::Number.new(0)
        bbox << Objects::Number.new(0)
        bbox << Objects::Number.new(size)
        bbox << Objects::Number.new(size)
        stream["BBox"] = bbox

        resources = Objects::Dictionary.new
        procset = Objects::Array.new
        procset << Objects::Name.new("PDF")
        resources["ProcSet"] = procset
        stream["Resources"] = resources

        io = IO::Memory.new
        io << "q\n"
        io << "0 0 0 RG\n"
        io << "0.5 w\n"
        # Bordering square — leave 0.5 pt margin so the stroke fits
        # cleanly inside the BBox.
        io << "0.5 0.5 " << format_num(size - 1.0) << " " << format_num(size - 1.0) << " re\n"
        io << "S\n"
        if checked
          # Diagonal cross drawn inside a centred square of ~70 % of
          # the BBox.
          margin = size * 0.2
          io << "1 w\n"
          io << format_num(margin) << " " << format_num(margin) << " m\n"
          io << format_num(size - margin) << " " << format_num(size - margin) << " l\n"
          io << format_num(margin) << " " << format_num(size - margin) << " m\n"
          io << format_num(size - margin) << " " << format_num(margin) << " l\n"
          io << "S\n"
        end
        io << "Q\n"

        stream.data = io.to_s
        stream
      end

      private def format_num(n : Float64) : String
        s = n.round(4).to_s
        s = s.rstrip('0').rstrip('.') if s.includes?('.')
        s.empty? ? "0" : s
      end
    end
  end
end
