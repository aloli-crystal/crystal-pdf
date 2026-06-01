module PDF
  module AcroForm
    # Choice field rendered as a dropdown (combo box) — `/FT /Ch`
    # with `Combo` flag set (PDF spec § 12.7.4.4).
    #
    # `options` may be either an `Array(String)` (export value = display
    # value) or a `Hash(String, String)` (export value => display value).
    # When a Hash is given, /Opt is emitted as a list of two-element
    # arrays `[export, display]` per PDF spec § 12.7.4.4.
    #
    # ```
    # # Simple list — value displayed = value stored
    # form.dropdown(
    #   "pays",
    #   page: page,
    #   options: ["FR", "BE", "CH", "CA"],
    #   x: 100, y: 550, width: 80, height: 20,
    #   default: "FR",
    # )
    #
    # # Hash — value stored differs from value displayed
    # form.dropdown(
    #   "pays",
    #   page: page,
    #   options: {"FR" => "France", "BE" => "Belgique"},
    #   x: 100, y: 550, width: 120, height: 20,
    #   default: "FR",
    # )
    # ```
    class Dropdown < Field
      # Field flag bits specific to choice fields (PDF spec table 230)
      COMBO                = 1 << 17 # bit 18 (1 = combo / dropdown, 0 = list)
      EDIT                 = 1 << 18 # bit 19 (editable combo)
      SORT                 = 1 << 19 # bit 20 (sort options on display)
      DO_NOT_SPELL_CHECK   = 1 << 22 # bit 23
      COMMIT_ON_SEL_CHANGE = 1 << 26 # bit 27

      getter options : Array(String) | Hash(String, String)
      property value : String? = nil
      property default_value : String? = nil
      property editable : Bool = false

      # When `do_not_spell_check` is true and the dropdown is also
      # editable, viewers should not run their spell checker on the
      # typed value.
      property do_not_spell_check : Bool = false

      # When `commit_on_sel_change` is true the field commits its
      # value as soon as the user picks an option, rather than only
      # on focus change. Useful for forms that drive other fields.
      property commit_on_sel_change : Bool = false

      def initialize(
        name : String,
        page : Page,
        rect : Tuple(Float64, Float64, Float64, Float64),
        @options : Array(String) | Hash(String, String),
        @value : String? = nil,
        @default_value : String? = nil,
        @editable : Bool = false,
      )
        codes = option_codes
        if codes.empty?
          raise ArgumentError.new("Dropdown '#{name}' needs at least one option")
        end
        if v = @value
          unless @editable || codes.includes?(v)
            raise ArgumentError.new("Dropdown '#{name}' value=#{v.inspect} not in options")
          end
        end
        super(name, page, rect)
      end

      # Export values (codes) in declaration order. For an Array
      # `options`, those are the entries themselves; for a Hash,
      # the keys. The PDF /V entry stores one of these codes.
      def option_codes : Array(String)
        case opts = @options
        when Array(String)        then opts
        when Hash(String, String) then opts.keys
        else                           [] of String
        end
      end

      # Display labels keyed by code. Returns the Hash form as-is,
      # or nil for the Array form (display = code).
      def option_labels : Hash(String, String)?
        @options.as?(Hash(String, String))
      end

      protected def field_type_name : String
        "Ch"
      end

      protected def build_flags : Int32
        f = super
        f |= COMBO
        f |= EDIT if @editable
        f |= DO_NOT_SPELL_CHECK if @do_not_spell_check
        f |= COMMIT_ON_SEL_CHANGE if @commit_on_sel_change
        f
      end

      protected def configure(d : Objects::Dictionary) : Nil
        opts = Objects::Array.new
        case raw = @options
        when Array(String)
          raw.each { |o| opts << Objects::Str.unicode(o) }
        when Hash(String, String)
          # /Opt entries as two-element arrays [export, display]
          # (PDF spec § 12.7.4.4).
          raw.each do |code, label|
            pair = Objects::Array.new
            pair << Objects::Str.unicode(code)
            pair << Objects::Str.unicode(label)
            opts << pair
          end
        end
        d["Opt"] = opts

        if v = @value
          d["V"] = Objects::Str.unicode(v)
        end
        if dv = @default_value
          d["DV"] = Objects::Str.unicode(dv)
        end

        # /AP /N normal appearance — the frame and dropdown arrow.
        # The current value is *not* drawn here ; viewers regenerate
        # that part on top via /NeedAppearances. Drawing the arrow
        # in our own appearance makes the field visually identifiable
        # as a dropdown even on viewers that fail to regenerate
        # appearances reliably.
        ap_ref = page.document.register_object(build_appearance)
        ap_n = Objects::Dictionary.new
        ap_n["N"] = ap_ref.reference
        d["AP"] = ap_n
      end

      private def build_appearance : Objects::Stream
        w = (@rect[2] - @rect[0]).to_f
        h = (@rect[3] - @rect[1]).to_f
        stream = Objects::Stream.new
        stream["Type"] = Objects::Name.new("XObject")
        stream["Subtype"] = Objects::Name.new("Form")
        stream["FormType"] = Objects::Number.new(1)

        bbox = Objects::Array.new
        bbox << Objects::Number.new(0)
        bbox << Objects::Number.new(0)
        bbox << Objects::Number.new(w)
        bbox << Objects::Number.new(h)
        stream["BBox"] = bbox

        resources = Objects::Dictionary.new
        procset = Objects::Array.new
        procset << Objects::Name.new("PDF")
        resources["ProcSet"] = procset
        stream["Resources"] = resources

        # Arrow geometry — small downward triangle in the right
        # ~12 % of the field, vertically centred.
        arrow_w = h * 0.4
        arrow_h = h * 0.25
        arrow_left = w - arrow_w - 4.0
        arrow_top = (h + arrow_h) / 2
        arrow_bottom = (h - arrow_h) / 2

        io = IO::Memory.new
        io << "q\n"
        io << "0 0 0 RG\n"
        io << "0.5 w\n"
        # Frame around the whole field.
        io << "0.5 0.5 " << format_num(w - 1.0) << " " << format_num(h - 1.0) << " re\n"
        io << "S\n"
        # Filled triangle pointing down.
        io << "0 0 0 rg\n"
        io << format_num(arrow_left) << " " << format_num(arrow_top) << " m\n"
        io << format_num(arrow_left + arrow_w) << " " << format_num(arrow_top) << " l\n"
        io << format_num(arrow_left + arrow_w / 2) << " " << format_num(arrow_bottom) << " l\n"
        io << "h\nf\n"
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
