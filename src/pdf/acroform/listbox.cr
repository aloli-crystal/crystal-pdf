module PDF
  module AcroForm
    # Choice field rendered as a multi-line listbox with optional
    # multi-selection — `/FT /Ch` without `Combo` flag, with
    # `MultiSelect` flag (PDF spec § 12.7.4.4).
    #
    # `options` may be either an `Array(String)` (export value =
    # display value) or a `Hash(String, String)` (export value =>
    # display value). When a Hash is given, /Opt is emitted as a list
    # of two-element arrays `[export, display]` per PDF spec
    # § 12.7.4.4.
    #
    # `value` and `default_value` are arrays of selected codes
    # (always an array, even for a single selection). The PDF /V
    # entry is emitted as either a single string (single selection)
    # or an array of strings (multi-selection) — viewers accept both.
    #
    # ```
    # # Simple list — multi-selection with two defaults
    # form.listbox(
    #   "langues",
    #   page: page,
    #   options: ["FR", "EN", "DE", "IT", "ES"],
    #   x: 100, y: 500, width: 100, height: 80,
    #   value: ["FR", "EN"],
    # )
    #
    # # Hash — codes mapped to user-facing labels
    # form.listbox(
    #   "langues",
    #   page: page,
    #   options: {"fr" => "Français", "en" => "English", "de" => "Deutsch"},
    #   x: 100, y: 500, width: 120, height: 80,
    #   value: ["fr", "en"],
    # )
    # ```
    class Listbox < Field
      # Field flag bits (PDF spec table 230)
      SORT          = 1 << 19 # bit 20 (sort options on display)
      MULTI_SELECT  = 1 << 21 # bit 22 (allow multiple selection)
      DO_NOT_SPELL  = 1 << 22 # bit 23
      COMMIT_ON_SEL = 1 << 26 # bit 27

      getter options : Array(String) | Hash(String, String)
      property value : Array(String)? = nil
      property default_value : Array(String)? = nil
      property sort : Bool = false

      def initialize(
        name : String,
        page : Page,
        rect : Tuple(Float64, Float64, Float64, Float64),
        @options : Array(String) | Hash(String, String),
        @value : Array(String)? = nil,
        @default_value : Array(String)? = nil,
        @sort : Bool = false,
      )
        codes = option_codes
        if codes.empty?
          raise ArgumentError.new("Listbox '#{name}' needs at least one option")
        end
        if vals = @value
          vals.each do |v|
            unless codes.includes?(v)
              raise ArgumentError.new("Listbox '#{name}' value=#{v.inspect} not in options")
            end
          end
        end
        if dvals = @default_value
          dvals.each do |v|
            unless codes.includes?(v)
              raise ArgumentError.new("Listbox '#{name}' default_value=#{v.inspect} not in options")
            end
          end
        end
        super(name, page, rect)
      end

      # Export codes (selectable values) in declaration order. For an
      # Array `options`, those are the entries themselves; for a Hash,
      # the keys.
      def option_codes : Array(String)
        case opts = @options
        when Array(String)        then opts
        when Hash(String, String) then opts.keys
        else                           [] of String
        end
      end

      # Display labels keyed by code, or nil if the Array form was
      # used.
      def option_labels : Hash(String, String)?
        @options.as?(Hash(String, String))
      end

      protected def field_type_name : String
        "Ch"
      end

      protected def build_flags : Int32
        f = super
        f |= MULTI_SELECT
        f |= SORT if @sort
        f
      end

      protected def configure(d : Objects::Dictionary) : Nil
        # /Opt — single value strings or [export, display] pairs
        opts = Objects::Array.new
        case raw = @options
        when Array(String)
          raw.each { |o| opts << Objects::Str.unicode(o) }
        when Hash(String, String)
          raw.each do |code, label|
            pair = Objects::Array.new
            pair << Objects::Str.unicode(code)
            pair << Objects::Str.unicode(label)
            opts << pair
          end
        end
        d["Opt"] = opts

        # /V — single string for one selection, array for many
        # (PDF spec § 12.7.4.4 : "If the field allows multiple
        # selections... shall be an array of text strings").
        write_selection(d, "V", @value)
        write_selection(d, "DV", @default_value)
      end

      private def write_selection(d : Objects::Dictionary, key : String, vals : Array(String)?) : Nil
        return unless vals
        return if vals.empty?
        if vals.size == 1
          d[key] = Objects::Str.unicode(vals.first)
        else
          arr = Objects::Array.new
          vals.each { |v| arr << Objects::Str.unicode(v) }
          d[key] = arr
        end
      end
    end
  end
end
