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
      COMBO = 1 << 17 # bit 18 (1 = combo / dropdown, 0 = list)
      EDIT  = 1 << 18 # bit 19 (editable combo)
      SORT  = 1 << 19 # bit 20 (sort options on display)

      getter options : Array(String) | Hash(String, String)
      property value : String? = nil
      property default_value : String? = nil
      property editable : Bool = false

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
      end
    end
  end
end
