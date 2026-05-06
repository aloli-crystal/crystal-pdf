module PDF
  module Writer
    # Writes a complete PDF document to an IO.
    #
    # The writer handles:
    # - PDF header and version
    # - Binary marker (for proper binary handling)
    # - All indirect objects
    # - Cross-reference table
    # - Trailer dictionary
    # - EOF marker
    # - Encryption (when configured via `Document#encrypt`)
    class DocumentWriter
      # The document being written
      getter document : Document

      # Object byte offsets for xref table
      @offsets : Hash(Int32, Int64)

      def initialize(@document : Document)
        @offsets = {} of Int32 => Int64
      end

      # Writes the complete PDF to the given IO.
      def write(io : IO) : Nil
        # Finalize the document (creates all objects)
        @document.finalize!

        # Register info dictionary BEFORE writing objects so it's in the xref
        info_ref = if info = @document.info_dict
                     @document.register_object(info).reference
                   end

        # Si chiffrement activé, enregistrer le dict /Encrypt et
        # chiffrer les objets AVANT sérialisation.
        encrypt_obj_num = nil
        if handler = @document.security_handler
          enc_dict = handler.to_encrypt_dict
          enc_obj = @document.register_object(enc_dict)
          encrypt_obj_num = enc_obj.object_number
          encrypt_objects(handler, encrypt_obj_num)
        end

        # Track current position
        position = 0_i64

        # Write header
        header = write_header
        io << header
        position += header.bytesize

        # Write all objects
        @document.objects.each do |obj|
          @offsets[obj.object_number] = position
          content = obj.to_pdf + "\n"
          io << content
          position += content.bytesize
        end

        # Write xref table
        xref_start = position
        xref = write_xref
        io << xref
        position += xref.bytesize

        # Write trailer
        trailer = write_trailer(xref_start, info_ref, encrypt_obj_num)
        io << trailer
      end

      # Chiffre tous les streams et toutes les strings indirectes
      # (sauf le dict /Encrypt lui-même) avec le handler fourni.
      private def encrypt_objects(
        handler : Encryption::StandardSecurity,
        encrypt_obj_num : Int32,
      ) : Nil
        @document.objects.each do |indirect|
          next if indirect.object_number == encrypt_obj_num
          encrypt_in_place(
            indirect.value,
            indirect.object_number,
            indirect.generation,
            handler,
          )
        end
      end

      # Marche récursivement le sous-arbre d'un objet indirect et
      # chiffre les `Stream` et `Str` rencontrés. Pour les streams,
      # on chiffre les octets ENCODÉS (post-Filter Flate) puisque le
      # spec applique le crypt filter au-dessus des autres filtres.
      private def encrypt_in_place(
        obj : Objects::Base,
        obj_num : Int32,
        gen : Int32,
        handler : Encryption::StandardSecurity,
      ) : Nil
        case obj
        when Objects::Stream
          encrypt_stream(obj, obj_num, gen, handler)
        when Objects::Str
          encrypt_string(obj, obj_num, gen, handler)
        when Objects::Dictionary
          obj.values.each { |v| encrypt_in_place(v, obj_num, gen, handler) }
        when Objects::Array
          obj.each { |v| encrypt_in_place(v, obj_num, gen, handler) }
        end
      end

      private def encrypt_stream(
        stream : Objects::Stream,
        obj_num : Int32,
        gen : Int32,
        handler : Encryption::StandardSecurity,
      ) : Nil
        # Récupérer les octets encodés (Flate appliqué) AVANT chiffrement.
        encoded = stream.encoded_data
        encrypted = handler.encrypt_object(encoded, obj_num, gen)
        # Remplacer les octets et neutraliser les filtres : `to_pdf`
        # ne les ré-encodera pas. Le Filter du dict reste tel quel —
        # c'est ce que le LECTEUR appliquera APRÈS déchiffrement.
        stream.replace_encoded!(encrypted)
        stream.dictionary[Objects::Name::LENGTH] = Objects::Number.new(encrypted.size)
      end

      private def encrypt_string(
        str : Objects::Str,
        obj_num : Int32,
        gen : Int32,
        handler : Encryption::StandardSecurity,
      ) : Nil
        encrypted = handler.encrypt_object(str.value.to_slice, obj_num, gen)
        str.value = String.new(encrypted)
        # Forcer la sérialisation hex pour la sûreté binaire
        # (les bytes chiffrés peuvent contenir des octets non-printable
        # ou des `(` `)` qui casseraient une string littérale).
        str.hex = true
      end

      private def write_header : String
        # PDF header with version
        # Second line contains high-bit bytes to mark as binary
        "%PDF-#{PDF::PDF_VERSION}\n%\xE2\xE3\xCF\xD3\n"
      end

      private def write_xref : String
        String.build do |io|
          io << "xref\n"

          # We include object 0 (free entry) plus all our objects
          total_objects = @document.objects.size + 1
          io << "0 #{total_objects}\n"

          # Object 0 is always free with generation 65535
          io << "0000000000 65535 f \n"

          # Write entry for each object in order
          (1...total_objects).each do |obj_num|
            offset = @offsets[obj_num]? || 0_i64
            io << offset.to_s.rjust(10, '0')
            io << " 00000 n \n"
          end
        end
      end

      private def write_trailer(
        xref_start : Int64,
        info_ref : Objects::Reference?,
        encrypt_obj_num : Int32?,
      ) : String
        String.build do |io|
          io << "trailer\n"
          io << "<<"
          io << "/Size #{@document.objects.size + 1}"
          io << "/Root #{@document.catalog.reference.to_pdf}"

          if ref = info_ref
            io << "/Info #{ref.to_pdf}"
          end

          if num = encrypt_obj_num
            io << "/Encrypt #{num} 0 R"
          end

          # /ID est obligatoire si /Encrypt est présent (PDF 1.4+) et
          # recommandé sinon. Deux éléments identiques (création +
          # dernière modif) suffisent pour un nouveau document.
          if @document.security_handler || @document.has_file_id?
            id_hex = bytes_to_hex(@document.file_id)
            io << "/ID [<" << id_hex << "><" << id_hex << ">]"
          end

          io << ">>\n"
          io << "startxref\n"
          io << xref_start
          io << "\n%%EOF\n"
        end
      end

      private def bytes_to_hex(bytes : Bytes) : String
        String.build do |sb|
          bytes.each { |b| sb << b.to_s(16, upcase: true).rjust(2, '0') }
        end
      end
    end
  end
end
