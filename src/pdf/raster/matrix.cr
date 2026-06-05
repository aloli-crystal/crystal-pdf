module PDF
  module Raster
    # Matrice affine 2D au sens PDF (ISO 32000-1 § 8.3.3) :
    #
    #   | a b 0 |
    #   | c d 0 |
    #   | e f 1 |
    #
    # Un point (x, y) est transformé en
    #   x' = a·x + c·y + e
    #   y' = b·x + d·y + f
    #
    # La concaténation suit la convention vecteur-ligne du PDF :
    # `m1.then(m2)` applique d'abord `m1`, puis `m2` (c'est l'ordre
    # dont a besoin l'opérateur `cm`, qui pré-multiplie la CTM).
    struct Matrix
      getter a : Float64
      getter b : Float64
      getter c : Float64
      getter d : Float64
      getter e : Float64
      getter f : Float64

      def initialize(@a : Float64, @b : Float64, @c : Float64, @d : Float64, @e : Float64, @f : Float64)
      end

      def self.identity : Matrix
        new(1.0, 0.0, 0.0, 1.0, 0.0, 0.0)
      end

      def self.translate(tx : Float64, ty : Float64) : Matrix
        new(1.0, 0.0, 0.0, 1.0, tx, ty)
      end

      def self.scale(sx : Float64, sy : Float64) : Matrix
        new(sx, 0.0, 0.0, sy, 0.0, 0.0)
      end

      # Retourne la matrice qui applique `self` PUIS `other`.
      def then(other : Matrix) : Matrix
        Matrix.new(
          a: other.a * @a + other.c * @b,
          b: other.b * @a + other.d * @b,
          c: other.a * @c + other.c * @d,
          d: other.b * @c + other.d * @d,
          e: other.a * @e + other.c * @f + other.e,
          f: other.b * @e + other.d * @f + other.f,
        )
      end

      # Transforme un point.
      def apply(x : Float64, y : Float64) : Tuple(Float64, Float64)
        {@a * x + @c * y + @e, @b * x + @d * y + @f}
      end

      # Facteur d'échelle moyen (racine du déterminant absolu) — sert à
      # convertir une largeur de trait de l'espace utilisateur vers les
      # pixels du périphérique.
      def mean_scale : Float64
        det = (@a * @d - @b * @c).abs
        Math.sqrt(det)
      end
    end
  end
end
