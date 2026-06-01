module PDF
  module AcroForm
    # Radio button group — `/FT /Btn` with `Radio` flag set
    # (PDF spec § 12.7.4.2.3).
    #
    # In PDF, a radio group is a *parent field* with multiple *kid*
    # widget annotations. All kids share the same `/T` (the parent's
    # name), and each kid has a distinct `/AS` value that names its
    # state. The parent's `/V` holds the currently selected state.
    #
    # ```
    # form.radio_group(
    #   "genre",
    #   page: page,
    #   options: ["M", "F", "Autre"],
    #   x: 100, y: 600,
    #   spacing: 30,
    #   size: 12,
    #   default: "M",
    # )
    # ```
    class RadioGroup < Field
      # Field flag bits specific to radio buttons
      PUSHBUTTON       = 1 << 16 # bit 17 (not set here)
      RADIO            = 1 << 15 # bit 16
      NO_TOGGLE_TO_OFF = 1 << 14 # bit 15
      RADIOS_IN_UNISON = 1 << 25 # bit 26

      # Options for the group. May be either an `Array(String)` (the
      # state codes themselves) or a `Hash(String, String)` mapping
      # codes to user-facing labels. The Hash form lets ALOLI labels
      # diverge from the export codes (e.g. {"C" => "Conforme"}). The
      # labels are *not* embedded in the PDF widget (radio buttons do
      # not show inline text in AcroForm) — the caller positions the
      # labels separately. Only the codes (keys) are used as `/AS`
      # state names on kids and as `/V` on the parent.
      getter options : Array(String) | Hash(String, String)

      # Layout : top-left of the first button, vertical spacing,
      # button square size (points).
      getter origin : Tuple(Float64, Float64)
      getter spacing : Float64
      getter size : Float64

      # Currently selected option, or nil for none.
      property selected : String? = nil

      property no_toggle_to_off : Bool = true

      # When `radios_in_unison` is true, radio buttons that share
      # the same value name (across multiple groups) are toggled
      # together. Useful for "yes/no" radios duplicated on every
      # page. PDF spec § 12.7.4.2.3.
      property radios_in_unison : Bool = false

      # Pre-allocated object ID for this radio field, set by
      # `Form#finalize!` *before* the parent dict is built so kids
      # can reference `/Parent <id 0 R>`. Without this, Acrobat and
      # Preview render the kids invisible (PDF spec § 12.7.4.2.3).
      property parent_object_id : Int32? = nil

      def initialize(
        name : String,
        page : Page,
        @options : Array(String) | Hash(String, String),
        @origin : Tuple(Float64, Float64),
        @spacing : Float64 = 20.0,
        @size : Float64 = 12.0,
        @selected : String? = nil,
        @no_toggle_to_off : Bool = true,
      )
        codes = option_codes
        if codes.empty?
          raise ArgumentError.new("RadioGroup '#{name}' needs at least one option")
        end
        unless codes.uniq.size == codes.size
          raise ArgumentError.new("RadioGroup '#{name}' options must be unique")
        end
        if sel = @selected
          unless codes.includes?(sel)
            raise ArgumentError.new("RadioGroup '#{name}' selected=#{sel.inspect} not in options")
          end
        end

        # Parent rect = bounding box covering all kids. Computed for
        # informational purposes ; viewers use the kids' /Rect.
        x, y_top = @origin
        x1 = x + @size
        y0 = y_top - (codes.size - 1) * @spacing
        y1 = y_top + @size
        super(name, page, {x, y0, x1, y1})
      end

      # Export codes (state names) in declaration order. For an Array
      # `options`, those are the entries themselves; for a Hash, the
      # keys. These become `/AS` values on kid widgets and `/V` on
      # the parent.
      def option_codes : Array(String)
        case opts = @options
        when Array(String)        then opts
        when Hash(String, String) then opts.keys
        else                           [] of String
        end
      end

      # Display labels keyed by code, or nil if the Array form was
      # used. Useful to the caller (typically a document converter)
      # to draw the labels alongside the radio widgets.
      def option_labels : Hash(String, String)?
        @options.as?(Hash(String, String))
      end

      protected def field_type_name : String
        "Btn"
      end

      protected def build_flags : Int32
        f = super
        f |= RADIO
        f |= NO_TOGGLE_TO_OFF if @no_toggle_to_off
        f |= RADIOS_IN_UNISON if @radios_in_unison
        f
      end

      protected def configure(d : Objects::Dictionary) : Nil
        state = @selected || "Off"
        d["V"] = Objects::Name.new(state)
        d["DV"] = Objects::Name.new(state)
        # The parent field is *not* itself a widget annotation —
        # remove the widget-side entries that `Field#build_dict` set,
        # and add /Kids instead. We strip /Subtype, /Rect, /F, /AS on
        # the parent ; they belong on each kid.
        d.delete("Subtype")
        d.delete("Rect")
        d.delete("F")
        d.delete("AS")
        d.delete("Type") # /Type Annot is removed too — parent is a Field, not an Annot

        parent_id = @parent_object_id
        raise "RadioGroup '#{@name}' has no parent_object_id — Form#finalize! must set it before #configure runs" if parent_id.nil?
        parent_ref = Objects::Reference.new(parent_id)

        kids = Objects::Array.new
        x, y_top = @origin
        option_codes.each_with_index do |opt, i|
          y0 = y_top - (i + 1) * @spacing + @spacing
          kid = build_kid_widget(opt, x, y0, parent_ref)
          kid_obj = page.document.register_object(kid)
          kids << kid_obj.reference
          page.add_annotation_ref(kid_obj.reference)
        end
        d["Kids"] = kids
      end

      # Each kid is a Widget annotation only (no field metadata —
      # everything lives on the parent except /AS).
      #
      # Critical detail : each kid MUST have an `/AP /N` appearance
      # dictionary with two entries — one keyed by the state name
      # (`/<state>`) for "selected" and one keyed by `/Off` for "not
      # selected". Without this, viewers render nothing at all for
      # radio kids (unlike checkboxes/text fields which fall back to
      # a default look). Cf. PDF spec § 12.7.4.2.3.
      private def build_kid_widget(state : String, x : Float64, y : Float64, parent_ref : Objects::Reference) : Objects::Dictionary
        k = Objects::Dictionary.new
        k["Type"] = Objects::Name.new("Annot")
        k["Subtype"] = Objects::Name.new("Widget")
        # /Parent — required by Acrobat and Preview. Without it the
        # widgets are not linked to the field and viewers either show
        # nothing (Acrobat, Preview) or show only the appearance
        # without exclusivity behavior (Firefox, Chrome).
        k["Parent"] = parent_ref

        rect = Objects::Array.new
        rect << Objects::Number.new(x)
        rect << Objects::Number.new(y)
        rect << Objects::Number.new(x + @size)
        rect << Objects::Number.new(y + @size)
        k["Rect"] = rect

        k["F"] = Objects::Number.new(4) # Print
        # /AS is the kid's *appearance state*. When equal to /V on
        # the parent, the kid renders as selected.
        k["AS"] = Objects::Name.new(@selected == state ? state : "Off")

        # /AP /N appearance dictionary — required for radio buttons.
        on_ref = page.document.register_object(build_circle_appearance(true))
        off_ref = page.document.register_object(build_circle_appearance(false))
        ap_n = Objects::Dictionary.new
        ap_n[state] = on_ref.reference
        ap_n["Off"] = off_ref.reference
        ap = Objects::Dictionary.new
        ap["N"] = ap_n
        k["AP"] = ap

        k
      end

      # Builds a Form XObject that draws a radio button appearance.
      # When `selected` is true, draws an empty outer circle plus a
      # filled inner dot. When false, only the empty outer circle.
      # The BBox is `[0 0 size size]` so the widget /Rect dictates
      # the on-page size and position.
      private def build_circle_appearance(selected : Bool) : Objects::Stream
        stream = Objects::Stream.new
        stream["Type"] = Objects::Name.new("XObject")
        stream["Subtype"] = Objects::Name.new("Form")
        stream["FormType"] = Objects::Number.new(1)

        bbox = Objects::Array.new
        bbox << Objects::Number.new(0)
        bbox << Objects::Number.new(0)
        bbox << Objects::Number.new(@size)
        bbox << Objects::Number.new(@size)
        stream["BBox"] = bbox

        resources = Objects::Dictionary.new
        procset = Objects::Array.new
        procset << Objects::Name.new("PDF")
        resources["ProcSet"] = procset
        stream["Resources"] = resources

        cx = @size / 2
        cy = @size / 2
        r_outer = @size / 2 - 0.5
        r_inner = @size / 4
        kf = 0.5522847498 # Bézier factor for circle approximation

        io = IO::Memory.new
        io << "q\n"
        # Outer ring (border) — thin black stroke.
        io << "0 0 0 RG\n"
        io << "0.5 w\n"
        append_circle(io, cx, cy, r_outer, kf)
        io << "S\n"
        if selected
          # Inner filled dot — black fill.
          io << "0 0 0 rg\n"
          append_circle(io, cx, cy, r_inner, kf)
          io << "f\n"
        end
        io << "Q\n"

        stream.data = io.to_s
        stream
      end

      # Appends a circle (4 Bézier curves) to the content stream.
      private def append_circle(io : IO, cx : Float64, cy : Float64, r : Float64, kf : Float64) : Nil
        io << format_num(cx + r) << " " << format_num(cy) << " m\n"
        io << format_num(cx + r) << " " << format_num(cy + r * kf) << " "
        io << format_num(cx + r * kf) << " " << format_num(cy + r) << " "
        io << format_num(cx) << " " << format_num(cy + r) << " c\n"
        io << format_num(cx - r * kf) << " " << format_num(cy + r) << " "
        io << format_num(cx - r) << " " << format_num(cy + r * kf) << " "
        io << format_num(cx - r) << " " << format_num(cy) << " c\n"
        io << format_num(cx - r) << " " << format_num(cy - r * kf) << " "
        io << format_num(cx - r * kf) << " " << format_num(cy - r) << " "
        io << format_num(cx) << " " << format_num(cy - r) << " c\n"
        io << format_num(cx + r * kf) << " " << format_num(cy - r) << " "
        io << format_num(cx + r) << " " << format_num(cy - r * kf) << " "
        io << format_num(cx + r) << " " << format_num(cy) << " c\n"
      end

      # Formats a float for the PDF content stream — strips trailing
      # zeros to keep the stream compact.
      private def format_num(n : Float64) : String
        s = n.round(4).to_s
        s = s.rstrip('0').rstrip('.') if s.includes?('.')
        s.empty? ? "0" : s
      end
    end
  end
end
