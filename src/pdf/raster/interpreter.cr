module PDF
  module Raster
    # Interprète un flux de contenu PDF et peint le résultat vectoriel
    # sur une `Canvas`. MVP : chemins (construction + remplissage +
    # trait), graphismes d'état (q/Q/cm/w), couleurs Device
    # (gray/rgb/cmyk + sc/scn par nombre de composantes).
    #
    # Hors périmètre du MVP (les opérateurs sont consommés sans effet
    # visible) : texte (BT…ET), images (Do, images en ligne), motifs,
    # détourage (W/W*), fondu (ca/CA via ExtGState).
    class Interpreter
      alias Point = Tuple(Float64, Float64)

      # État graphique courant (pile via q/Q).
      private struct State
        property ctm : Matrix
        property fill : Tuple(Float64, Float64, Float64)
        property stroke : Tuple(Float64, Float64, Float64)
        property line_width : Float64

        def initialize(@ctm : Matrix, @fill = {0.0, 0.0, 0.0}, @stroke = {0.0, 0.0, 0.0}, @line_width = 1.0)
        end

        def dup_state : State
          State.new(@ctm, @fill, @stroke, @line_width)
        end
      end

      # Nombre de segments pour aplatir une courbe de Bézier cubique.
      BEZIER_STEPS = 18

      def initialize(@canvas : Canvas, base_ctm : Matrix)
        @state = State.new(base_ctm)
        @stack = [] of State
        @path = [] of Canvas::SubPath
        @subpath = [] of Point
        @current = {0.0, 0.0}
        @start = {0.0, 0.0}
        @nums = [] of Float64
      end

      # Exécute un flux de contenu (octets décompressés) sur la toile.
      def run(data : Bytes) : Nil
        ContentLexer.tokenize(data).each { |tok| handle(tok) }
      end

      private def handle(tok : ContentLexer::Token) : Nil
        case tok.kind
        when :num
          @nums << tok.num
        when :op
          execute(tok.text)
          @nums.clear
        else
          # noms, chaînes, délimiteurs de tableau/dict : ignorés (les
          # nombres internes seront vidés par le prochain opérateur).
        end
      end

      private def execute(op : String) : Nil
        case op
        when "q"  then @stack << @state.dup_state
        when "Q"  then @state = @stack.pop? || @state
        when "cm" then concat_matrix
        when "w"  then @state.line_width = arg(0)
        when "m"  then move_to(arg(0), arg(1))
        when "l"  then line_to(arg(0), arg(1))
        when "c"  then curve_to(arg(0), arg(1), arg(2), arg(3), arg(4), arg(5))
        when "v"  then curve_to(@current[0], @current[1], arg(0), arg(1), arg(2), arg(3), pre_transformed: true)
        when "y"  then curve_to(arg(0), arg(1), arg(2), arg(3), arg(2), arg(3))
        when "re" then rectangle(arg(0), arg(1), arg(2), arg(3))
        when "h"  then close_subpath
        when "n"  then end_path
        when "W", "W*"
          # Détourage non implémenté (MVP) : on poursuit sans clip.
        when "f", "F", "f*" then paint(fill: true, stroke: false, even_odd: op == "f*")
        when "S"            then paint(fill: false, stroke: true, even_odd: false)
        when "s"            then close_subpath; paint(fill: false, stroke: true, even_odd: false)
        when "B", "B*"      then paint(fill: true, stroke: true, even_odd: op == "B*")
        when "b", "b*"      then close_subpath; paint(fill: true, stroke: true, even_odd: op == "b*")
        when "g"            then @state.fill = gray(arg(0))
        when "G"            then @state.stroke = gray(arg(0))
        when "rg"           then @state.fill = {arg(0), arg(1), arg(2)}
        when "RG"           then @state.stroke = {arg(0), arg(1), arg(2)}
        when "k"            then @state.fill = cmyk(arg(0), arg(1), arg(2), arg(3))
        when "K"            then @state.stroke = cmyk(arg(0), arg(1), arg(2), arg(3))
        when "sc", "scn"    then @state.fill = color_from_components
        when "SC", "SCN"    then @state.stroke = color_from_components
        else
          # Opérateur non géré (texte, images, ExtGState…) : ignoré.
        end
      end

      # --- Construction de chemin (points transformés par la CTM) ---

      private def move_to(x : Float64, y : Float64) : Nil
        flush_subpath
        @current = @state.ctm.apply(x, y)
        @start = @current
        @subpath = [@current] of Point
      end

      private def line_to(x : Float64, y : Float64) : Nil
        @current = @state.ctm.apply(x, y)
        @subpath << @current
      end

      # Bézier cubique. Les coordonnées passées sont en espace
      # utilisateur sauf si `pre_transformed` (cas de l'opérateur `v`,
      # dont le 1er point de contrôle est déjà en device).
      private def curve_to(x1 : Float64, y1 : Float64, x2 : Float64, y2 : Float64, x3 : Float64, y3 : Float64, pre_transformed : Bool = false) : Nil
        p0 = @current
        p1 = pre_transformed ? {x1, y1} : @state.ctm.apply(x1, y1)
        p2 = @state.ctm.apply(x2, y2)
        p3 = @state.ctm.apply(x3, y3)
        (1..BEZIER_STEPS).each do |i|
          t = i.to_f / BEZIER_STEPS
          @subpath << bezier(p0, p1, p2, p3, t)
        end
        @current = p3
      end

      private def rectangle(x : Float64, y : Float64, w : Float64, h : Float64) : Nil
        flush_subpath
        ctm = @state.ctm
        @subpath = [
          ctm.apply(x, y), ctm.apply(x + w, y),
          ctm.apply(x + w, y + h), ctm.apply(x, y + h),
        ] of Point
        @current = ctm.apply(x, y)
        @start = @current
        flush_subpath
      end

      private def close_subpath : Nil
        return if @subpath.empty?
        @subpath << @start
        @current = @start
      end

      private def flush_subpath : Nil
        @path << @subpath if @subpath.size >= 2
        @subpath = [] of Point
      end

      private def end_path : Nil
        @path.clear
        @subpath = [] of Point
      end

      private def paint(fill : Bool, stroke : Bool, even_odd : Bool) : Nil
        flush_subpath
        return if @path.empty?
        if fill
          r, g, b = @state.fill
          @canvas.fill(@path, r, g, b, even_odd)
        end
        if stroke
          r, g, b = @state.stroke
          width = @state.line_width * @state.ctm.mean_scale
          @canvas.stroke(@path, width, r, g, b)
        end
        end_path
      end

      # --- Graphismes d'état & couleurs ---

      private def concat_matrix : Nil
        m = Matrix.new(arg(0), arg(1), arg(2), arg(3), arg(4), arg(5))
        @state.ctm = m.then(@state.ctm)
      end

      private def gray(v : Float64) : Tuple(Float64, Float64, Float64)
        {v, v, v}
      end

      private def cmyk(c : Float64, m : Float64, y : Float64, k : Float64) : Tuple(Float64, Float64, Float64)
        PDF::Content::Color.cmyk_to_rgb(c, m, y, k)
      end

      # sc/scn/SC/SCN : on déduit l'espace du nombre de composantes.
      private def color_from_components : Tuple(Float64, Float64, Float64)
        case @nums.size
        when 1 then gray(@nums[0])
        when 3 then {@nums[0], @nums[1], @nums[2]}
        when 4 then cmyk(@nums[0], @nums[1], @nums[2], @nums[3])
        else        @state.fill # motif/indexé non géré : on garde la couleur courante
        end
      end

      # --- Helpers ---

      private def arg(i : Int32) : Float64
        @nums[i]? || 0.0
      end

      private def bezier(p0 : Point, p1 : Point, p2 : Point, p3 : Point, t : Float64) : Point
        u = 1.0 - t
        a = u * u * u
        b = 3 * u * u * t
        c = 3 * u * t * t
        d = t * t * t
        {
          a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0],
          a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1],
        }
      end
    end
  end
end
