require "digest/md5"
require "./rc4"

module PDF
  module Encryption
    # Standard Security Handler — algorithme de dérivation de clé et
    # de déchiffrement défini par le PDF Reference (ISO 32000-1
    # § 7.6.3, "Standard Security Handler").
    #
    # Couvre les niveaux V=1/V=2 (RC4 40-128 bit) et expose une
    # API unifiée. AES (V=4 R=4 et V=5 R=5/6) sera ajouté
    # dans une révision ultérieure.
    #
    # Usage typique :
    #
    # ```
    # ssh = PDF::Encryption::StandardSecurity.new(
    #   o: o_bytes, u: u_bytes,
    #   p: -1324, id: id_bytes, v: 2, r: 3, length: 128,
    # )
    # raise "wrong password" unless ssh.try_password("")
    # decrypted = ssh.decrypt_object(stream_bytes, obj_num: 2, gen: 0)
    # ```
    class StandardSecurity
      # « Padding string » du PDF spec § 7.6.3.3 — 32 octets exacts.
      # Sert à produire une clé déterministe à partir d'un mot de
      # passe utilisateur de longueur arbitraire (vide compris).
      PADDING = Bytes[
        0x28_u8, 0xBF_u8, 0x4E_u8, 0x5E_u8, 0x4E_u8, 0x75_u8, 0x8A_u8, 0x41_u8,
        0x64_u8, 0x00_u8, 0x4E_u8, 0x56_u8, 0xFF_u8, 0xFA_u8, 0x01_u8, 0x08_u8,
        0x2E_u8, 0x2E_u8, 0x00_u8, 0xB6_u8, 0xD0_u8, 0x68_u8, 0x3E_u8, 0x80_u8,
        0x2F_u8, 0x0C_u8, 0xA9_u8, 0xFE_u8, 0x64_u8, 0x53_u8, 0x69_u8, 0x7A_u8,
      ]

      # Champs du dictionnaire `/Encrypt`.
      getter o : Bytes      # Owner password hash
      getter u : Bytes      # User password hash
      getter p : Int32      # Permissions (signed)
      getter id : Bytes     # First element of /ID array (file identifier)
      getter v : Int32      # Algorithm version (1, 2, 4, 5)
      getter r : Int32      # Revision (2, 3, 4, 5, 6)
      getter length : Int32 # Key length in bits

      # Calculé après try_password, sinon nil.
      getter file_key : Bytes?

      # `length` est en bits ; doit être un multiple de 8 entre 40 et
      # 128 pour V=1/2. Pour V=2 R=3 sans `/Length` explicite, le
      # défaut PDF est 40 bits.
      def initialize(
        @o : Bytes, @u : Bytes, @p : Int32, @id : Bytes,
        @v : Int32, @r : Int32, @length : Int32,
      )
        unless [1, 2].includes?(@v)
          raise ArgumentError.new("Standard Security V=#{@v} non supportée (uniquement V=1, V=2 pour cette version)")
        end
        unless [2, 3].includes?(@r)
          raise ArgumentError.new("Standard Security R=#{@r} non supportée (uniquement R=2, R=3 pour cette version)")
        end
        unless @length >= 40 && @length <= 128 && @length % 8 == 0
          raise ArgumentError.new("Longueur de clé invalide : #{@length} bits (attendu 40..128, multiple de 8)")
        end
      end

      # Tente le mot de passe. Retourne `true` si la clé dérivée
      # passe le check du `/U` ; `false` sinon (mot de passe faux).
      # En cas de succès, `file_key` est défini.
      def try_password(password : String) : Bool
        key = compute_file_key(password)
        return false unless validate_user_password(key)
        @file_key = key
        true
      end

      # Déchiffre le contenu d'un objet (stream ou string) avec la
      # clé par-objet calculée selon § 7.6.2.
      #
      # Algorithm 1 du spec PDF : per_object_key = first n+5 bytes
      # of MD5(file_key || obj_low_3_bytes || gen_low_2_bytes).
      def decrypt_object(data : Bytes, obj_num : Int32, gen : Int32) : Bytes
        key = @file_key
        raise "file_key pas calculée — appelez try_password d'abord" unless key
        per_obj_key = per_object_key(key, obj_num, gen)
        RC4.apply(per_obj_key, data)
      end

      # Calcule la clé par-objet selon l'Algorithm 1 du spec.
      private def per_object_key(file_key : Bytes, obj_num : Int32, gen : Int32) : Bytes
        # Construire input : file_key + 3 bytes obj_num LE + 2 bytes gen LE
        input = IO::Memory.new(file_key.size + 5)
        input.write(file_key)
        input.write_byte((obj_num & 0xff).to_u8)
        input.write_byte(((obj_num >> 8) & 0xff).to_u8)
        input.write_byte(((obj_num >> 16) & 0xff).to_u8)
        input.write_byte((gen & 0xff).to_u8)
        input.write_byte(((gen >> 8) & 0xff).to_u8)
        hash = ::Digest::MD5.digest(input.to_slice)
        # n+5 bytes, plafonné à 16 (taille MD5)
        out_size = {file_key.size + 5, 16}.min
        hash[0, out_size]
      end

      # Algorithm 2 du spec § 7.6.3.3 — calcul de la clé du fichier
      # à partir du mot de passe.
      private def compute_file_key(password : String) : Bytes
        # 1. Padded password (32 bytes)
        padded = pad_password(password)
        # 2. Concaténer : padded || /O || /P (4 bytes LE) || /ID
        ctx = IO::Memory.new
        ctx.write(padded)
        ctx.write(@o)
        ctx.write_byte((@p & 0xff).to_u8)
        ctx.write_byte(((@p >> 8) & 0xff).to_u8)
        ctx.write_byte(((@p >> 16) & 0xff).to_u8)
        ctx.write_byte(((@p >> 24) & 0xff).to_u8)
        ctx.write(@id)
        # NOTE : pas de /EncryptMetadata géré ici (PDF 1.5+, R≥4) ;
        # ce shard ne traite que R=2/R=3 pour l'instant.
        hash = ::Digest::MD5.digest(ctx.to_slice)

        # 3. Pour R≥3, 50 itérations de MD5(hash[0, n])
        n_bytes = @length // 8
        if @r >= 3
          50.times do
            hash = ::Digest::MD5.digest(hash[0, n_bytes])
          end
        end

        hash[0, n_bytes]
      end

      # Pad/truncate le mot de passe à exactement 32 bytes selon le
      # spec § 7.6.3.3. Si plus court que 32 bytes, complète avec
      # `PADDING` ; si plus long, tronque à 32.
      private def pad_password(password : String) : Bytes
        pwd_bytes = password.to_slice
        out = Bytes.new(32)
        n = {pwd_bytes.size, 32}.min
        n.times { |i| out[i] = pwd_bytes[i] }
        # Complète avec PADDING si reste de la place
        (n...32).each { |i| out[i] = PADDING[i - n] }
        out
      end

      # Vérifie que la clé calculée déchiffre correctement `/U`.
      # Algorithm 5 (R=3) ou Algorithm 4 (R=2) du spec § 7.6.3.4.
      private def validate_user_password(file_key : Bytes) : Bool
        case @r
        when 2
          # R=2 : RC4(file_key, PADDING) doit donner /U.
          expected = RC4.apply(file_key, PADDING)
          @u[0, 32] == expected
        when 3
          # R=3 :
          #   1. MD5(PADDING || /ID)
          #   2. RC4(file_key, hash) — appelé hash_2
          #   3. 19 itérations : RC4(file_key XOR i, hash_n)
          #   4. Comparer les 16 premiers bytes au /U[0,16]
          ctx = IO::Memory.new
          ctx.write(PADDING)
          ctx.write(@id)
          hash = ::Digest::MD5.digest(ctx.to_slice)
          result = RC4.apply(file_key, hash)
          (1..19).each do |i|
            xor_key = Bytes.new(file_key.size) { |k| (file_key[k] ^ i.to_u8).to_u8 }
            result = RC4.apply(xor_key, result)
          end
          # Comparer les 16 premiers bytes
          @u[0, 16] == result[0, 16]
        else
          false
        end
      end
    end
  end
end
