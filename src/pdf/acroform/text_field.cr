module PDF
  module AcroForm
    # Text input field — `/FT /Tx` (PDF spec § 12.7.4.3).
    #
    # ```
    # form.text_field("nom", page: page, x: 100, y: 700, width: 200, height: 20)
    # form.text_field("commentaire", page: page, x: 100, y: 600, width: 300, height: 80, multiline: true)
    # ```
    class TextField < Field
      # Field flag bits (PDF spec table 228)
      MULTILINE     = 1 << 12 # bit 13
      PASSWORD      = 1 << 13 # bit 14
      FILE_SELECT   = 1 << 20 # bit 21
      DO_NOT_SCROLL = 1 << 23 # bit 24

      property value : String? = nil
      property default_value : String? = nil
      property max_length : Int32? = nil
      property multiline : Bool = false
      property password : Bool = false
      property alignment : Symbol = :left # :left, :center, :right

      def initialize(
        name : String,
        page : Page,
        rect : Tuple(Float64, Float64, Float64, Float64),
        @value : String? = nil,
        @default_value : String? = nil,
        @max_length : Int32? = nil,
        @multiline : Bool = false,
        @password : Bool = false,
        @alignment : Symbol = :left,
      )
        super(name, page, rect)
      end

      protected def field_type_name : String
        "Tx"
      end

      protected def build_flags : Int32
        f = super
        f |= MULTILINE if @multiline
        f |= PASSWORD if @password
        f
      end

      protected def configure(d : Objects::Dictionary) : Nil
        if v = @value
          d["V"] = Objects::Str.unicode(v)
        end
        if dv = @default_value
          d["DV"] = Objects::Str.unicode(dv)
        end
        if ml = @max_length
          d["MaxLen"] = Objects::Number.new(ml)
        end
        q = case @alignment
            when :center then 1
            when :right  then 2
            else              0
            end
        d["Q"] = Objects::Number.new(q) unless q == 0
      end
    end
  end
end
