module PDF
  module Fonts
    # Handler for TrueType/OpenType fonts with PDF embedding support.
    #
    # TrueType fonts are embedded as Type0 (composite) fonts with
    # CIDFont Type 2 descendants. The font is automatically subsetted
    # to include only the glyphs used in the document.
    #
    # ## Example
    #
    # ```
    # parser = TrueType::Parser.parse("path/to/font.ttf")
    # font = TrueTypeFont.new(parser)
    # font.use("Hello World!")
    #
    # # Get PDF objects
    # font_dict = font.to_dictionary
    # descriptor = font.font_descriptor
    # stream = font.font_file_stream
    # ```
    class TrueTypeFont < Base
      # Random prefix for subset tag (6 uppercase letters)
      @subset_prefix : String

      # The TrueType parser
      getter parser : TrueType::Parser

      # The TrueType subsetter (glyf-based). Nil for CFF/OTF fonts,
      # which use the CFF subsetter instead.
      @subsetter : TrueType::Subsetter?

      # The CFF parser (OpenType/CFF fonts only). Nil for glyf fonts.
      @cff_parser : CFF::Parser?

      # Characters used in this font
      @used_chars : Set(Char)

      # Cache for subset font data
      @subset_data : Bytes?

      # Raised when a font file has a valid sfnt header but an outline
      # format this shard cannot handle (neither `glyf` TrueType nor
      # `CFF ` OpenType). With CFF support (palier 0.6.x) this is now
      # rare — only exotic sfnt flavours hit it.
      class UnsupportedFontFormat < Exception
      end

      def initialize(@parser : TrueType::Parser)
        @subset_prefix = generate_subset_prefix
        @used_chars = Set(Char).new
        @subset_data = nil

        if @parser.truetype?
          @subsetter = TrueType::Subsetter.new(@parser)
          @cff_parser = nil
        elsif @parser.cff?
          # OpenType/CFF (.otf) — parse the embedded CFF table and
          # subset it natively (palier 0.6.x of the ISO trajectory).
          cff_bytes = @parser.table_data("CFF ") ||
                      raise UnsupportedFontFormat.new("OpenType font declares CFF outlines but has no 'CFF ' table")
          @cff_parser = CFF::Parser.new(cff_bytes)
          @subsetter = nil
        else
          raise UnsupportedFontFormat.new(unsupported_message)
        end
      end

      # `true` for OpenType/CFF (.otf) fonts, `false` for glyf-based
      # TrueType. Drives the PDF emission path (CIDFontType0 +
      # FontFile3 vs CIDFontType2 + FontFile2).
      def cff? : Bool
        !@cff_parser.nil?
      end

      # Builds a user-actionable error message for a font whose sfnt
      # flavour is neither glyf TrueType nor OpenType/CFF (both of
      # which are supported). Reached only for exotic flavours.
      private def unsupported_message : String
        "Unsupported sfnt flavour. This shard handles TrueType outlines " \
        "(glyf) and OpenType/CFF (CFF ) ; the loaded font has neither."
      end

      # Load a TrueType font from a file path
      def self.load(path : String) : TrueTypeFont
        parser = TrueType::Parser.parse(path)
        new(parser)
      end

      # Load a TrueType font from bytes
      def self.load(data : Bytes) : TrueTypeFont
        parser = TrueType::Parser.parse(data)
        new(parser)
      end

      # Returns the font name as it appears in the PDF
      def name : String
        "#{@subset_prefix}+#{@parser.postscript_name}"
      end

      # Returns the base font name without subset prefix
      def base_name : String
        @parser.postscript_name
      end

      # Mark a character as used
      def use(char : Char) : Nil
        return if @used_chars.includes?(char)
        @used_chars << char
        # The glyf subsetter tracks per-char glyphs ; the CFF path
        # derives kept GIDs lazily from @used_chars at subset time.
        @subsetter.try(&.use(char))
        @subset_data = nil # Invalidate cache
      end

      # Mark a string of characters as used
      def use(text : String) : Nil
        text.each_char { |c| use(c) }
      end

      # Returns `true` when this font contains a glyph for `char`,
      # i.e. `char` will render as something other than the `.notdef`
      # tofu box.
      #
      # Useful for callers that maintain a fallback font chain : if
      # the primary font reports `has_glyph?(c) == false`, try the
      # next font (or substitute a placeholder) instead of letting a
      # silent tofu box ship in the PDF.
      def has_glyph?(char : Char) : Bool
        @parser.glyph_id(char) != 0_u16
      end

      # Get the glyph width in 1/1000 of the font's em-square
      def glyph_width(char : Char) : Int32
        glyph_id = @parser.glyph_id(char)
        width = @parser.advance_width(glyph_id)
        # Scale to 1000 units
        (width.to_f64 * 1000 / @parser.units_per_em).round.to_i32
      end

      # Get the subset font data. For glyf fonts this is a subsetted
      # TrueType sfnt ; for CFF fonts it is a subsetted bare CFF blob
      # (to be embedded as FontFile3 / CIDFontType0C).
      def subset_data : Bytes
        @subset_data ||= begin
          if cff_parser = @cff_parser
            kept = kept_glyph_ids
            CFF::Subsetter.new(cff_parser, kept).subset
          else
            @subsetter.not_nil!.subset
          end
        end
      end

      # Original glyph IDs to retain in a CFF subset, derived from
      # the characters actually used in the document. GID 0 is added
      # by the subsetter itself.
      private def kept_glyph_ids : Set(Int32)
        kept = Set(Int32).new
        @used_chars.each { |c| kept << @parser.glyph_id(c).to_i32 }
        kept
      end

      # Returns the Type 0 (composite) font dictionary
      def to_dictionary : Objects::Dictionary
        dict = Objects::Dictionary.new
        dict["Type"] = Objects::Name::FONT
        dict["Subtype"] = Objects::Name.new("Type0")
        dict["BaseFont"] = Objects::Name.new(name)
        dict["Encoding"] = Objects::Name.new("Identity-H")

        # DescendantFonts is an array containing one CIDFont
        # This will be replaced with a reference when the font is registered
        descendants = Objects::Array.new
        dict["DescendantFonts"] = descendants

        dict
      end

      # Returns the CIDFont dictionary. CFF fonts use CIDFontType0
      # (the descendant of a Type0 font whose FontFile3 carries a
      # bare CFF), glyf fonts use CIDFontType2.
      def cid_font_dictionary : Objects::Dictionary
        dict = Objects::Dictionary.new
        dict["Type"] = Objects::Name::FONT
        dict["Subtype"] = Objects::Name.new(cff? ? "CIDFontType0" : "CIDFontType2")
        dict["BaseFont"] = Objects::Name.new(name)

        # CIDSystemInfo
        cid_info = Objects::Dictionary.new
        cid_info["Registry"] = Objects::Str.new("Adobe")
        cid_info["Ordering"] = Objects::Str.new("Identity")
        cid_info["Supplement"] = Objects::Number.new(0)
        dict["CIDSystemInfo"] = cid_info

        # FontDescriptor will be added as a reference
        # dict["FontDescriptor"] = ...

        # DW (default width) - use 1000 as fallback
        dict["DW"] = Objects::Number.new(1000)

        # W array (glyph widths) - using original glyph IDs as CIDs
        dict["W"] = build_widths_array

        # CIDToGIDMap will be added as a stream reference by the caller
        # This maps original glyph IDs (used as CIDs) to new glyph IDs in subset

        dict
      end

      # Returns the font descriptor dictionary
      def font_descriptor : Objects::Dictionary
        dict = Objects::Dictionary.new
        dict["Type"] = Objects::Name.new("FontDescriptor")
        dict["FontName"] = Objects::Name.new(name)
        dict["Flags"] = Objects::Number.new(@parser.flags.to_i32)

        # Bounding box (scaled to 1000 units)
        bbox = @parser.bounding_box
        scale = 1000.0 / @parser.units_per_em
        scaled_bbox = [
          (bbox[0] * scale).round.to_i32,
          (bbox[1] * scale).round.to_i32,
          (bbox[2] * scale).round.to_i32,
          (bbox[3] * scale).round.to_i32,
        ]
        dict["FontBBox"] = Objects::Array.new(scaled_bbox)

        dict["ItalicAngle"] = Objects::Number.new(@parser.italic_angle)
        dict["Ascent"] = Objects::Number.new((@parser.ascender * scale).round.to_i32)
        dict["Descent"] = Objects::Number.new((@parser.descender * scale).round.to_i32)
        dict["CapHeight"] = Objects::Number.new((@parser.cap_height * scale).round.to_i32)
        dict["StemV"] = Objects::Number.new(@parser.stem_v)

        # FontFile2 will be added as a reference
        # dict["FontFile2"] = ...

        dict
      end

      # Returns the font file stream (subset font data). For glyf
      # fonts this is FontFile2 data with /Length1 ; for CFF fonts
      # it is FontFile3 data with /Subtype /CIDFontType0C and no
      # /Length1 (which only applies to Type1/TrueType programs).
      def font_file_stream : Objects::Stream
        data = subset_data
        stream = Objects::Stream.new
        stream.data = data
        if cff?
          stream["Subtype"] = Objects::Name.new("CIDFontType0C")
        else
          stream["Length1"] = Objects::Number.new(data.size)
        end
        stream.add_filter(Filters::Flate.new)
        stream
      end

      # The FontDescriptor key under which the embedded font program
      # is referenced : `FontFile3` for CFF, `FontFile2` for glyf.
      def font_file_key : String
        cff? ? "FontFile3" : "FontFile2"
      end

      # `true` when the CIDToGIDMap should be the name `/Identity`
      # rather than an explicit stream. The CFF subsetter preserves
      # GID numbering, so CID (original GID) maps to itself.
      def uses_identity_cid_to_gid? : Bool
        cff?
      end

      # Returns the ToUnicode CMap stream
      def to_unicode_cmap : Objects::Stream
        stream = Objects::Stream.new
        stream.data = build_to_unicode_cmap
        stream.add_filter(Filters::Flate.new)
        stream
      end

      # Returns the CIDToGIDMap stream
      # Maps original glyph IDs (used as CIDs in content stream) to
      # new glyph IDs in the subset font
      def cid_to_gid_map_stream : Objects::Stream
        # Ensure subset is generated so we have the mapping
        subset_data

        stream = Objects::Stream.new
        stream.data = build_cid_to_gid_map
        stream.add_filter(Filters::Flate.new)
        stream
      end

      # Build the CIDToGIDMap data
      # This is a stream of 2-byte big-endian GID values, indexed by CID
      private def build_cid_to_gid_map : Bytes
        # Find the maximum CID (original glyph ID) we need to map
        max_cid = 0_u16
        @used_chars.each do |char|
          glyph_id = @parser.glyph_id(char)
          max_cid = glyph_id if glyph_id > max_cid
        end

        # Build array of GID mappings (2 bytes per entry)
        # Entry at index i gives the new GID for original GID (CID) i
        io = IO::Memory.new

        (0_u16..max_cid).each do |cid|
          new_gid = @subsetter.not_nil!.new_glyph_id(cid)
          io.write_byte(((new_gid >> 8) & 0xFF).to_u8)
          io.write_byte((new_gid & 0xFF).to_u8)
        end

        io.to_slice
      end

      # Build the widths array for the CIDFont dictionary
      # CIDs are original glyph IDs from the source font
      private def build_widths_array : Objects::Array
        widths = Objects::Array.new

        # Get original glyph IDs for all used characters
        glyph_ids = @used_chars.map { |c| @parser.glyph_id(c) }.uniq.sort

        # Group consecutive CIDs with widths
        # Format: [cid [w1 w2 w3...]]
        i = 0
        while i < glyph_ids.size
          start_cid = glyph_ids[i]
          consecutive_widths = [] of Int32

          # Collect consecutive glyph IDs
          while i < glyph_ids.size
            current_cid = glyph_ids[i]
            break if current_cid != start_cid + consecutive_widths.size

            # Get width for this glyph
            width = @parser.advance_width(current_cid)
            # Scale to 1000 units
            scaled_width = (width.to_f64 * 1000 / @parser.units_per_em).round.to_i32
            consecutive_widths << scaled_width
            i += 1
          end

          # Add to array: start_cid [w1 w2 w3 ...]
          widths << Objects::Number.new(start_cid.to_i32)
          width_array = Objects::Array.new
          consecutive_widths.each { |w| width_array << Objects::Number.new(w) }
          widths << width_array
        end

        widths
      end

      # Build the ToUnicode CMap for text extraction
      # Maps original glyph IDs (used as CIDs) to Unicode values
      private def build_to_unicode_cmap : String
        # Build mapping from original glyph ID to Unicode codepoint
        entries = [] of {UInt16, UInt32}
        @used_chars.each do |char|
          glyph_id = @parser.glyph_id(char)
          entries << {glyph_id, char.ord.to_u32}
        end
        entries = entries.sort_by { |glyph_id, _| glyph_id }

        String.build do |io|
          io << "/CIDInit /ProcSet findresource begin\n"
          io << "12 dict begin\n"
          io << "begincmap\n"
          io << "/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def\n"
          io << "/CMapName /Adobe-Identity-UCS def\n"
          io << "/CMapType 2 def\n"
          io << "1 begincodespacerange\n"
          io << "<0000> <FFFF>\n"
          io << "endcodespacerange\n"

          # Split into chunks of 100 for bfchar sections
          entries.each_slice(100) do |chunk|
            io << "#{chunk.size} beginbfchar\n"
            chunk.each do |glyph_id, unicode|
              io << "<" << glyph_id.to_s(16).rjust(4, '0').upcase << "> "
              if unicode <= 0xFFFF
                io << "<" << unicode.to_s(16).rjust(4, '0').upcase << ">\n"
              else
                # Surrogate pair for characters outside BMP
                high = ((unicode - 0x10000) >> 10) + 0xD800
                low = ((unicode - 0x10000) & 0x3FF) + 0xDC00
                io << "<" << high.to_s(16).rjust(4, '0').upcase
                io << low.to_s(16).rjust(4, '0').upcase << ">\n"
              end
            end
            io << "endbfchar\n"
          end

          io << "endcmap\n"
          io << "CMapName currentdict /CMap defineresource pop\n"
          io << "end\n"
          io << "end\n"
        end
      end

      # Generate a random 6-letter subset prefix
      private def generate_subset_prefix : String
        String.build(6) do |io|
          6.times { io << ('A'.ord + Random.rand(26)).chr }
        end
      end

      # Returns true if this font has kerning data.
      def has_kerning? : Bool
        @parser.has_kerning?
      end

      # Returns kerning value between two characters, scaled to 1/1000 em.
      def kern_pair(left : Char, right : Char) : Int32
        left_gid = @parser.glyph_id(left)
        right_gid = @parser.glyph_id(right)
        value = @parser.kern_pair(left_gid, right_gid)
        (value.to_f64 * 1000 / @parser.units_per_em).round.to_i32
      end

      # Returns an array of kerning-aware text segments.
      # Each element is either a String (text fragment) or an Int32 (kern adjustment in 1/1000 em).
      # The kern adjustments are negated for use with the TJ operator (positive = move left).
      def text_with_kerning(text : String) : Array(String | Int32)
        use(text)
        return [text] of (String | Int32) unless has_kerning?

        chars = text.chars
        return [text] of (String | Int32) if chars.size < 2

        result = [] of (String | Int32)
        current = String::Builder.new

        chars.each_with_index do |char, i|
          current << char
          if i < chars.size - 1
            kern_value = kern_pair(char, chars[i + 1])
            if kern_value != 0
              result << current.to_s
              current = String::Builder.new
              # PDF TJ operator: positive values move text left (tighten),
              # but kern values are positive when glyphs should be moved apart.
              # In TJ, negative values in the array move glyphs apart.
              # Font kern values: negative = tighten, positive = loosen.
              # TJ values: positive = tighten (move left), negative = loosen (move right).
              # So we negate the kern value.
              result << (-kern_value)
            end
          end
        end

        remaining = current.to_s
        result << remaining unless remaining.empty?
        result
      end

      # Encode text for use in a content stream (returns hex string)
      #
      # For Identity-H encoding, we encode characters using their ORIGINAL
      # glyph IDs from the source font. The CIDToGIDMap will then map these
      # to the remapped glyph IDs in the subset font.
      def encode_text(text : String) : String
        use(text)

        String.build do |io|
          io << '<'
          text.each_char do |char|
            # Use the original glyph ID - CIDToGIDMap will remap it
            glyph_id = @parser.glyph_id(char)
            io << glyph_id.to_s(16).rjust(4, '0').upcase
          end
          io << '>'
        end
      end

      # Encode a single character as a hex string for PDF content streams.
      def encode_char(char : Char) : String
        use(char)
        glyph_id = @parser.glyph_id(char)
        "<#{glyph_id.to_s(16).rjust(4, '0').upcase}>"
      end
    end
  end
end
