# Analyseur syntaxique PDF.
#
# Lit les octets bruts d'un fichier PDF et construit les objets
# correspondants (Dictionary, Array, Stream, etc.) en suivant
# la spécification ISO 32000-1:2008.
module PDF
  class Parser
    # Caractères considérés comme espacement en PDF
    WHITESPACE = Set{0x00_u8, 0x09_u8, 0x0A_u8, 0x0C_u8, 0x0D_u8, 0x20_u8}

    # Caractères délimiteurs en PDF
    DELIMITERS = Set{
      '('.ord.to_u8, ')'.ord.to_u8,
      '<'.ord.to_u8, '>'.ord.to_u8,
      '['.ord.to_u8, ']'.ord.to_u8,
      '{'.ord.to_u8, '}'.ord.to_u8,
      '/'.ord.to_u8, '%'.ord.to_u8,
    }

    # Données brutes du PDF
    getter data : Bytes

    # Table de correspondance numéro d'objet => offset en octets
    getter xref : Hash(Int32, Int64)

    # Dictionnaire trailer du PDF
    getter trailer : Objects::Dictionary

    # Version PDF extraite de l'en-tête
    getter version : String

    # Objets déjà analysés (cache)
    getter objects : Hash(Int32, Objects::Indirect)

    # Position courante dans le flux d'octets
    @pos : Int64

    def initialize(@data : Bytes)
      @pos = 0_i64
      @xref = {} of Int32 => Int64
      @trailer = Objects::Dictionary.new
      @version = ""
      @objects = {} of Int32 => Objects::Indirect
    end

    # Analyse la structure complète du PDF
    def parse! : Nil
      @version = parse_header
      xref_offset = find_xref_offset

      # Lire toutes les tables xref en suivant la chaîne /Prev
      # Chaque section xref est suivie de son trailer
      all_sections = [] of {Hash(Int32, Int64), Objects::Dictionary}
      current_offset = xref_offset

      loop do
        entries = parse_xref(current_offset)
        # @pos est maintenant juste après la table xref, devant "trailer"
        skip_whitespace
        trailer = parse_trailer
        all_sections << {entries, trailer}

        # Suivre /Prev pour la section xref précédente
        if prev = trailer["Prev"]?
          if prev_num = prev.as?(Objects::Number)
            current_offset = prev_num.to_i64
          else
            break
          end
        else
          break
        end
      end

      # Le trailer principal est celui de la section la plus récente
      @trailer = all_sections[0][1]

      # Fusionner les tables xref (les plus anciennes d'abord, les plus récentes écrasent)
      all_sections.reverse_each do |entries, _|
        entries.each do |obj_num, offset|
          @xref[obj_num] = offset
        end
      end
    end

    # Analyse un objet indirect à la position donnée
    def parse_object_at(offset : Int64) : Objects::Indirect
      @pos = offset
      obj_num = read_int
      skip_whitespace
      gen_num = read_int
      skip_whitespace
      expect_token("obj")
      skip_whitespace
      value = parse_value
      skip_whitespace
      # endobj peut être absent si c'est un stream (déjà lu dans parse_value)
      if @pos < @data.size
        token = peek_token
        if token == "endobj"
          read_token
        end
      end
      Objects::Indirect.new(obj_num, gen_num, value)
    end

    # Analyse une valeur PDF quelconque à la position courante
    def parse_value : Objects::Base
      skip_whitespace
      return Objects::Null.instance if @pos >= @data.size

      byte = peek_byte

      case byte
      when '<'.ord.to_u8
        # Dictionnaire << >> ou chaîne hexadécimale < >
        if @pos + 1 < @data.size && @data[@pos + 1] == '<'.ord.to_u8
          parse_dictionary
        else
          parse_hex_string
        end
      when '('.ord.to_u8
        parse_string
      when '['.ord.to_u8
        parse_array
      when '/'.ord.to_u8
        parse_name
      when '+'.ord.to_u8, '-'.ord.to_u8, '.'.ord.to_u8
        parse_number
      else
        if byte >= '0'.ord.to_u8 && byte <= '9'.ord.to_u8
          # Peut être un nombre ou une référence (N M R)
          parse_number_or_reference
        else
          # Mot-clé : true, false, null
          token = read_token
          case token
          when "true"
            Objects::Boolean.new(true)
          when "false"
            Objects::Boolean.new(false)
          when "null"
            Objects::Null.instance
          else
            # Valeur inattendue, on retourne null
            Objects::Null.instance
          end
        end
      end
    end

    # Analyse un dictionnaire PDF << ... >>
    # Peut retourner un Stream si le dictionnaire est suivi de "stream"
    def parse_dictionary : Objects::Base
      expect_bytes("<<")
      dict = Objects::Dictionary.new

      loop do
        skip_whitespace
        break if @pos >= @data.size

        # Vérifier la fin du dictionnaire
        if peek_byte == '>'.ord.to_u8 && @pos + 1 < @data.size && @data[@pos + 1] == '>'.ord.to_u8
          @pos += 2
          break
        end

        # Clé (doit être un Name)
        key = parse_name
        skip_whitespace

        # Valeur
        value = parse_value
        dict[key] = value
      end

      # Vérifier si un stream suit le dictionnaire
      skip_whitespace
      if @pos + 6 <= @data.size
        maybe_stream = String.new(@data[@pos, 6])
        if maybe_stream == "stream"
          return parse_stream(dict)
        end
      end

      dict
    end

    # Analyse un stream PDF (appelé après le dictionnaire)
    def parse_stream(dict : Objects::Dictionary) : Objects::Stream
      expect_token("stream")

      # Sauter le retour à la ligne après "stream"
      # La spécification dit : CR, LF, ou CR+LF
      if @pos < @data.size && @data[@pos] == 0x0D_u8
        @pos += 1
      end
      if @pos < @data.size && @data[@pos] == 0x0A_u8
        @pos += 1
      end

      # Lire la longueur depuis le dictionnaire
      length = 0_i64
      if len_obj = dict["Length"]?
        case len_obj
        when Objects::Number
          length = len_obj.to_i64
        when Objects::Reference
          # Résoudre la référence pour obtenir la longueur
          # On doit analyser l'objet référencé
          if offset = @xref[len_obj.object_number]?
            saved_pos = @pos
            indirect = parse_object_at(offset)
            @pos = saved_pos
            if num = indirect.value.as?(Objects::Number)
              length = num.to_i64
            end
          end
        end
      end

      # Extraire les données brutes du stream
      stream_data = if length > 0 && (@pos + length) <= @data.size
                      @data[@pos, length]
                    else
                      Bytes.empty
                    end
      @pos += length

      # Sauter jusqu'à endstream
      skip_whitespace
      if @pos + 9 <= @data.size
        token = peek_token
        if token == "endstream"
          read_token
        end
      end

      # Décompresser si nécessaire
      decoded_data = decompress_stream(dict, stream_data)

      Objects::Stream.new(dict, decoded_data)
    end

    # Analyse un tableau PDF [ ... ]
    def parse_array : Objects::Array
      @pos += 1 # Sauter '['
      arr = Objects::Array.new

      loop do
        skip_whitespace
        break if @pos >= @data.size
        break if peek_byte == ']'.ord.to_u8

        arr << parse_value
      end

      @pos += 1 if @pos < @data.size # Sauter ']'
      arr
    end

    # Analyse une chaîne littérale PDF ( ... )
    def parse_string : Objects::Str
      @pos += 1 # Sauter '('
      result = IO::Memory.new
      depth = 1

      while @pos < @data.size && depth > 0
        byte = read_byte
        case byte
        when '('.ord.to_u8
          depth += 1
          result.write_byte(byte)
        when ')'.ord.to_u8
          depth -= 1
          result.write_byte(byte) if depth > 0
        when '\\'.ord.to_u8
          # Séquence d'échappement
          if @pos < @data.size
            next_byte = read_byte
            case next_byte
            when 'n'.ord.to_u8  then result.write_byte(0x0A_u8)
            when 'r'.ord.to_u8  then result.write_byte(0x0D_u8)
            when 't'.ord.to_u8  then result.write_byte(0x09_u8)
            when 'b'.ord.to_u8  then result.write_byte(0x08_u8)
            when 'f'.ord.to_u8  then result.write_byte(0x0C_u8)
            when '('.ord.to_u8  then result.write_byte('('.ord.to_u8)
            when ')'.ord.to_u8  then result.write_byte(')'.ord.to_u8)
            when '\\'.ord.to_u8 then result.write_byte('\\'.ord.to_u8)
            else
              if next_byte >= '0'.ord.to_u8 && next_byte <= '7'.ord.to_u8
                # Code octal (\ddd)
                octal = String.new(Bytes[next_byte])
                2.times do
                  if @pos < @data.size
                    b = peek_byte
                    if b >= '0'.ord.to_u8 && b <= '7'.ord.to_u8
                      octal += b.chr
                      @pos += 1
                    else
                      break
                    end
                  end
                end
                result.write_byte(octal.to_u8(8))
              else
                # Caractère d'échappement inconnu, on l'ignore
                result.write_byte(next_byte)
              end
            end
          end
        else
          result.write_byte(byte)
        end
      end

      Objects::Str.new(String.new(result.to_slice))
    end

    # Analyse une chaîne hexadécimale PDF < ... >
    def parse_hex_string : Objects::Str
      @pos += 1 # Sauter '<'
      hex = String.build do |io|
        while @pos < @data.size
          byte = peek_byte
          if byte == '>'.ord.to_u8
            @pos += 1
            break
          end
          if WHITESPACE.includes?(byte)
            @pos += 1
            next
          end
          io << byte.chr
          @pos += 1
        end
      end

      # Compléter avec un 0 si longueur impaire
      hex += "0" if hex.size.odd?

      # Convertir les paires hexadécimales en octets
      bytes = IO::Memory.new
      (0...hex.size).step(2) do |i|
        pair = hex[i, 2]
        bytes.write_byte(pair.to_u8(16))
      end

      Objects::Str.new(String.new(bytes.to_slice), hex: true)
    end

    # Analyse un nom PDF /Name
    def parse_name : Objects::Name
      @pos += 1 # Sauter '/'
      name = String.build do |io|
        while @pos < @data.size
          byte = peek_byte
          break if WHITESPACE.includes?(byte) || DELIMITERS.includes?(byte)

          if byte == '#'.ord.to_u8
            # Échappement hexadécimal #XX
            @pos += 1
            if @pos + 1 < @data.size
              hex = String.new(@data[@pos, 2])
              io << hex.to_u8(16).chr
              @pos += 2
            end
          else
            io << byte.chr
            @pos += 1
          end
        end
      end

      Objects::Name.new(name)
    end

    # Analyse un nombre PDF (entier ou réel)
    def parse_number : Objects::Number
      token = read_number_token
      if token.includes?('.')
        Objects::Number.new(token.to_f64)
      else
        Objects::Number.new(token.to_i64)
      end
    end

    # Analyse un nombre ou une référence indirecte (N M R)
    private def parse_number_or_reference : Objects::Base
      saved_pos = @pos
      token1 = read_number_token
      is_int1 = !token1.includes?('.')

      if is_int1
        saved_pos2 = @pos
        skip_whitespace
        if @pos < @data.size && peek_byte >= '0'.ord.to_u8 && peek_byte <= '9'.ord.to_u8
          token2 = read_number_token
          is_int2 = !token2.includes?('.')
          if is_int2
            skip_whitespace
            if @pos < @data.size && peek_byte == 'R'.ord.to_u8
              @pos += 1
              obj_num = token1.to_i32
              gen_num = token2.to_i32
              return Objects::Reference.new(obj_num, gen_num)
            end
          end
        end
        # Pas une référence, revenir à la position après le premier nombre
        @pos = saved_pos2
      end

      if token1.includes?('.')
        Objects::Number.new(token1.to_f64)
      else
        Objects::Number.new(token1.to_i64)
      end
    end

    # Analyse l'en-tête %PDF-X.Y
    private def parse_header : String
      @pos = 0
      line = read_line
      if line.starts_with?("%PDF-")
        line[5..]
      else
        "1.7"
      end
    end

    # Cherche l'offset de la table xref en partant de la fin.
    #
    # NOTE : la recherche est faite **au niveau octet**, sans passer
    # par `String#rindex`. Un PDF amendé par mise à jour incrémentale
    # (PDF spec § 7.5.6) contient typiquement un content stream
    # FlateDecode juste avant le second `startxref` ; ces octets
    # binaires (≥ 0x80) forment souvent des séquences UTF-8
    # multi-octets qui décalent les indices retournés par
    # `String#rindex` (qui compte des caractères, pas des octets).
    # Le résultat : `@pos = search_start + idx + 9` tombait à côté
    # et `read_int` lisait une chaîne vide → `Invalid Int32 ""`.
    def find_xref_offset : Int64
      # Chercher "startxref" dans les 1024 derniers octets, en
      # parcourant les octets en arrière depuis la fin du fichier.
      needle = "startxref".to_slice
      search_start = {0_i64, @data.size.to_i64 - 1024}.max
      idx = byte_rindex(@data, needle, search_start)
      raise "Table xref introuvable" unless idx

      # Se positionner juste après "startxref"
      @pos = idx + needle.size
      skip_whitespace
      read_int.to_i64
    end

    # Cherche la dernière occurrence de `needle` dans `haystack`,
    # à partir de l'offset `from` inclus. Retourne `nil` si absente.
    # Comparaison purement octet-à-octet — n'utilise pas la sémantique
    # de String / d'UTF-8 (cf. `find_xref_offset` pour le pourquoi).
    private def byte_rindex(haystack : Bytes, needle : Bytes, from : Int64) : Int64?
      return nil if needle.size == 0 || needle.size > haystack.size - from
      i = haystack.size.to_i64 - needle.size
      while i >= from
        match = true
        j = 0
        while j < needle.size
          if haystack[i + j] != needle[j]
            match = false
            break
          end
          j += 1
        end
        return i if match
        i -= 1
      end
      nil
    end

    # Analyse la table xref traditionnelle
    def parse_xref(offset : Int64) : Hash(Int32, Int64)
      @pos = offset
      result = {} of Int32 => Int64

      # Vérifier si c'est une table xref traditionnelle ou un stream xref
      token = read_token
      if token != "xref"
        # Peut être un stream de références croisées (PDF 1.5+)
        STDERR.puts "AVERTISSEMENT : stream xref détecté (PDF 1.5+), non supporté en v1"
        return result
      end

      # Lire les sous-sections
      loop do
        skip_whitespace
        break if @pos >= @data.size

        # Vérifier si c'est le début du trailer
        if peek_byte == 't'.ord.to_u8
          break
        end

        # Lire le numéro de départ et le nombre d'entrées
        first_obj = read_int
        skip_whitespace
        count = read_int
        skip_whitespace

        count.times do |i|
          obj_num = first_obj + i
          entry_offset = read_int.to_i64
          skip_whitespace
          _gen = read_int
          skip_whitespace
          flag = read_byte.chr
          skip_whitespace

          # 'n' = en usage, 'f' = libre
          if flag == 'n' && entry_offset > 0
            result[obj_num] = entry_offset
          end
        end
      end

      result
    end

    # Analyse le dictionnaire trailer
    private def parse_trailer : Objects::Dictionary
      expect_token("trailer")
      skip_whitespace
      result = parse_dictionary
      if dict = result.as?(Objects::Dictionary)
        dict
      else
        raise "Trailer invalide : dictionnaire attendu"
      end
    end

    # Saute les caractères d'espacement
    def skip_whitespace : Nil
      while @pos < @data.size
        byte = @data[@pos]
        if WHITESPACE.includes?(byte)
          @pos += 1
        elsif byte == '%'.ord.to_u8
          skip_comment
        else
          break
        end
      end
    end

    # Saute un commentaire (% jusqu'à fin de ligne)
    private def skip_comment : Nil
      while @pos < @data.size
        byte = @data[@pos]
        @pos += 1
        break if byte == 0x0A_u8 || byte == 0x0D_u8
      end
    end

    # Lit l'octet courant sans avancer
    def peek_byte : UInt8
      @data[@pos]
    end

    # Lit l'octet courant et avance
    def read_byte : UInt8
      byte = @data[@pos]
      @pos += 1
      byte
    end

    # Lit un jeton (séquence de caractères non-espace/non-délimiteur)
    def read_token : String
      skip_whitespace
      start = @pos
      while @pos < @data.size
        byte = @data[@pos]
        break if WHITESPACE.includes?(byte) || DELIMITERS.includes?(byte)
        @pos += 1
      end
      String.new(@data[start, @pos - start])
    end

    # Lit un jeton sans le consommer
    private def peek_token : String
      saved = @pos
      token = read_token
      @pos = saved
      token
    end

    # Lit un entier
    private def read_int : Int32
      skip_whitespace
      token = String.build do |io|
        while @pos < @data.size
          byte = @data[@pos]
          if (byte >= '0'.ord.to_u8 && byte <= '9'.ord.to_u8) || byte == '+'.ord.to_u8 || byte == '-'.ord.to_u8
            io << byte.chr
            @pos += 1
          else
            break
          end
        end
      end
      token.to_i32
    end

    # Lit un jeton numérique (entier ou réel)
    private def read_number_token : String
      String.build do |io|
        while @pos < @data.size
          byte = @data[@pos]
          if (byte >= '0'.ord.to_u8 && byte <= '9'.ord.to_u8) ||
             byte == '.'.ord.to_u8 || byte == '+'.ord.to_u8 || byte == '-'.ord.to_u8
            io << byte.chr
            @pos += 1
          else
            break
          end
        end
      end
    end

    # Lit une ligne complète
    private def read_line : String
      start = @pos
      while @pos < @data.size
        byte = @data[@pos]
        if byte == 0x0A_u8 || byte == 0x0D_u8
          line = String.new(@data[start, @pos - start])
          @pos += 1
          # Sauter CR+LF
          if @pos < @data.size && @data[@pos] == 0x0A_u8 && byte == 0x0D_u8
            @pos += 1
          end
          return line
        end
        @pos += 1
      end
      String.new(@data[start, @pos - start])
    end

    # Vérifie et consomme un jeton attendu
    private def expect_token(expected : String) : Nil
      skip_whitespace
      token = read_token
      if token != expected
        raise "Jeton attendu '#{expected}', trouvé '#{token}' à la position #{@pos}"
      end
    end

    # Vérifie et consomme une séquence d'octets attendue
    private def expect_bytes(expected : String) : Nil
      skip_whitespace
      expected.each_byte do |b|
        if @pos < @data.size && @data[@pos] == b
          @pos += 1
        else
          raise "Octets attendus '#{expected}' à la position #{@pos}"
        end
      end
    end

    # Décompresse les données d'un stream selon ses filtres
    private def decompress_stream(dict : Objects::Dictionary, data : Bytes) : Bytes
      filter = dict["Filter"]?
      return data unless filter

      case filter
      when Objects::Name
        apply_filter(filter.value, data)
      when Objects::Array
        result = data
        filter.each do |f|
          if name = f.as?(Objects::Name)
            result = apply_filter(name.value, result)
          end
        end
        result
      else
        data
      end
    end

    # Applique un filtre de décompression
    private def apply_filter(name : String, data : Bytes) : Bytes
      case name
      when "FlateDecode"
        Filters::Flate.new.decode(data)
      else
        # Filtre non supporté, retourner les données brutes
        STDERR.puts "AVERTISSEMENT : filtre '#{name}' non supporté"
        data
      end
    end
  end
end
