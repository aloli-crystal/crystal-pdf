module PDF
  module Raster
    # Extraction des contours d'un glyphe TrueType (table `glyf`) vers
    # des polygones en unités de fonte, prêts à être remplis. Les
    # courbes de Bézier quadratiques sont aplaties en segments.
    #
    # Gère les glyphes simples et composites (offset + matrice 2×2).
    module Glyph
      ON_CURVE   = 0x01_u8
      X_SHORT    = 0x02_u8
      Y_SHORT    = 0x04_u8
      REPEAT     = 0x08_u8
      X_SAME     = 0x10_u8 # si X_SHORT : signe + ; sinon : x identique
      Y_SAME     = 0x20_u8
      QUAD_STEPS =       8

      alias Point = Tuple(Float64, Float64)
      alias Contour = Array(Point)

      # Retourne les contours (polygones fermés) du glyphe `gid`.
      def self.outline(glyf : PDF::Fonts::TrueType::Tables::Glyf, loca : PDF::Fonts::TrueType::Tables::Loca, gid : UInt16, depth : Int32 = 0) : Array(Contour)
        return [] of Contour if depth > 5
        data = glyf.glyph(gid, loca)
        return [] of Contour if data.empty?

        if data.composite?
          composite_outline(glyf, loca, data, depth)
        else
          simple_outline(data)
        end
      rescue
        [] of Contour
      end

      private def self.simple_outline(data : PDF::Fonts::TrueType::Tables::GlyphData) : Array(Contour)
        nc = data.number_of_contours.to_i
        return [] of Contour if nc <= 0
        raw = data.raw_data
        io = IO::Memory.new(raw)

        end_pts = Array(Int32).new(nc) { read_u16(io).to_i }
        return [] of Contour if end_pts.empty?
        num_points = end_pts.last + 1
        return [] of Contour if num_points <= 0

        instr_len = read_u16(io)
        io.skip(instr_len)

        # Drapeaux (avec expansion REPEAT).
        flags = Array(UInt8).new(num_points)
        while flags.size < num_points
          f = read_byte(io)
          flags << f
          if (f & REPEAT) != 0
            rep = read_byte(io)
            rep.times { flags << f if flags.size < num_points }
          end
        end

        xs = read_coords(io, flags, X_SHORT, X_SAME)
        ys = read_coords(io, flags, Y_SHORT, Y_SAME)

        contours = [] of Contour
        start = 0
        end_pts.each do |last|
          pts = [] of Tuple(Float64, Float64, Bool)
          (start..last).each do |i|
            pts << {xs[i], ys[i], (flags[i] & ON_CURVE) != 0}
          end
          contour = flatten_contour(pts)
          contours << contour unless contour.size < 3
          start = last + 1
        end
        contours
      rescue
        [] of Contour
      end

      # Lit les coordonnées delta (x ou y) et accumule en absolu.
      private def self.read_coords(io : IO, flags : Array(UInt8), short_bit : UInt8, same_bit : UInt8) : Array(Float64)
        coords = Array(Float64).new(flags.size)
        value = 0
        flags.each do |f|
          if (f & short_bit) != 0
            delta = read_byte(io).to_i
            delta = -delta if (f & same_bit) == 0
            value += delta
          elsif (f & same_bit) == 0
            value += read_i16(io)
          end
          coords << value.to_f
        end
        coords
      end

      # Aplati un contour (points on/off-curve) en polygone de segments.
      private def self.flatten_contour(pts : Array(Tuple(Float64, Float64, Bool))) : Contour
        return [] of Point if pts.empty?

        # Insère les points on-curve implicites entre deux off-curve.
        expanded = [] of Tuple(Float64, Float64, Bool)
        n = pts.size
        n.times do |i|
          cur = pts[i]
          nxt = pts[(i + 1) % n]
          expanded << cur
          if !cur[2] && !nxt[2]
            expanded << {(cur[0] + nxt[0]) / 2, (cur[1] + nxt[1]) / 2, true}
          end
        end

        start_idx = expanded.index(&.[2])
        return [] of Point unless start_idx
        rot = expanded.rotate(start_idx)
        seq = rot + [rot[0]]

        result = [] of Point
        result << {rot[0][0], rot[0][1]}
        i = 0
        while i < seq.size - 1
          a = seq[i]
          b = seq[i + 1]
          if b[2]
            result << {b[0], b[1]}
            i += 1
          else
            c = seq[i + 2]? || seq[0]
            flatten_quad({a[0], a[1]}, {b[0], b[1]}, {c[0], c[1]}, result)
            i += 2
          end
        end
        result
      end

      private def self.flatten_quad(p0 : Point, c : Point, p1 : Point, result : Contour) : Nil
        (1..QUAD_STEPS).each do |k|
          t = k.to_f / QUAD_STEPS
          u = 1.0 - t
          x = u * u * p0[0] + 2 * u * t * c[0] + t * t * p1[0]
          y = u * u * p0[1] + 2 * u * t * c[1] + t * t * p1[1]
          result << {x, y}
        end
      end

      # Glyphe composite : assemble les composants avec leur offset et
      # leur matrice 2×2.
      private def self.composite_outline(glyf : PDF::Fonts::TrueType::Tables::Glyf, loca : PDF::Fonts::TrueType::Tables::Loca, data : PDF::Fonts::TrueType::Tables::GlyphData, depth : Int32) : Array(Contour)
        result = [] of Contour
        io = IO::Memory.new(data.raw_data)
        loop do
          break if io.pos + 4 > data.raw_data.size
          flags = read_u16(io)
          comp_gid = read_u16(io)

          if (flags & 0x0001) != 0 # ARG_1_AND_2_ARE_WORDS
            arg1 = read_i16(io)
            arg2 = read_i16(io)
          else
            arg1 = read_sbyte(io)
            arg2 = read_sbyte(io)
          end

          a = 1.0; b = 0.0; c = 0.0; d = 1.0
          if (flags & 0x0008) != 0 # WE_HAVE_A_SCALE
            a = d = f2dot14(io)
          elsif (flags & 0x0040) != 0 # X_AND_Y_SCALE
            a = f2dot14(io); d = f2dot14(io)
          elsif (flags & 0x0080) != 0 # TWO_BY_TWO
            a = f2dot14(io); b = f2dot14(io); c = f2dot14(io); d = f2dot14(io)
          end

          dx, dy = ((flags & 0x0002) != 0) ? {arg1.to_f, arg2.to_f} : {0.0, 0.0}

          outline(glyf, loca, comp_gid.to_u16, depth + 1).each do |contour|
            result << contour.map do |pt|
              {a * pt[0] + c * pt[1] + dx, b * pt[0] + d * pt[1] + dy}
            end
          end

          break if (flags & 0x0020) == 0 # MORE_COMPONENTS
        end
        result
      end

      # --- lectures big-endian ---

      private def self.read_byte(io : IO) : UInt8
        io.read_byte || 0_u8
      end

      private def self.read_sbyte(io : IO) : Int32
        v = read_byte(io).to_i
        v >= 128 ? v - 256 : v
      end

      private def self.read_u16(io : IO) : Int32
        hi = read_byte(io).to_i
        lo = read_byte(io).to_i
        (hi << 8) | lo
      end

      private def self.read_i16(io : IO) : Int32
        v = read_u16(io)
        v >= 0x8000 ? v - 0x10000 : v
      end

      private def self.f2dot14(io : IO) : Float64
        read_i16(io) / 16384.0
      end
    end
  end
end
