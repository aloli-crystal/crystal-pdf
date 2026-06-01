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
      end
    end
  end
end
