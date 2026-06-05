module PDF
  module Raster
    # Fonte chargée pour le rendu : enveloppe le programme TrueType
    # embarqué (`/FontFile2`) d'une fonte PDF et fournit les contours
    # de glyphes, les avances, et le décodage codes → GID.
    #
    # Couvre le cas dominant des PDF ALOLI / asciidoctor-pdf : fontes
    # composites Type0 (CIDFontType2, Identity-H, 2 octets par code) et
    # fontes TrueType simples (1 octet, via la table cmap). Les fontes
    # Type1/CFF non-TrueType ne sont pas encore rendues (`load` renvoie
    # nil → le texte est ignoré sans planter).
    class Font
      getter units_per_em : Float64
      getter? two_byte : Bool

      def initialize(
        @parser : PDF::Fonts::TrueType::Parser,
        @two_byte : Bool,
        @cid_to_gid : Array(UInt16)?,
      )
        @units_per_em = @parser.units_per_em.to_f
        @units_per_em = 1000.0 if @units_per_em <= 0
        @glyf = @parser.glyf
        @loca = @parser.loca
        @hmtx = @parser.hmtx
        @cmap_loaded = false
        @cmap = nil.as(PDF::Fonts::TrueType::Tables::Cmap?)
        @cache = {} of UInt16 => Array(Glyph::Contour)
      end

      # Charge la fonte de rendu depuis un dictionnaire de fonte PDF.
      # Renvoie nil si aucun programme TrueType embarqué n'est trouvé.
      def self.load(reader : PDF::Reader, font_dict : PDF::Objects::Dictionary) : Font?
        subtype = name_of(reader, font_dict["Subtype"]?)
        descendant = nil.as(PDF::Objects::Dictionary?)
        two_byte = false
        cid_to_gid = nil.as(Array(UInt16)?)

        if subtype == "Type0"
          two_byte = true # Identity-H/V : 2 octets par code (cas courant)
          descendant = first_descendant(reader, font_dict)
          return nil unless descendant
          cid_to_gid = load_cid_to_gid(reader, descendant)
        end

        descriptor_owner = descendant || font_dict
        descriptor = resolve_dict(reader, descriptor_owner["FontDescriptor"]?)
        return nil unless descriptor

        ff = descriptor["FontFile2"]?
        return nil unless ff
        stream = reader.resolve(ff).as?(PDF::Objects::Stream)
        return nil unless stream

        parser = PDF::Fonts::TrueType::Parser.parse(stream.data)
        return nil unless parser.has_table?("glyf")
        Font.new(parser, two_byte, cid_to_gid)
      rescue
        nil
      end

      # Découpe une chaîne en codes (2 octets pour les fontes composites,
      # 1 octet sinon) puis les traduit en GID.
      def decode_to_gids(bytes : Bytes) : Array(UInt16)
        gids = [] of UInt16
        if two_byte?
          i = 0
          while i + 1 < bytes.size
            code = (bytes[i].to_u32 << 8) | bytes[i + 1].to_u32
            gids << cid_to_gid(code.to_u16)
            i += 2
          end
        else
          bytes.each { |byte| gids << simple_gid(byte) }
        end
        gids
      end

      # Contours du glyphe `gid`, en fraction d'em (unités / unitsPerEm).
      def contours(gid : UInt16) : Array(Glyph::Contour)
        @cache[gid] ||= begin
          raw = Glyph.outline(@glyf, @loca, gid)
          scale = 1.0 / @units_per_em
          raw.map { |c| c.map { |pt| {pt[0] * scale, pt[1] * scale} } }
        end
      end

      # Avance horizontale du glyphe `gid`, en fraction d'em.
      def advance(gid : UInt16) : Float64
        metrics = @hmtx.h_metrics
        return 0.0 if metrics.empty?
        m = metrics[gid.to_i]? || metrics.last
        m.advance_width / @units_per_em
      end

      private def cid_to_gid(cid : UInt16) : UInt16
        if map = @cid_to_gid
          map[cid.to_i]? || 0_u16
        else
          cid # Identity
        end
      end

      private def simple_gid(code : UInt8) : UInt16
        cm = cmap
        return code.to_u16 unless cm
        cm.glyph_id(code.to_u32) || cm.glyph_id(0xF000_u32 + code) || 0_u16
      end

      private def cmap : PDF::Fonts::TrueType::Tables::Cmap?
        unless @cmap_loaded
          @cmap_loaded = true
          @cmap = @parser.has_table?("cmap") ? @parser.cmap : nil
        end
        @cmap
      end

      private def self.load_cid_to_gid(reader : PDF::Reader, cidfont : PDF::Objects::Dictionary) : Array(UInt16)?
        obj = cidfont["CIDToGIDMap"]?
        return nil unless obj
        resolved = reader.resolve(obj)
        if stream = resolved.as?(PDF::Objects::Stream)
          data = stream.data
          map = Array(UInt16).new(data.size // 2)
          i = 0
          while i + 1 < data.size
            map << ((data[i].to_u16 << 8) | data[i + 1].to_u16)
            i += 2
          end
          map
        else
          nil # /Identity
        end
      end

      private def self.first_descendant(reader : PDF::Reader, font : PDF::Objects::Dictionary) : PDF::Objects::Dictionary?
        desc = font["DescendantFonts"]?
        desc = reader.resolve(desc) if desc
        if arr = desc.as?(PDF::Objects::Array)
          return resolve_dict(reader, arr.unsafe_fetch(0)) if arr.size > 0
        end
        nil
      end

      private def self.resolve_dict(reader : PDF::Reader, obj : PDF::Objects::Base?) : PDF::Objects::Dictionary?
        return nil unless obj
        reader.resolve(obj).as?(PDF::Objects::Dictionary)
      end

      private def self.name_of(reader : PDF::Reader, obj : PDF::Objects::Base?) : String?
        return nil unless obj
        reader.resolve(obj).as?(PDF::Objects::Name).try(&.value)
      end
    end
  end
end
