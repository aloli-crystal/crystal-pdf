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

      # Boîte englobante du détourage (x0, y0, x1, y1 inclus, en pixels),
      # nil = pas de détourage. Borne l'itération.
      @clip : Tuple(Int32, Int32, Int32, Int32)?

      # Masque de couverture du détourage (0/255 par pixel) pour les
      # clips non rectangulaires, nil = clip purement rectangulaire.
      @clip_mask : Bytes?

      def initialize(@width : Int32, @height : Int32, background : StumpyCore::RGBA = StumpyCore::RGBA::WHITE)
        @pixels = StumpyCore::Canvas.new(@width, @height, background)
        @clip = nil
        @clip_mask = nil
      end

      # Définit (ou retire avec nil) la boîte de détourage et un masque
      # optionnel pour les formes non rectangulaires.
      def set_clip(rect : Tuple(Int32, Int32, Int32, Int32)?, mask : Bytes? = nil) : Nil
        @clip = rect
        @clip_mask = mask
      end

      # Compose une couleur (0..1) avec alpha sur un pixel, en
      # respectant le détourage. Utilisé par le rendu d'images (SMask).
      def blend(x : Int32, y : Int32, r : Float64, g : Float64, b : Float64, alpha : Float64) : Nil
        return if alpha <= 0.0
        put(x, y, rgba(r, g, b), alpha)
      end

      # Remplit un chemin (liste de sous-chemins fermés) avec la couleur
      # donnée (composantes 0..1), selon la règle even-odd ou non-zéro.
      def fill(subpaths : Array(SubPath), r : Float64, g : Float64, b : Float64, even_odd : Bool = false, alpha : Float64 = 1.0) : Nil
        color = rgba(r, g, b)
        fill_subpaths(subpaths, color, even_odd, alpha)
      end

      # Trace une polyligne avec une épaisseur (pixels). Chaque segment
      # est un quadrilatère rempli ; des disques aux sommets donnent des
      # jointures et extrémités rondes (traits épais). `dash` (longueurs
      # en pixels, alternance plein/vide) produit un trait tireté.
      def stroke(subpaths : Array(SubPath), width : Float64, r : Float64, g : Float64, b : Float64, alpha : Float64 = 1.0, dash : Array(Float64)? = nil, dash_phase : Float64 = 0.0) : Nil
        color = rgba(r, g, b)
        half = {width, 1.0}.max / 2.0
        dashed = dash && dash.size > 0 && dash.any? { |d| d > 0 }
        round = half > 0.75
        subpaths.each do |sp|
          next if sp.size < 2
          if dashed
            stroke_dashed(sp, half, color, alpha, dash.not_nil!, dash_phase)
            next
          end
          (0...sp.size - 1).each do |i|
            quad = segment_quad(sp[i], sp[i + 1], half)
            fill_subpaths([quad], color, false, alpha)
          end
          sp.each { |pt| fill_disc(pt[0], pt[1], half, color, alpha) } if round
        end
      end

      # Réduit la toile d'un facteur entier en moyennant des blocs
      # `factor × factor` — c'est l'étape de ré-échantillonnage du
      # supersampling (anti-aliasing). Renvoie une nouvelle `Canvas`.
      def downsample(factor : Int32) : Canvas
        return self if factor <= 1
        out_w = @width // factor
        out_h = @height // factor
        result = Canvas.new(out_w, out_h)
        inv = 1.0 / (factor * factor)
        (0...out_h).each do |ty|
          (0...out_w).each do |tx|
            r = 0_u64
            g = 0_u64
            b = 0_u64
            (0...factor).each do |dy|
              (0...factor).each do |dx|
                px = @pixels[tx * factor + dx, ty * factor + dy]
                r += px.r
                g += px.g
                b += px.b
              end
            end
            result.pixels[tx, ty] = StumpyCore::RGBA.new(
              (r * inv).to_u16, (g * inv).to_u16, (b * inv).to_u16, UInt16::MAX)
          end
        end
        result
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

      # Construit un masque de couverture (0/255 par pixel) à partir
      # d'un chemin — sert au détourage exact des clips non rectangulaires.
      def path_coverage(subpaths : Array(SubPath), even_odd : Bool) : Bytes
        mask = Bytes.new(@width * @height, 0_u8)
        each_span(subpaths, even_odd) do |py, x_start, x_end|
          x0 = Math.max(x_start.round.to_i, 0)
          x1 = Math.min(x_end.round.to_i, @width)
          row = py * @width
          (x0...x1).each { |px| mask[row + px] = 255_u8 }
        end
        mask
      end

      private def fill_subpaths(subpaths : Array(SubPath), color : StumpyCore::RGBA, even_odd : Bool, alpha : Float64) : Nil
        each_span(subpaths, even_odd) do |py, x_start, x_end|
          span(py, x_start, x_end, color, alpha)
        end
      end

      # Cœur du balayage : pour chaque scanline, calcule les segments
      # couverts (règle even-odd ou non-zéro) et les passe au bloc sous
      # la forme (py, x_début, x_fin).
      private def each_span(subpaths : Array(SubPath), even_odd : Bool, &block : Int32, Float64, Float64 ->) : Nil
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
              block.call(py, xs[i][0], xs[i + 1][0])
              i += 2
            end
          else
            wind = 0
            i = 0
            while i < xs.size - 1
              wind += xs[i][1]
              block.call(py, xs[i][0], xs[i + 1][0]) if wind != 0
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
        if clip = @clip
          return if x < clip[0] || y < clip[1] || x > clip[2] || y > clip[3]
        end
        if mask = @clip_mask
          return if mask[y * @width + x] == 0
        end
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

      # Trace une polyligne tiretée : avance le long du chemin en
      # alternant plein/vide selon le motif `dash` (longueurs en pixels),
      # l'état du motif étant continu d'un segment à l'autre.
      private def stroke_dashed(sp : SubPath, half : Float64, color : StumpyCore::RGBA, alpha : Float64, dash : Array(Float64), phase : Float64) : Nil
        total = dash.sum
        return if total <= 0
        # Position initiale dans le cycle (phase).
        idx = 0
        rem = dash[0]
        on = true
        ph = phase % total
        while ph > 0
          if ph >= rem
            ph -= rem
            idx = (idx + 1) % dash.size
            rem = dash[idx]
            on = !on
          else
            rem -= ph
            ph = 0.0
          end
        end

        (0...sp.size - 1).each do |s|
          x1, y1 = sp[s]
          x2, y2 = sp[s + 1]
          seg = Math.sqrt((x2 - x1)**2 + (y2 - y1)**2)
          next if seg == 0
          ux = (x2 - x1) / seg
          uy = (y2 - y1) / seg
          pos = 0.0
          while pos < seg
            take = Math.min(rem, seg - pos)
            if on
              a = {x1 + ux * pos, y1 + uy * pos}
              b = {x1 + ux * (pos + take), y1 + uy * (pos + take)}
              fill_subpaths([segment_quad(a, b, half)], color, false, alpha)
            end
            pos += take
            rem -= take
            if rem <= 1e-9
              idx = (idx + 1) % dash.size
              rem = dash[idx]
              on = !on
            end
          end
        end
      end

      # Remplit un disque (jointure/extrémité ronde) centré en (cx, cy).
      private def fill_disc(cx : Float64, cy : Float64, radius : Float64, color : StumpyCore::RGBA, alpha : Float64) : Nil
        r2 = radius * radius
        y0 = (cy - radius).floor.to_i
        y1 = (cy + radius).ceil.to_i
        x0 = (cx - radius).floor.to_i
        x1 = (cx + radius).ceil.to_i
        (y0..y1).each do |py|
          (x0..x1).each do |px|
            dx = px + 0.5 - cx
            dy = py + 0.5 - cy
            put(px, py, color, alpha) if dx * dx + dy * dy <= r2
          end
        end
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
