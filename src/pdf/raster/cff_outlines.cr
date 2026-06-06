module PDF
  module Raster
    # Interpréteur de charstring Type 2 (CFF, Adobe spec § 4.3) : exécute
    # le bytecode d'un glyphe et produit ses contours, en unités de
    # fonte (1000 par em par défaut). Les courbes de Bézier cubiques
    # sont aplaties en segments.
    #
    # Couvre les opérateurs de tracé (move/line/curve), les sous-routines
    # locales et globales (avec biais), les indices d'astuces (hstem…,
    # hintmask) sautés, et les opérateurs flex.
    class CFFOutlines
      alias Point = Tuple(Float64, Float64)
      alias Contour = Array(Point)

      CURVE_STEPS = 8

      # Chasse (avance) du dernier glyphe exécuté, en unités de fonte.
      getter width : Float64

      @gsubrs : Array(Bytes)
      @lsubrs : Array(Bytes)
      @gbias : Int32
      @lbias : Int32

      def initialize(@parser : PDF::Fonts::CFF::Parser? = nil)
        @stack = [] of Float64
        @contours = [] of Contour
        @subpath = [] of Point
        @x = 0.0
        @y = 0.0
        @n_stems = 0
        @have_width = false
        @gsubrs = @parser.try(&.global_subrs.entries) || [] of Bytes
        @lsubrs = [] of Bytes
        @gbias = bias(@gsubrs.size)
        @lbias = 107
        @done = false
        @width = 0.0
        @default_width = 0.0
        @nominal_width = 0.0
      end

      # Contours du glyphe `gid` (index dans le CharStrings INDEX).
      def self.outline(parser : PDF::Fonts::CFF::Parser, gid : Int32) : Array(Contour)
        new(parser).run(gid)
      rescue
        [] of Array(Point)
      end

      # Contours + chasse du glyphe `gid`.
      def self.run_glyph(parser : PDF::Fonts::CFF::Parser, gid : Int32) : Tuple(Array(Contour), Float64)
        inst = new(parser)
        contours = inst.run(gid)
        {contours, inst.width}
      rescue
        {[] of Array(Point), 0.0}
      end

      # Exécute un charstring brut (point d'entrée testable, sans parser).
      def self.run_charstring(charstring : Bytes, gsubrs : Array(Bytes) = [] of Bytes, lsubrs : Array(Bytes) = [] of Bytes, default_width : Float64 = 0.0, nominal_width : Float64 = 0.0) : Tuple(Array(Contour), Float64)
        new.interpret(charstring, gsubrs, lsubrs, default_width, nominal_width)
      end

      protected def interpret(charstring : Bytes, gsubrs : Array(Bytes), lsubrs : Array(Bytes), default_width : Float64, nominal_width : Float64) : Tuple(Array(Contour), Float64)
        @gsubrs = gsubrs
        @gbias = bias(gsubrs.size)
        @lsubrs = lsubrs
        @lbias = bias(lsubrs.size)
        @default_width = default_width
        @nominal_width = nominal_width
        @width = default_width
        execute(charstring)
        close_subpath
        {@contours, @width}
      end

      protected def run(gid : Int32) : Array(Contour)
        parser = @parser
        return @contours unless parser
        charstrings = parser.charstrings.entries
        return @contours unless 0 <= gid < charstrings.size
        @lsubrs = local_subrs_for(gid)
        @lbias = bias(@lsubrs.size)
        load_widths(gid)
        @width = @default_width
        execute(charstrings[gid])
        close_subpath
        @contours
      end

      # Charge defaultWidthX (op 20) et nominalWidthX (op 21) depuis le
      # Private DICT approprié (par FD pour les CIDFonts).
      private def load_widths(gid : Int32) : Nil
        parser = @parser
        return unless parser
        priv = if parser.cid_font?
                 fd = parser.fd_select[gid]? || 0
                 parser.fd_privates[fd]? || parser.private_dict
               else
                 parser.private_dict
               end
        @default_width = priv[20]?.try(&.first?) || 0.0
        @nominal_width = priv[21]?.try(&.first?) || 0.0
      end

      # Sélectionne les Local Subrs : par FD pour les CIDFonts, globaux
      # sinon.
      private def local_subrs_for(gid : Int32) : Array(Bytes)
        parser = @parser
        return [] of Bytes unless parser
        if parser.cid_font?
          fd = parser.fd_select[gid]? || 0
          subrs = parser.fd_local_subrs[fd]?
          return subrs.entries if subrs
          [] of Bytes
        else
          parser.local_subrs.entries
        end
      end

      private def execute(code : Bytes) : Nil
        i = 0
        n = code.size
        while i < n && !@done
          b0 = code[i]
          if b0 >= 32 || b0 == 28
            i = read_operand(code, i, b0)
          else
            i += 1
            case b0
            when 1, 3, 18, 23 then stems
            when 19, 20       then i = hintmask(code, i)
            when 21           then rmoveto
            when 22           then hvmoveto(horizontal: true)
            when 4            then hvmoveto(horizontal: false)
            when 5            then rlineto
            when 6            then hvlineto(start_h: true)
            when 7            then hvlineto(start_h: false)
            when 8            then rrcurveto
            when 24           then rcurveline
            when 25           then rlinecurve
            when 26           then vvcurveto
            when 27           then hhcurveto
            when 30           then vhcurveto(start_h: false)
            when 31           then vhcurveto(start_h: true)
            when 10           then call(@lsubrs, @lbias)
            when 29           then call(@gsubrs, @gbias)
            when 11           then return
            when 14           then @done = true
            when 12           then escape(code[i]?); i += 1
            else                   @stack.clear
            end
          end
        end
      end

      private def read_operand(code : Bytes, i : Int32, b0 : UInt8) : Int32
        if b0 == 28
          v = ((code[i + 1].to_i << 8) | code[i + 2].to_i)
          v -= 0x10000 if v >= 0x8000
          @stack << v.to_f
          i + 3
        elsif b0 < 247
          @stack << (b0.to_i - 139).to_f
          i + 1
        elsif b0 < 251
          @stack << ((b0.to_i - 247) * 256 + code[i + 1].to_i + 108).to_f
          i + 2
        elsif b0 < 255
          @stack << (-(b0.to_i - 251) * 256 - code[i + 1].to_i - 108).to_f
          i + 2
        else
          v = ((code[i + 1].to_i << 24) | (code[i + 2].to_i << 16) | (code[i + 3].to_i << 8) | code[i + 4].to_i)
          v -= 0x1_0000_0000 if v >= 0x8000_0000
          @stack << v / 65536.0
          i + 5
        end
      end

      # --- opérateurs de tracé ---

      private def rmoveto : Nil
        check_width(2)
        @x += arg(0)
        @y += arg(1)
        start_subpath
        @stack.clear
      end

      private def hvmoveto(horizontal : Bool) : Nil
        check_width(1)
        if horizontal
          @x += arg(0)
        else
          @y += arg(0)
        end
        start_subpath
        @stack.clear
      end

      private def rlineto : Nil
        i = 0
        while i + 1 < @stack.size
          @x += @stack[i]
          @y += @stack[i + 1]
          @subpath << {@x, @y}
          i += 2
        end
        @stack.clear
      end

      private def hvlineto(start_h : Bool) : Nil
        horiz = start_h
        @stack.each do |d|
          if horiz
            @x += d
          else
            @y += d
          end
          @subpath << {@x, @y}
          horiz = !horiz
        end
        @stack.clear
      end

      private def rrcurveto : Nil
        i = 0
        while i + 5 < @stack.size
          curve(@stack[i], @stack[i + 1], @stack[i + 2], @stack[i + 3], @stack[i + 4], @stack[i + 5])
          i += 6
        end
        @stack.clear
      end

      private def rcurveline : Nil
        i = 0
        while i + 5 < @stack.size - 2
          curve(@stack[i], @stack[i + 1], @stack[i + 2], @stack[i + 3], @stack[i + 4], @stack[i + 5])
          i += 6
        end
        @x += @stack[i]
        @y += @stack[i + 1]
        @subpath << {@x, @y}
        @stack.clear
      end

      private def rlinecurve : Nil
        i = 0
        while i + 1 < @stack.size - 6
          @x += @stack[i]
          @y += @stack[i + 1]
          @subpath << {@x, @y}
          i += 2
        end
        curve(@stack[i], @stack[i + 1], @stack[i + 2], @stack[i + 3], @stack[i + 4], @stack[i + 5])
        @stack.clear
      end

      private def vvcurveto : Nil
        i = 0
        dx1 = 0.0
        if @stack.size.odd?
          dx1 = @stack[0]
          i = 1
        end
        while i + 3 < @stack.size
          curve(dx1, @stack[i], @stack[i + 1], @stack[i + 2], 0.0, @stack[i + 3])
          dx1 = 0.0
          i += 4
        end
        @stack.clear
      end

      private def hhcurveto : Nil
        i = 0
        dy1 = 0.0
        if @stack.size.odd?
          dy1 = @stack[0]
          i = 1
        end
        while i + 3 < @stack.size
          curve(@stack[i], dy1, @stack[i + 1], @stack[i + 2], @stack[i + 3], 0.0)
          dy1 = 0.0
          i += 4
        end
        @stack.clear
      end

      private def vhcurveto(start_h : Bool) : Nil
        horiz = start_h
        i = 0
        size = @stack.size
        while i + 3 < size
          last = (size - i) == 5
          df = last ? @stack[i + 4] : 0.0
          if horiz
            curve(@stack[i], 0.0, @stack[i + 1], @stack[i + 2], df, @stack[i + 3])
          else
            curve(0.0, @stack[i], @stack[i + 1], @stack[i + 2], @stack[i + 3], df)
          end
          horiz = !horiz
          i += 4
        end
        @stack.clear
      end

      private def escape(op : UInt8?) : Nil
        case op
        when 35 # flex
          curve(@stack[0], @stack[1], @stack[2], @stack[3], @stack[4], @stack[5])
          curve(@stack[6], @stack[7], @stack[8], @stack[9], @stack[10], @stack[11])
        when 34 # hflex
          curve(@stack[0], 0.0, @stack[1], @stack[2], @stack[3], 0.0)
          curve(@stack[4], 0.0, @stack[5], -@stack[2], @stack[6], 0.0)
        when 36 # hflex1
          curve(@stack[0], @stack[1], @stack[2], @stack[3], @stack[4], 0.0)
          curve(@stack[5], 0.0, @stack[6], @stack[7], @stack[8], -(@stack[1] + @stack[3] + @stack[7]))
        when 37 # flex1
          dx = @stack[0] + @stack[2] + @stack[4] + @stack[6] + @stack[8]
          dy = @stack[1] + @stack[3] + @stack[5] + @stack[7] + @stack[9]
          curve(@stack[0], @stack[1], @stack[2], @stack[3], @stack[4], @stack[5])
          if dx.abs > dy.abs
            curve(@stack[6], @stack[7], @stack[8], @stack[9], @stack[10], -dy)
          else
            curve(@stack[6], @stack[7], @stack[8], @stack[9], -dx, @stack[10])
          end
        end
        @stack.clear
      end

      # --- sous-routines & astuces ---

      private def call(subrs : Array(Bytes), bias : Int32) : Nil
        return if @stack.empty?
        idx = @stack.pop.to_i + bias
        execute(subrs[idx]) if 0 <= idx < subrs.size
      end

      private def stems : Nil
        check_width_even
        @n_stems += @stack.size // 2
        @stack.clear
      end

      private def hintmask(code : Bytes, i : Int32) : Int32
        check_width_even
        @n_stems += @stack.size // 2
        @stack.clear
        i + (@n_stems + 7) // 8
      end

      # --- gestion de la chasse (width) ---

      private def check_width(expected : Int32) : Nil
        return if @have_width
        @have_width = true
        @width = @nominal_width + @stack.shift if @stack.size > expected
      end

      private def check_width_even : Nil
        return if @have_width
        @have_width = true
        @width = @nominal_width + @stack.shift if @stack.size.odd?
      end

      # --- géométrie ---

      private def curve(dx1 : Float64, dy1 : Float64, dx2 : Float64, dy2 : Float64, dx3 : Float64, dy3 : Float64) : Nil
        x0 = @x
        y0 = @y
        x1 = x0 + dx1
        y1 = y0 + dy1
        x2 = x1 + dx2
        y2 = y1 + dy2
        x3 = x2 + dx3
        y3 = y2 + dy3
        (1..CURVE_STEPS).each do |k|
          t = k.to_f / CURVE_STEPS
          u = 1.0 - t
          a = u * u * u
          b = 3 * u * u * t
          c = 3 * u * t * t
          d = t * t * t
          @subpath << {a * x0 + b * x1 + c * x2 + d * x3, a * y0 + b * y1 + c * y2 + d * y3}
        end
        @x = x3
        @y = y3
      end

      private def start_subpath : Nil
        close_subpath
        @subpath = [{@x, @y}] of Point
      end

      private def close_subpath : Nil
        @contours << @subpath if @subpath.size >= 3
        @subpath = [] of Point
      end

      private def arg(i : Int32) : Float64
        @stack[i]? || 0.0
      end

      private def bias(n : Int32) : Int32
        n < 1240 ? 107 : (n < 33900 ? 1131 : 32768)
      end
    end
  end
end
