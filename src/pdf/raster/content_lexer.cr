module PDF
  module Raster
    # Tokeniseur de flux de contenu PDF (ISO 32000-1 § 7.8.2) pour le
    # rasterizer. Produit une suite de jetons : nombres, noms,
    # chaînes, délimiteurs de tableau / dictionnaire, et opérateurs.
    #
    # Les images en ligne (`BI … ID … EI`) sont sautées en bloc — leurs
    # données binaires ne doivent pas être interprétées comme des
    # jetons. Le rendu des images en ligne est hors périmètre du MVP.
    module ContentLexer
      # Un jeton du flux de contenu. `kind` ∈ {:num, :name, :str, :op,
      # :array_start, :array_end, :dict_start, :dict_end}.
      record Token,
        kind : Symbol,
        num : Float64 = 0.0,
        text : String = ""

      WHITESPACE = {' ', '\t', '\r', '\n', '\f', '\0'}
      DELIMITERS = {'(', ')', '<', '>', '[', ']', '{', '}', '/', '%'}

      # Découpe les octets d'un flux de contenu en jetons.
      def self.tokenize(data : Bytes) : Array(Token)
        tokens = [] of Token
        i = 0
        n = data.size
        while i < n
          c = data[i].unsafe_chr
          if WHITESPACE.includes?(c)
            i += 1
          elsif c == '%'
            i += 1
            while i < n && data[i] != 0x0A_u8 && data[i] != 0x0D_u8
              i += 1
            end
          elsif c == '['
            tokens << Token.new(:array_start)
            i += 1
          elsif c == ']'
            tokens << Token.new(:array_end)
            i += 1
          elsif c == '<' && i + 1 < n && data[i + 1].unsafe_chr == '<'
            tokens << Token.new(:dict_start)
            i += 2
          elsif c == '>' && i + 1 < n && data[i + 1].unsafe_chr == '>'
            tokens << Token.new(:dict_end)
            i += 2
          elsif c == '('
            i = lex_literal_string(data, i, tokens)
          elsif c == '<'
            i = lex_hex_string(data, i, tokens)
          elsif c == '/'
            i = lex_name(data, i, tokens)
          elsif c == '+' || c == '-' || c == '.' || ('0' <= c <= '9')
            i = lex_number(data, i, tokens)
          else
            i = lex_operator(data, i, tokens)
          end
        end
        tokens
      end

      private def self.lex_number(data : Bytes, start : Int32, tokens : Array(Token)) : Int32
        i = start
        n = data.size
        while i < n
          c = data[i].unsafe_chr
          break unless c == '+' || c == '-' || c == '.' || c == 'e' || c == 'E' || ('0' <= c <= '9')
          i += 1
        end
        slice = String.new(data[start, i - start])
        tokens << Token.new(:num, num: slice.to_f64? || 0.0)
        i
      end

      private def self.lex_name(data : Bytes, start : Int32, tokens : Array(Token)) : Int32
        i = start + 1 # saute '/'
        n = data.size
        while i < n
          c = data[i].unsafe_chr
          break if WHITESPACE.includes?(c) || DELIMITERS.includes?(c)
          i += 1
        end
        tokens << Token.new(:name, text: String.new(data[start + 1, i - start - 1]))
        i
      end

      private def self.lex_operator(data : Bytes, start : Int32, tokens : Array(Token)) : Int32
        i = start
        n = data.size
        while i < n
          c = data[i].unsafe_chr
          break if WHITESPACE.includes?(c) || DELIMITERS.includes?(c)
          i += 1
        end
        op = String.new(data[start, i - start])
        # Image en ligne : sauter jusqu'à `EI`.
        if op == "BI"
          return skip_inline_image(data, i)
        end
        tokens << Token.new(:op, text: op) unless op.empty?
        i
      end

      private def self.lex_literal_string(data : Bytes, start : Int32, tokens : Array(Token)) : Int32
        i = start + 1
        n = data.size
        depth = 1
        while i < n && depth > 0
          c = data[i]
          if c == '\\'.ord
            i += 2
            next
          elsif c == '('.ord
            depth += 1
          elsif c == ')'.ord
            depth -= 1
          end
          i += 1
        end
        # Contenu non décodé : le rendu de texte est hors MVP.
        tokens << Token.new(:str)
        i
      end

      private def self.lex_hex_string(data : Bytes, start : Int32, tokens : Array(Token)) : Int32
        i = start + 1
        n = data.size
        while i < n && data[i].unsafe_chr != '>'
          i += 1
        end
        i += 1 if i < n
        tokens << Token.new(:str)
        i
      end

      private def self.skip_inline_image(data : Bytes, start : Int32) : Int32
        i = start
        n = data.size
        # Cherche la séquence `EI` délimitée par des espaces.
        while i < n - 1
          if data[i].unsafe_chr == 'E' && data[i + 1].unsafe_chr == 'I' &&
             (i + 2 >= n || WHITESPACE.includes?(data[i + 2].unsafe_chr))
            return i + 2
          end
          i += 1
        end
        n
      end
    end
  end
end
