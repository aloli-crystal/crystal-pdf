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
      MULTILINE          = 1 << 12 # bit 13
      PASSWORD           = 1 << 13 # bit 14
      FILE_SELECT        = 1 << 20 # bit 21
      DO_NOT_SPELL_CHECK = 1 << 22 # bit 23
      DO_NOT_SCROLL      = 1 << 23 # bit 24
      COMB               = 1 << 24 # bit 25

      property value : String? = nil
      property default_value : String? = nil
      property max_length : Int32? = nil
      property multiline : Bool = false
      property password : Bool = false
      property alignment : Symbol = :left # :left, :center, :right

      # When `file_select` is true the field acts as a file picker
      # — the value is interpreted as a file path, not arbitrary
      # text. Forbidden in PDF/A.
      property file_select : Bool = false

      # When `do_not_spell_check` is true viewers should not run their
      # spell checker on the field's contents.
      property do_not_spell_check : Bool = false

      # When `do_not_scroll` is true the field has a fixed visible
      # length — text exceeding the rectangle is truncated rather
      # than scrolled.
      property do_not_scroll : Bool = false

      # When `comb` is true and `max_length` is set, the field is
      # rendered as a sequence of `max_length` equally-spaced cells
      # (typical for code/serial-number entry). Requires `max_length`
      # to be set explicitly.
      property comb : Bool = false

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
        f |= FILE_SELECT if @file_select
        f |= DO_NOT_SPELL_CHECK if @do_not_spell_check
        f |= DO_NOT_SCROLL if @do_not_scroll
        if @comb
          raise ArgumentError.new("TextField '#{@name}' : `comb: true` requires `max_length:` to be set explicitly") if @max_length.nil?
          f |= COMB
        end
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

        # /AP /N normal appearance — draws the frame plus the current
        # value (if any). Without this, viewers that ignore
        # /NeedAppearances render the field invisible. The text is
        # rendered in WinAnsi-compatible Helvetica ; non-ASCII chars
        # (CJK, emoji) require user-supplied TrueType subsets, out of
        # MVP scope.
        ref = page.document.register_object(build_appearance(page.document.acroform_helvetica_ref))
        ap_n = Objects::Dictionary.new
        ap_n["N"] = ref.reference
        d["AP"] = ap_n
      end

      private def build_appearance(helv_ref : Objects::Reference) : Objects::Stream
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

        # Resources : embed the /Helv font alias so the BT/Tj
        # sequence finds the font.
        font_res = Objects::Dictionary.new
        font_res["Helv"] = helv_ref
        resources = Objects::Dictionary.new
        resources["Font"] = font_res
        procset = Objects::Array.new
        procset << Objects::Name.new("PDF")
        procset << Objects::Name.new("Text")
        resources["ProcSet"] = procset
        stream["Resources"] = resources

        # Font size : 60 % of the field height for single-line, or
        # ~14 pt cap for multi-line (otherwise the text overflows).
        font_size = @multiline ? 12.0 : (h * 0.6).clamp(8.0, 24.0)
        baseline_y = @multiline ? (h - font_size - 2) : ((h - font_size) / 2 + font_size * 0.2)

        io = IO::Memory.new
        io << "q\n"
        # Border around the field (optional but helps locate it).
        io << "0 0 0 RG\n0.5 w\n"
        io << "0.5 0.5 " << format_num(w - 1.0) << " " << format_num(h - 1.0) << " re\nS\n"

        if v = @value
          io << "BT\n"
          io << "/Helv " << format_num(font_size) << " Tf\n"
          io << "0 0 0 rg\n"
          # Move to (left_margin, baseline). 2pt margin keeps the
          # text from touching the border.
          io << "2 " << format_num(baseline_y) << " Td\n"
          escaped = escape_pdf_text(@password ? "*" * v.size : v)
          io << "(" << escaped << ") Tj\n"
          io << "ET\n"
        end
        io << "Q\n"

        stream.data = io.to_s
        stream
      end

      # Escapes a string for embedding inside PDF literal `(...)` —
      # backslash and parentheses must be escaped. Non-ASCII bytes
      # are passed through ; the WinAnsi encoding of Helvetica
      # interprets them.
      private def escape_pdf_text(s : String) : String
        s.gsub("\\", "\\\\").gsub("(", "\\(").gsub(")", "\\)")
      end

      private def format_num(n : Float64) : String
        s = n.round(4).to_s
        s = s.rstrip('0').rstrip('.') if s.includes?('.')
        s.empty? ? "0" : s
      end
    end
  end
end
