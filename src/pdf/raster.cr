require "./raster/matrix"
require "./raster/canvas"
require "./raster/content_lexer"
require "./raster/glyph"
require "./raster/font"
require "./raster/interpreter"

module PDF
  # Rasterizer PDF natif (Crystal pur) — le moteur des utilitaires
  # `pdftoppm` / `pdftocairo` de poppler-utils, SANS dépendance à
  # ghostscript.
  #
  # MVP : rendu **vectoriel** (chemins, remplissages, traits, couleurs
  # Device, transformations). Le texte (rendu des glyphes) et les
  # images (XObjects) sont des paliers suivants — leurs opérateurs sont
  # consommés sans effet pour l'instant.
  #
  # ```
  # reader = PDF::Reader.open("document.pdf")
  # canvas = PDF::Raster.render_page(reader, 0, dpi: 150)
  # canvas.save_png("page-1.png")
  # ```
  module Raster
    # Résolution par défaut (points par pouce).
    DEFAULT_DPI = 150

    # Rend la page d'indice `page_index` (0-based) en une `Canvas`.
    # `dpi` fixe la résolution ; l'arrière-plan est blanc.
    def self.render_page(reader : PDF::Reader, page_index : Int32, dpi : Int32 = DEFAULT_DPI) : Canvas
      page = reader.pages[page_index]
      scale = dpi / 72.0

      width_px = (page.width * scale).ceil.to_i
      height_px = (page.height * scale).ceil.to_i
      width_px = 1 if width_px < 1
      height_px = 1 if height_px < 1

      canvas = Canvas.new(width_px, height_px)

      # CTM de base : espace PDF (origine bas-gauche, y vers le haut)
      # vers pixels périphérique (origine haut-gauche, y vers le bas).
      base = Matrix.new(scale, 0.0, 0.0, -scale, 0.0, height_px.to_f)

      interpreter = Interpreter.new(canvas, base, reader, page.resources)
      page.content_streams.each { |stream| interpreter.run(stream) }

      canvas
    end

    # Nombre de pages du document (commodité).
    def self.page_count(reader : PDF::Reader) : Int32
      reader.page_count
    end
  end
end
