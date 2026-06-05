require "stumpy_core"
require "stumpy_png"

module PDF
  module Raster
    # Toile de rastérisation : un tampon de pixels RGBA (via
    # `StumpyCore::Canvas`) avec remplissage de polygones par balayage
    # de lignes (scanline) et tracé de segments épais.
    #
    # Les coordonnées sont en pixels périphérique (origine haut-gauche,
    # y vers le bas) — la conversion depuis l'espace PDF est faite en
    # amont par l'interpréteur via la CTM.
    class Canvas
      alias Point = Tuple(Float64, Float64)
      alias SubPath = Array(Point)

      getter width : Int32
      getter height : Int32
      getter pixels : StumpyCore::Canvas

      def initialize(@width : Int32, @height : Int32, background : StumpyCore::RGBA = StumpyCore::RGBA::WHITE)
        @pixels = StumpyCore::Canvas.new(@width, @height, background)
      end

      # Remplit un chemin (liste de sous-chemins fermés) avec la couleur
      # donnée (composantes 0..1), selon la règle even-odd ou non-zéro.
      def fill(subpaths : Array(SubPath), r : Float64, g : Float64, b : Float64, even_odd : Bool = false, alpha : Float64 = 1.0) : Nil
        color = rgba(r, g, b)
        fill_subpaths(subpaths, color, even_odd, alpha)
      end

      # Trace une polyligne (chemin ouvert ou fermé) avec une épaisseur
      # donnée en pixels, approximée par un quadrilatère rempli par
      # segment (jointures simples).
      def stroke(subpaths : Array(SubPath), width : Float64, r : Float64, g : Float64, b : Float64, alpha : Float64 = 1.0) : Nil
        color = rgba(r, g, b)
        half = {width, 1.0}.max / 2.0
        subpaths.each do |sp|
          next if sp.size < 2
          (0...sp.size - 1).each do |i|
            quad = segment_quad(sp[i], sp[i + 1], half)
            fill_subpaths([quad], color, false, alpha)
          end
        end
      end

      # Encode la toile en PNG dans un IO.
      def to_png(io : IO) : Nil
        StumpyPNG.write(@pixels, io)
      end

      # Écrit la toile en PNG sur disque.
      def save_png(path : String) : Nil
        StumpyPNG.write(@pixels, path)
      end

      # Écrit la toile en PPM binaire (P6) dans un IO — format Netpbm,
      # comme `pdftoppm` par défaut.
      def to_ppm(io : IO) : Nil
        io << "P6\n" << @width << " " << @height << "\n255\n"
        @height.times do |y|
          @width.times do |x|
            px = @pixels[x, y]
            io.write_byte((px.r >> 8).to_u8)
            io.write_byte((px.g >> 8).to_u8)
            io.write_byte((px.b >> 8).to_u8)
          end
        end
      end

      private def rgba(r : Float64, g : Float64, b : Float64) : StumpyCore::RGBA
        StumpyCore::RGBA.new(to_u16(r), to_u16(g), to_u16(b), UInt16::MAX)
      end

      private def to_u16(v : Float64) : UInt16
        (v.clamp(0.0, 1.0) * UInt16::MAX).round.to_u16
      end

      # Cœur du remplissage : balayage de lignes avec règle even-odd ou
      # non-zéro. Chaque arête contribue une intersection par scanline.
      private def fill_subpaths(subpaths : Array(SubPath), color : StumpyCore::RGBA, even_odd : Bool, alpha : Float64) : Nil
        # Arêtes : {y_min, y_max, x_at_ymin, dx/dy, winding}.
        y_lo = @height
        y_hi = 0
        edges = [] of Tuple(Float64, Float64, Float64, Float64, Int32)
        subpaths.each do |sp|
          next if sp.size < 2
          n = sp.size
          n.times do |i|
            x1, y1 = sp[i]
            x2, y2 = sp[(i + 1) % n] # ferme implicitement le sous-chemin
            next if y1 == y2
            if y1 < y2
              winding = 1
              ya, xa, yb, xb = y1, x1, y2, x2
            else
              winding = -1
              ya, xa, yb, xb = y2, x2, y1, x1
            end
            slope = (xb - xa) / (yb - ya)
            edges << {ya, yb, xa, slope, winding}
            y_lo = Math.min(y_lo, ya.floor.to_i)
            y_hi = Math.max(y_hi, yb.ceil.to_i)
          end
        end
        return if edges.empty?

        y_lo = Math.max(y_lo, 0)
        y_hi = Math.min(y_hi, @height - 1)

        (y_lo..y_hi).each do |py|
          cy = py + 0.5
          # Intersections {x, winding}.
          xs = [] of Tuple(Float64, Int32)
          edges.each do |ya, yb, xa, slope, winding|
            next if cy < ya || cy >= yb
            x = xa + (cy - ya) * slope
            xs << {x, winding}
          end
          next if xs.empty?
          xs.sort_by! { |pair| pair[0] }

          if even_odd
            i = 0
            while i + 1 < xs.size
              span(py, xs[i][0], xs[i + 1][0], color, alpha)
              i += 2
            end
          else
            wind = 0
            i = 0
            while i < xs.size - 1
              wind += xs[i][1]
              span(py, xs[i][0], xs[i + 1][0], color, alpha) if wind != 0
              i += 1
            end
          end
        end
      end

      private def span(py : Int32, x_start : Float64, x_end : Float64, color : StumpyCore::RGBA, alpha : Float64) : Nil
        x0 = Math.max(x_start.round.to_i, 0)
        x1 = Math.min(x_end.round.to_i, @width)
        return if x1 <= x0
        (x0...x1).each { |px| put(px, py, color, alpha) }
      end

      private def put(x : Int32, y : Int32, color : StumpyCore::RGBA, alpha : Float64) : Nil
        return if x < 0 || y < 0 || x >= @width || y >= @height
        if alpha >= 0.999
          @pixels[x, y] = color
        else
          bg = @pixels[x, y]
          @pixels[x, y] = StumpyCore::RGBA.new(
            mix(bg.r, color.r, alpha), mix(bg.g, color.g, alpha),
            mix(bg.b, color.b, alpha), UInt16::MAX)
        end
      end

      private def mix(bg : UInt16, fg : UInt16, alpha : Float64) : UInt16
        (bg.to_f * (1.0 - alpha) + fg.to_f * alpha).round.to_u16
      end

      # Quadrilatère couvrant un segment épais (extrémités carrées).
      private def segment_quad(p1 : Point, p2 : Point, half : Float64) : SubPath
        dx = p2[0] - p1[0]
        dy = p2[1] - p1[1]
        len = Math.sqrt(dx * dx + dy * dy)
        return [p1, p2] of Point if len == 0
        nx = -dy / len * half
        ny = dx / len * half
        [
          {p1[0] + nx, p1[1] + ny},
          {p2[0] + nx, p2[1] + ny},
          {p2[0] - nx, p2[1] - ny},
          {p1[0] - nx, p1[1] - ny},
        ] of Point
      end
    end
  end
end
