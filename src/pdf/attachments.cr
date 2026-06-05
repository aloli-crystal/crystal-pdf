module PDF
  # Énumère et extrait les fichiers attachés à un document PDF —
  # l'équivalent bibliothèque de l'utilitaire `pdfdetach` de
  # poppler-utils.
  #
  # Trois sources d'attachements sont parcourues (ISO 32000-1) :
  # - `/Root /Names /EmbeddedFiles` : l'arbre de noms des fichiers
  #   embarqués (§ 7.11.4), source principale.
  # - `/Root /AF` : les *associated files* (§ 14.13, PDF/A-3, Factur-X,
  #   ZUGFeRD).
  # - les annotations `/FileAttachment` des pages (§ 12.5.6.15).
  #
  # ```
  # files = PDF::AttachedFile.list("facture.pdf")
  # files.each { |f| puts "#{f.name} (#{f.size} octets)" }
  # File.write(files.first.name, files.first.data)
  # ```
  #
  # Lecture pure : les octets sont restitués décompressés depuis le flux
  # `/EF /F`, sans modification du document.
  struct AttachedFile
    # Nom de fichier (/UF de préférence, sinon /F), décodé en UTF-8.
    getter name : String

    # Description (/Desc), si présente.
    getter description : String?

    # Type MIME déclaré (/EF /F → stream /Subtype), si présent.
    getter mime_type : String?

    # Taille déclarée (/EF /F → stream /Params /Size), si présente.
    getter size : Int32?

    # Relation à l'attachement (/AFRelationship : Data, Source…), PDF/A-3.
    getter relationship : String?

    # Numéro d'objet indirect du flux de fichier embarqué.
    getter object_number : Int32

    # Référence au lecteur et au flux, pour extraire les octets à la demande.
    @reader : PDF::Reader
    @stream : PDF::Objects::Stream

    def initialize(
      @name : String,
      @description : String?,
      @mime_type : String?,
      @size : Int32?,
      @relationship : String?,
      @object_number : Int32,
      @reader : PDF::Reader,
      @stream : PDF::Objects::Stream,
    )
    end

    # Octets du fichier embarqué (décompressés).
    def data : Bytes
      @stream.data
    end

    # Ouvre un fichier et liste ses attachements.
    def self.list(path : String, password : String = "") : ::Array(AttachedFile)
      list(PDF::Reader.open(path, password))
    end

    # Liste les attachements d'un `PDF::Reader` déjà ouvert,
    # dédupliqués par numéro d'objet du flux et dans l'ordre de
    # découverte (arbre de noms, puis /AF, puis annotations).
    def self.list(reader : PDF::Reader) : ::Array(AttachedFile)
      seen = Set(Int32).new
      result = [] of AttachedFile

      collect = ->(filespec : PDF::Objects::Base?) do
        att = from_filespec(reader, filespec)
        return unless att
        return if seen.includes?(att.object_number)
        seen.add(att.object_number)
        result << att
      end

      # 1. Arbre de noms /Root /Names /EmbeddedFiles.
      root = resolve_dict(reader, reader.trailer["Root"]?)
      if root
        names = resolve_dict(reader, root["Names"]?)
        if names
          walk_name_tree(reader, names["EmbeddedFiles"]?) { |filespec| collect.call(filespec) }
        end

        # 2. Associated files /Root /AF (PDF/A-3).
        each_in_array(reader, root["AF"]?) { |filespec| collect.call(filespec) }
      end

      # 3. Annotations /FileAttachment des pages.
      reader.pages.each do |page|
        each_in_array(reader, page.page_dict["Annots"]?) do |annot|
          dict = reader.resolve(annot).as?(PDF::Objects::Dictionary)
          next unless dict
          subtype = dict["Subtype"]?.try { |s| reader.resolve(s).as?(PDF::Objects::Name) }
          next unless subtype && subtype.value == "FileAttachment"
          collect.call(dict["FS"]?)
        end
      end

      result
    end

    # Construit un `AttachedFile` à partir d'un dictionnaire de
    # spécification de fichier (/Filespec). Retourne nil si la structure
    # est incomplète (pas de flux embarqué exploitable).
    private def self.from_filespec(reader : PDF::Reader, filespec : PDF::Objects::Base?) : AttachedFile?
      return nil unless filespec
      spec = reader.resolve(filespec).as?(PDF::Objects::Dictionary)
      return nil unless spec

      ef = resolve_dict(reader, spec["EF"]?)
      return nil unless ef

      # Le flux embarqué : /F en priorité, /UF en repli.
      ef_ref = ef["F"]? || ef["UF"]?
      return nil unless ef_ref
      obj_num = ef_ref.as?(PDF::Objects::Reference).try(&.object_number) || 0
      stream = reader.resolve(ef_ref).as?(PDF::Objects::Stream)
      return nil unless stream

      name = text_string(reader, spec["UF"]?) ||
             text_string(reader, spec["F"]?) ||
             "[sans nom]"
      description = text_string(reader, spec["Desc"]?)
      relationship = spec["AFRelationship"]?.try { |r| reader.resolve(r).as?(PDF::Objects::Name).try(&.value) }

      mime_type = stream["Subtype"]?.try { |s| reader.resolve(s).as?(PDF::Objects::Name).try(&.value) }
      size = nil
      if params = resolve_dict(reader, stream["Params"]?)
        size = params["Size"]?.try { |s| reader.resolve(s).as?(PDF::Objects::Number).try(&.to_i64.to_i) }
      end

      AttachedFile.new(
        name: name,
        description: description,
        mime_type: mime_type,
        size: size,
        relationship: relationship,
        object_number: obj_num,
        reader: reader,
        stream: stream,
      )
    end

    # Parcourt un arbre de noms (ISO 32000-1 § 7.9.6) : nœuds /Kids
    # intermédiaires + feuilles /Names [clé valeur clé valeur …]. Ne
    # remonte que les valeurs (filespecs), pas les clés.
    private def self.walk_name_tree(reader : PDF::Reader, node : PDF::Objects::Base?, &block : PDF::Objects::Base ->) : Nil
      dict = resolve_dict(reader, node)
      return unless dict

      if kids = dict["Kids"]?
        each_in_array(reader, kids) do |kid|
          walk_name_tree(reader, kid, &block)
        end
      end

      if names_obj = dict["Names"]?
        if names = reader.resolve(names_obj).as?(PDF::Objects::Array)
          i = 1
          while i < names.size
            block.call(names.unsafe_fetch(i))
            i += 2
          end
        end
      end
    end

    # Applique le bloc à chaque élément d'un objet tableau (résolu).
    private def self.each_in_array(reader : PDF::Reader, obj : PDF::Objects::Base?, &block : PDF::Objects::Base ->) : Nil
      return unless obj
      arr = reader.resolve(obj).as?(PDF::Objects::Array)
      return unless arr
      arr.each { |item| block.call(item) }
    end

    private def self.resolve_dict(reader : PDF::Reader, obj : PDF::Objects::Base?) : PDF::Objects::Dictionary?
      return nil unless obj
      reader.resolve(obj).as?(PDF::Objects::Dictionary)
    end

    private def self.text_string(reader : PDF::Reader, obj : PDF::Objects::Base?) : String?
      return nil unless obj
      str = reader.resolve(obj).as?(PDF::Objects::Str)
      return nil unless str
      PDF::Info.decode_text_string(str.value)
    end
  end
end
