# Lecteur de fichiers PDF existants.
#
# Point d'entrée principal pour ouvrir et lire un PDF.
# Permet d'accéder aux pages, de résoudre les références,
# et de sauvegarder un PDF modifié (mise à jour incrémentale).
#
# ```
# reader = PDF::Reader.open("document.pdf")
# puts reader.page_count
# reader.pages.each { |page| puts "#{page.width}x#{page.height}" }
# ```
module PDF
  class Reader
    # Objets indirects indexés par numéro d'objet
    getter objects : Hash(Int32, Objects::Indirect)

    # Pages du document
    getter pages : ::Array(ReaderPage)

    # Dictionnaire trailer
    getter trailer : Objects::Dictionary

    # Version du PDF
    getter version : String

    # Données brutes du PDF
    @data : Bytes

    # Analyseur syntaxique
    @parser : Parser

    # Table xref (numéro d'objet => offset)
    @xref : Hash(Int32, Int64)

    # Prochain numéro d'objet disponible pour les nouveaux objets
    @next_object_number : Int32

    # Objets indirects ajoutés à émettre lors de la prochaine mise à
    # jour incrémentale (cf. `add_object`).
    @added_objects = [] of Objects::Indirect

    # Objets existants modifiés à ré-émettre (numéro d'objet => valeur ;
    # cf. `replace_object`). Sert notamment à réécrire le catalogue.
    @modified_objects = {} of Int32 => Objects::Base

    # Ouvre un PDF depuis un chemin de fichier. `password` est
    # le mot de passe utilisateur si le PDF est chiffré (vide par
    # défaut, ce qui suffit pour la majorité des PDFs « owner-only
    # protected »).
    def self.open(path : String, password : String = "") : Reader
      data = File.read(path).to_slice
      new(data, password)
    end

    # Ouvre un PDF depuis un flux IO.
    def self.open(io : IO, password : String = "") : Reader
      data = io.gets_to_end.to_slice
      new(data, password)
    end

    def initialize(@data : Bytes, password : String = "")
      @parser = Parser.new(@data)
      @parser.parse!

      @version = @parser.version
      @trailer = @parser.trailer
      @xref = @parser.xref
      @objects = {} of Int32 => Objects::Indirect
      @pages = [] of ReaderPage
      @next_object_number = 1

      # Détecter les PDFs chiffrés et tenter le déchiffrement.
      # Stratégie : essayer le `password` fourni (vide par défaut),
      # qui marche pour la plupart des PDFs « owner-only protected »
      # (cas le plus courant : restrictions de copie/édition mais
      # ouverture libre).
      #
      # Si le mot de passe est faux OU si l'algorithme n'est pas
      # encore supporté (V=4/V=5/AES), on lève `EncryptedPdfError`
      # pour que le caller puisse rediriger vers un contournement.
      if encrypt_obj = @trailer["Encrypt"]?
        setup_decryption(encrypt_obj, password)
      end

      # Calculer le prochain numéro d'objet disponible
      if size_obj = @trailer["Size"]?
        if num = size_obj.as?(Objects::Number)
          @next_object_number = num.to_i64.to_i32
        end
      end

      # Construire l'arbre des pages
      build_page_tree
    end

    # Configure le `security_handler` du parser après avoir validé
    # le mot de passe. Lève `EncryptedPdfError` si le mot de passe
    # ne convient pas ou si l'algorithme n'est pas supporté.
    private def setup_decryption(encrypt_obj : Objects::Base, password : String) : Nil
      dict = resolve_encrypt_dict(encrypt_obj)
      raise EncryptedPdfError.new("Dictionnaire /Encrypt introuvable ou mal formé") unless dict

      filter = dict["Filter"]?.try(&.as?(Objects::Name)).try(&.value) || "?"
      v = dict["V"]?.try(&.as?(Objects::Number)).try(&.to_i64).try(&.to_i32) || 0
      r = dict["R"]?.try(&.as?(Objects::Number)).try(&.to_i64).try(&.to_i32) || 0
      length = dict["Length"]?.try(&.as?(Objects::Number)).try(&.to_i64).try(&.to_i32) || 40

      # Filter doit être /Standard pour le Standard Security Handler
      unless filter == "Standard"
        raise EncryptedPdfError.new("Filter de sécurité '#{filter}' non supporté (uniquement /Standard)")
      end

      # V=1, 2, 4, 5 supportés. R=5 (transitoire) explicitement refusé.
      unless [1, 2, 4, 5].includes?(v)
        raise EncryptedPdfError.new(
          "Algorithme V=#{v}, R=#{r} non supporté. " \
          "Contournement : passer le PDF par `gs` ou `qpdf --decrypt`."
        )
      end
      if r == 5
        raise EncryptedPdfError.new(
          "PDF chiffré R=5 (transitoire ISO 32000-2 draft, déprécié) non supporté. " \
          "Contournement : `qpdf --decrypt` puis `qpdf --encrypt ... 256` (R=6)."
        )
      end

      # Déterminer le cipher effectif
      cipher = detect_cipher(dict, v)

      # Extraire /O, /U, /P et l'/ID
      o = bytes_from_string(dict["O"]?)
      u = bytes_from_string(dict["U"]?)
      p_value = dict["P"]?.try(&.as?(Objects::Number)).try(&.to_i64).try(&.to_i32) || 0
      id_first = first_id_bytes
      # /ID est optionnel en V=5 (le file_key ne dépend que des sels
      # /U et /O), mais obligatoire en V=1/2/4.
      if v < 5 && (o.empty? || u.empty? || id_first.empty?)
        raise EncryptedPdfError.new("/Encrypt incomplet (O, U ou ID manquant)")
      end
      if v == 5 && (o.empty? || u.empty?)
        raise EncryptedPdfError.new("/Encrypt incomplet (O ou U manquant)")
      end

      # /OE, /UE, /Perms et /EncryptMetadata pour V=5
      oe = bytes_from_string(dict["OE"]?)
      ue = bytes_from_string(dict["UE"]?)
      perms = bytes_from_string(dict["Perms"]?)
      encrypt_metadata = dict["EncryptMetadata"]?.try(&.as?(Objects::Boolean)).try(&.value)
      encrypt_metadata = true if encrypt_metadata.nil?

      # Pour V=5, /Length n'est pas significatif côté StandardSecurity
      # (forcé à 256). Pour V=4, /Length du dict global n'est pas
      # toujours présent, on prend celui du CryptFilter ou 128 par défaut.
      effective_length = case v
                         when 4 then 128
                         when 5 then 256
                         else        length
                         end

      ssh = Encryption::StandardSecurity.new(
        o: o, u: u, p: p_value, id: id_first,
        v: v, r: r, length: effective_length,
        cipher: cipher,
        oe: oe, ue: ue, perms: perms,
        encrypt_metadata: encrypt_metadata,
      )

      unless ssh.try_password(password)
        algo = describe_cipher(cipher, effective_length)
        raise EncryptedPdfError.new(
          "PDF chiffré (#{algo}, R=#{r}). Mot de passe utilisateur " \
          "invalide#{password.empty? ? " (vide essayé)" : ""}. " \
          "Fournissez le mot de passe via `Reader.open(path, password: \"...\")`."
        )
      end

      @parser.security_handler = ssh

      # Mémoriser le numéro d'objet du dict /Encrypt pour que le
      # parser ne tente PAS de déchiffrer les strings qu'il contient
      # (/O, /U, /OE, /UE, /Perms ne sont pas chiffrées par /Encrypt
      # — spec § 7.6.2).
      if (ref = encrypt_obj.as?(Objects::Reference))
        @parser.encrypt_object_number = ref.object_number
      end

      # IMPORTANT : invalider les caches d'objets déjà lus.
      # `parse!` a peut-être résolu certains objets (xref stream,
      # /Info) sans déchiffrement parce que le handler n'était pas
      # encore configuré. On force une re-résolution propre en
      # vidant le cache du parser et le notre.
      @parser.objects.clear
      @objects.clear
    end

    # Détermine le cipher effectif en lisant /CF/StdCF/CFM pour V=4.
    # V=1/V=2 → RC4 ; V=5 → AES-256 ; V=4 → AES-128 si CFM=AESV2,
    # sinon RC4 (CFM=V2).
    private def detect_cipher(dict : Objects::Dictionary, v : Int32) : Encryption::StandardSecurity::Cipher
      case v
      when 1, 2 then Encryption::StandardSecurity::Cipher::RC4
      when 5    then Encryption::StandardSecurity::Cipher::AES_256
      when 4
        cf = dict["CF"]?.try(&.as?(Objects::Dictionary))
        return Encryption::StandardSecurity::Cipher::RC4 unless cf
        # Le filtre par défaut pour les streams est nommé via /StmF
        stmf = dict["StmF"]?.try(&.as?(Objects::Name)).try(&.value) || "StdCF"
        std_cf = cf[stmf]?.try(&.as?(Objects::Dictionary))
        return Encryption::StandardSecurity::Cipher::RC4 unless std_cf
        cfm = std_cf["CFM"]?.try(&.as?(Objects::Name)).try(&.value)
        case cfm
        when "AESV2" then Encryption::StandardSecurity::Cipher::AES_128
        when "V2"    then Encryption::StandardSecurity::Cipher::RC4
        else
          raise EncryptedPdfError.new("CryptFilter CFM=#{cfm} non supporté")
        end
      else
        raise EncryptedPdfError.new("V=#{v} non supporté pour la détection de cipher")
      end
    end

    private def describe_cipher(cipher : Encryption::StandardSecurity::Cipher, length : Int32) : String
      case cipher
      in .rc4?     then "RC4 #{length}-bit"
      in .aes_128? then "AES-128"
      in .aes_256? then "AES-256"
      end
    end

    # Résout le dict `/Encrypt` (référence indirecte la plupart du
    # temps, dict en ligne possible). Retourne nil si introuvable.
    private def resolve_encrypt_dict(encrypt_obj : Objects::Base) : Objects::Dictionary?
      if (ref = encrypt_obj.as?(Objects::Reference)) && (off = @xref[ref.object_number]?)
        @parser.parse_object_at(off).value.as?(Objects::Dictionary)
      else
        encrypt_obj.as?(Objects::Dictionary)
      end
    end

    # Extrait les bytes d'un Objects::Str (forme littérale ou hex —
    # les deux sont stockées dans Str avec un drapeau `hex?`).
    private def bytes_from_string(obj : Objects::Base?) : Bytes
      case obj
      when Objects::Str then obj.value.to_slice
      else                   Bytes.empty
      end
    end

    # Récupère le premier élément de `/ID` du trailer, sous forme
    # de Bytes. Indispensable au calcul de la clé du fichier.
    private def first_id_bytes : Bytes
      arr = @trailer["ID"]?.try(&.as?(Objects::Array))
      return Bytes.empty unless arr
      first = arr[0]?
      bytes_from_string(first)
    end

    # Nombre de pages dans le document
    def page_count : Int32
      @pages.size
    end

    # Résout une référence ou retourne l'objet tel quel
    def resolve(obj : Objects::Base) : Objects::Base
      case obj
      when Objects::Reference
        resolve_reference(obj)
      else
        obj
      end
    end

    # Résout une référence indirecte vers son objet
    def resolve_reference(ref : Objects::Reference) : Objects::Base
      # Vérifier le cache
      if cached = @objects[ref.object_number]?
        return cached.value
      end

      # Analyser l'objet depuis le fichier
      if offset = @xref[ref.object_number]?
        indirect = @parser.parse_object_at(offset)
        @objects[ref.object_number] = indirect
        indirect.value
      elsif compressed = @parser.resolve_compressed_object(ref.object_number)
        # Objet stocké dans un object stream (PDF 1.5+).
        @objects[ref.object_number] = compressed
        compressed.value
      else
        Objects::Null.instance
      end
    end

    # Enregistre un nouvel objet indirect à émettre lors de la prochaine
    # mise à jour incrémentale (`write`/`save`). Alloue un numéro d'objet
    # libre et renvoie la référence à utiliser pour le pointer.
    def add_object(value : Objects::Base) : Objects::Reference
      obj_num = @next_object_number
      @next_object_number += 1
      indirect = Objects::Indirect.new(obj_num, 0, value)
      @added_objects << indirect
      @objects[obj_num] = indirect
      indirect.reference
    end

    # Marque un objet existant comme modifié : sa nouvelle valeur sera
    # ré-émise lors de la mise à jour incrémentale. Mettre à jour le
    # catalogue se fait en mutant `catalog` puis en appelant cette
    # méthode avec `catalog_reference.object_number`.
    def replace_object(object_number : Int32, value : Objects::Base) : Nil
      @modified_objects[object_number] = value
    end

    # Référence indirecte du catalogue (/Root).
    def catalog_reference : Objects::Reference
      root = @trailer["Root"]?
      raise "PDF sans /Root : catalogue introuvable" unless root
      ref = root.as?(Objects::Reference)
      raise "/Root n'est pas une référence indirecte" unless ref
      ref
    end

    # Dictionnaire du catalogue (/Root), résolu. Mutez-le puis appelez
    # `replace_object(catalog_reference.object_number, catalog)` pour
    # persister les changements à la prochaine écriture.
    def catalog : Objects::Dictionary
      resolved = resolve(catalog_reference)
      dict = resolved.as?(Objects::Dictionary)
      raise "Catalogue /Root illisible" unless dict
      dict
    end

    # Sauvegarde le PDF modifié dans un fichier (mise à jour incrémentale)
    def save(path : String) : Nil
      File.open(path, "wb") do |file|
        write(file)
      end
    end

    # Écrit le PDF modifié dans un flux IO (mise à jour incrémentale)
    def write(io : IO) : Nil
      # Écrire les données originales intactes
      io.write(@data)

      # Collecter les nouveaux objets et les objets modifiés
      new_objects = [] of Objects::Indirect
      modified = {} of Int32 => Objects::Base

      @pages.each do |page|
        next if page.added_streams.empty?

        # Créer un nouvel objet stream pour chaque contenu ajouté
        page.added_streams.each do |content|
          stream = Objects::Stream.new
          stream.data = content
          stream.add_filter(Filters::Flate.new)
          obj = Objects::Indirect.new(@next_object_number, 0, stream)
          new_objects << obj
          @next_object_number += 1

          # Mettre à jour le dictionnaire de page pour ajouter la référence
          update_page_contents(page, obj.reference)
        end

        modified[page.object_number] = page.page_dict
      end

      # Objets ajoutés via `add_object` (pièces jointes, etc.)
      new_objects.concat(@added_objects)

      # Objets existants modifiés via `replace_object` (ex. catalogue)
      @modified_objects.each { |num, value| modified[num] = value }

      return if new_objects.empty? && modified.empty?

      # Position de départ des nouveaux objets
      position = @data.size.to_i64
      new_offsets = {} of Int32 => Int64

      # Écrire les nouveaux objets
      new_objects.each do |obj|
        new_offsets[obj.object_number] = position
        content = obj.to_pdf + "\n"
        io << content
        position += content.bytesize
      end

      # Écrire les objets modifiés (pages, catalogue…)
      modified.each do |obj_num, value|
        new_offsets[obj_num] = position
        indirect = Objects::Indirect.new(obj_num, 0, value)
        content = indirect.to_pdf + "\n"
        io << content
        position += content.bytesize
      end

      # Écrire la table xref incrémentale
      xref_start = position
      io << "xref\n"

      # Écrire chaque entrée individuellement (pas forcément contiguës)
      new_offsets.keys.sort.each do |obj_num|
        io << "#{obj_num} 1\n"
        offset = new_offsets[obj_num]
        io << offset.to_s.rjust(10, '0')
        io << " 00000 n \n"
      end

      # Écrire le nouveau trailer
      io << "trailer\n"
      io << "<<"
      io << "/Size #{@next_object_number}"

      # Référence /Root
      if root = @trailer["Root"]?
        io << "/Root "
        root.to_pdf(io)
      end

      # Référence /Info
      if info = @trailer["Info"]?
        io << "/Info "
        info.to_pdf(io)
      end

      # Référence vers l'ancienne table xref
      old_xref_offset = @parser.find_xref_offset
      io << "/Prev #{old_xref_offset}"

      io << ">>\n"
      io << "startxref\n"
      io << xref_start
      io << "\n%%EOF\n"
    end

    # Construit l'arbre des pages depuis le catalogue
    private def build_page_tree : Nil
      root_ref = @trailer["Root"]?
      return unless root_ref

      catalog = resolve(root_ref)
      return unless catalog.is_a?(Objects::Dictionary)

      pages_ref = catalog["Pages"]?
      return unless pages_ref

      pages_obj_num = 0
      if ref = pages_ref.as?(Objects::Reference)
        pages_obj_num = ref.object_number
      end

      pages_obj = resolve(pages_ref)
      return unless pages_obj.is_a?(Objects::Dictionary)

      collect_pages(pages_obj, pages_obj_num)
    end

    # Parcourt récursivement l'arbre /Pages pour collecter les feuilles
    private def collect_pages(node : Objects::Dictionary, node_obj_num : Int32 = 0) : Nil
      type = node["Type"]?
      type = resolve(type) if type

      if type.is_a?(Objects::Name) && type.value == "Page"
        # C'est une page feuille
        @pages << ReaderPage.new(self, node, node_obj_num)
        return
      end

      # C'est un nœud intermédiaire /Pages, parcourir /Kids
      kids = node["Kids"]?
      return unless kids

      kids = resolve(kids)
      return unless kids.is_a?(Objects::Array)

      kids.each do |kid|
        # Extraire le numéro d'objet depuis la référence
        kid_obj_num = 0
        if ref = kid.as?(Objects::Reference)
          kid_obj_num = ref.object_number
        end
        kid_obj = resolve(kid)
        if kid_dict = kid_obj.as?(Objects::Dictionary)
          collect_pages(kid_dict, kid_obj_num)
        end
      end
    end

    # Met à jour /Contents d'une page pour inclure un nouveau stream
    private def update_page_contents(page : ReaderPage, new_ref : Objects::Reference) : Nil
      contents = page.page_dict["Contents"]?

      case contents
      when Objects::Reference
        # Transformer en tableau [ancienne_ref, nouvelle_ref]
        arr = Objects::Array.new
        arr << contents
        arr << new_ref
        page.page_dict["Contents"] = arr
      when Objects::Array
        # Ajouter au tableau existant
        contents << new_ref
      else
        # Pas de contenu existant, créer une référence simple
        page.page_dict["Contents"] = new_ref
      end
    end
  end

  # Levée par `Reader.open` quand le PDF est chiffré (RC4 ou AES).
  # Les flux ne peuvent pas être lus tant qu'ils ne sont pas déchiffrés ;
  # tenter de Flate-décoder des octets chiffrés produit un cryptique
  # `Compress::Zlib::Error: Invalid header`.
  #
  # Cas typique : « owner-only protection » — mot de passe utilisateur
  # vide, mais permissions restreintes. Tout viewer ouvre le fichier
  # sans demander, ce qui crée la fausse impression que le PDF n'est
  # pas chiffré (`pdfinfo` peut afficher `Encrypted: no` alors que le
  # trailer contient bien `/Encrypt`).
  #
  # Contournement utilisateur : passer le PDF par `ghostscript` ou
  # `qpdf --decrypt` pour produire une copie non chiffrée que ce
  # shard saura lire.
  class EncryptedPdfError < Exception
  end
end
