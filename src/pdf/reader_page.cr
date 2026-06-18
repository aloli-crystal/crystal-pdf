# Représente une page lue depuis un PDF existant.
#
# Donne accès aux dimensions, au dictionnaire de page,
# aux flux de contenu et aux ressources. Permet aussi
# d'ajouter de nouveaux flux de contenu (pour le filigrane).
module PDF
  class ReaderPage
    # Largeur de la page en points
    getter width : Float64

    # Hauteur de la page en points
    getter height : Float64

    # Dictionnaire de la page tel que lu dans le PDF
    getter page_dict : Objects::Dictionary

    # Numéro d'objet indirect de cette page
    getter object_number : Int32

    # Référence au lecteur parent pour résoudre les références
    @reader : Reader

    # Nouveaux flux de contenu ajoutés (pour le filigrane)
    @added_streams : ::Array(String)

    def initialize(@reader : Reader, @page_dict : Objects::Dictionary, @object_number : Int32)
      @added_streams = [] of String

      # Extraire les dimensions depuis /MediaBox
      media_box = resolve_media_box
      @width = media_box[2]
      @height = media_box[3]
    end

    # Retourne les flux de contenu existants (décompressés)
    def content_streams : ::Array(Bytes)
      streams = [] of Bytes
      contents = @page_dict["Contents"]?
      return streams unless contents

      # Résoudre si c'est une référence
      contents = @reader.resolve(contents)

      case contents
      when Objects::Stream
        streams << contents.data
      when Objects::Array
        contents.each do |item|
          resolved = @reader.resolve(item)
          if stream = resolved.as?(Objects::Stream)
            streams << stream.data
          end
        end
      end

      streams
    end

    # Ajoute un nouveau flux de contenu (pour le filigrane)
    def add_content_stream(data : String) : Nil
      @added_streams << data
    end

    # Retourne les flux de contenu ajoutés
    def added_streams : ::Array(String)
      @added_streams
    end

    # Retourne l'angle de rotation déclaré pour la page
    # (ISO 32000-1 § 14.8 — /Rotate), héritable depuis l'arbre
    # /Pages. Valeurs autorisées : 0, 90, 180, 270 (modulo 360,
    # normalisées dans [0, 360[). Une page sans /Rotate ni hérité
    # retourne 0.
    #
    # Utile pour détecter les PDFs dont une page a été tournée par
    # un viewer (Aperçu macOS, Acrobat) via le tag /Rotate plutôt
    # qu'en réécrivant le contenu : un assemblage naïf laisserait
    # la page à l'envers dans le PDF final. À combiner avec un
    # `qpdf --flatten-rotation` côté caller pour cuire la rotation.
    def rotate : Int32
      val = @page_dict["Rotate"]?

      # Héritage : remonter l'arbre /Pages si non trouvé localement.
      unless val
        if parent_ref = @page_dict["Parent"]?
          parent = @reader.resolve(parent_ref)
          if parent_dict = parent.as?(Objects::Dictionary)
            val = parent_dict["Rotate"]?
          end
        end
      end

      val = @reader.resolve(val) if val
      degrees = val.try(&.as?(Objects::Number)).try(&.to_i64.to_i32) || 0
      ((degrees % 360) + 360) % 360
    end

    # Retourne le dictionnaire de ressources de la page
    def resources : Objects::Dictionary
      res = @page_dict["Resources"]?
      res = @reader.resolve(res) if res

      case res
      when Objects::Dictionary
        res
      else
        Objects::Dictionary.new
      end
    end

    # Extrait le MediaBox en résolvant les références si nécessaire
    private def resolve_media_box : ::Array(Float64)
      box = @page_dict["MediaBox"]?

      # Chercher dans le parent si absent
      unless box
        if parent_ref = @page_dict["Parent"]?
          parent = @reader.resolve(parent_ref)
          if parent_dict = parent.as?(Objects::Dictionary)
            box = parent_dict["MediaBox"]?
          end
        end
      end

      # Résoudre la référence si c'est une
      box = @reader.resolve(box) if box

      if arr = box.as?(Objects::Array)
        values = [] of Float64
        arr.each do |item|
          resolved = @reader.resolve(item)
          if num = resolved.as?(Objects::Number)
            values << num.to_f64
          end
        end
        return values if values.size == 4
      end

      # Valeurs par défaut : Letter US
      [0.0, 0.0, 612.0, 792.0]
    end
  end
end
