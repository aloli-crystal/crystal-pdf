require "digest/md5"
require "openssl/digest"
require "./rc4"
require "./aes"

module PDF
  module Encryption
    # Standard Security Handler — algorithme de dérivation de clé et
    # de déchiffrement défini par le PDF Reference (ISO 32000-1
    # § 7.6.3 et ISO 32000-2 § 7.6.4 pour V=5).
    #
    # Couvre :
    # * V=1, R=2 — RC4 40-bit (PDF 1.1)
    # * V=2, R=3 — RC4 40 à 128-bit (PDF 1.4)
    # * V=4, R=4 — AES-128 ou RC4 128 selon le CryptFilter (PDF 1.5)
    # * V=5, R=6 — AES-256 (PDF 2.0, Acrobat ≥ X)
    #
    # R=5 (transitoire, déprécié par Adobe avant publication d'ISO
    # 32000-2) **n'est pas** supporté — utiliser R=6.
    #
    # Usage typique :
    #
    # ```
    # ssh = PDF::Encryption::StandardSecurity.new(
    #   o: o_bytes, u: u_bytes,
    #   p: -1324, id: id_bytes, v: 4, r: 4, length: 128,
    #   cipher: PDF::Encryption::StandardSecurity::Cipher::AES_128,
    # )
    # raise "wrong password" unless ssh.try_password("")
    # decrypted = ssh.decrypt_object(stream_bytes, obj_num: 2, gen: 0)
    # ```
    class StandardSecurity
      # Algorithme de chiffrement effectif (déduit de V/R/CryptFilter).
      enum Cipher
        RC4
        AES_128
        AES_256
      end

      # Niveau de chiffrement choisi à l'ÉCRITURE (API publique
      # `Document#encrypt`). Mappe vers V/R/Cipher en interne.
      #
      # * `RC4_128` : V=2, R=3, RC4 128-bit. Compatible Acrobat ≥ 5
      #   (1999) mais cryptographiquement faible. Évitez sauf pour
      #   compatibilité legacy.
      # * `AES_128` : V=4, R=4, AES-128-CBC + CryptFilter AESV2.
      #   Compatible Acrobat ≥ 7 (2005). Bon compromis.
      # * `AES_256` : V=5, R=6, AES-256-CBC. PDF 2.0 / Acrobat ≥ X
      #   (2012). À privilégier pour les nouveaux documents.
      enum Level
        RC4_128
        AES_128
        AES_256
      end

      # « Padding string » du PDF spec § 7.6.3.3 — 32 octets exacts.
      # Sert à produire une clé déterministe à partir d'un mot de
      # passe utilisateur de longueur arbitraire (vide compris).
      PADDING = Bytes[
        0x28_u8, 0xBF_u8, 0x4E_u8, 0x5E_u8, 0x4E_u8, 0x75_u8, 0x8A_u8, 0x41_u8,
        0x64_u8, 0x00_u8, 0x4E_u8, 0x56_u8, 0xFF_u8, 0xFA_u8, 0x01_u8, 0x08_u8,
        0x2E_u8, 0x2E_u8, 0x00_u8, 0xB6_u8, 0xD0_u8, 0x68_u8, 0x3E_u8, 0x80_u8,
        0x2F_u8, 0x0C_u8, 0xA9_u8, 0xFE_u8, 0x64_u8, 0x53_u8, 0x69_u8, 0x7A_u8,
      ]

      # Suffixe « sAlT » ajouté avant le MD5 par-objet quand le
      # CryptFilter est AESV2 (V=4, AES-128). Spec § 7.6.2 (PDF 1.7).
      SALT_AES = Bytes[0x73_u8, 0x41_u8, 0x6c_u8, 0x54_u8]

      # Champs du dictionnaire `/Encrypt`.
      getter o : Bytes      # Owner password hash (32 bytes pour V≤4, 48 pour V=5)
      getter u : Bytes      # User password hash  (32 bytes pour V≤4, 48 pour V=5)
      getter p : Int32      # Permissions (signed)
      getter id : Bytes     # First element of /ID array (file identifier)
      getter v : Int32      # Algorithm version (1, 2, 4, 5)
      getter r : Int32      # Revision (2, 3, 4, 6)
      getter length : Int32 # Key length in bits

      # Champs spécifiques à V=5 (R=6).
      getter oe : Bytes              # Owner-Encrypted file key (32 bytes)
      getter ue : Bytes              # User-Encrypted file key (32 bytes)
      getter perms : Bytes           # Encrypted permissions block (16 bytes)
      getter encrypt_metadata : Bool # /EncryptMetadata (PDF 1.5+)

      # Algorithme de chiffrement résolu après inspection du
      # CryptFilter (V=4) ou direct (V=1/2 = RC4, V=5 = AES-256).
      getter cipher : Cipher

      # Calculé après try_password, sinon nil.
      getter file_key : Bytes?

      # `length` est en bits ; doit être un multiple de 8 entre 40 et
      # 128 pour V=1/2/4. Pour V=5 c'est forcément 256.
      def initialize(
        @o : Bytes, @u : Bytes, @p : Int32, @id : Bytes,
        @v : Int32, @r : Int32, @length : Int32,
        @cipher : Cipher = Cipher::RC4,
        @oe : Bytes = Bytes.empty,
        @ue : Bytes = Bytes.empty,
        @perms : Bytes = Bytes.empty,
        @encrypt_metadata : Bool = true,
      )
        unless [1, 2, 4, 5].includes?(@v)
          raise ArgumentError.new("Standard Security V=#{@v} non supportée (uniquement V=1, 2, 4, 5)")
        end
        unless [2, 3, 4, 6].includes?(@r)
          if @r == 5
            raise ArgumentError.new("Standard Security R=5 (transitoire ISO 32000-2 draft, déprécié par Adobe) non supporté — utiliser R=6.")
          end
          raise ArgumentError.new("Standard Security R=#{@r} non supportée (uniquement R=2, 3, 4, 6)")
        end

        case @v
        when 1
          @length = 40 # V=1 forcé à 40 bits
        when 2, 4
          unless @length >= 40 && @length <= 128 && @length % 8 == 0
            raise ArgumentError.new("Longueur de clé invalide : #{@length} bits (attendu 40..128, multiple de 8)")
          end
        when 5
          @length = 256
          # /OE, /UE et /Perms sont obligatoires en V=5.
          if @oe.size != 32 || @ue.size != 32
            raise ArgumentError.new("V=5 requiert /OE et /UE de 32 octets (#{@oe.size}/#{@ue.size} reçus)")
          end
        end
      end

      # Tente le mot de passe. Retourne `true` si la clé dérivée
      # passe le check du `/U` ou du `/O` (mot de passe owner) ;
      # `false` sinon (mot de passe faux).
      # En cas de succès, `file_key` est défini.
      def try_password(password : String) : Bool
        if @v == 5
          try_password_v5(password)
        else
          # 1. Tenter le mot de passe utilisateur
          key = compute_file_key(password)
          if validate_user_password(key)
            @file_key = key
            return true
          end
          # 2. Tenter le mot de passe owner (Algorithm 7)
          try_password_owner_legacy(password)
        end
      end

      # Déchiffre le contenu d'un objet (stream ou string) avec la
      # clé par-objet calculée selon § 7.6.2.
      def decrypt_object(data : Bytes, obj_num : Int32, gen : Int32) : Bytes
        key = @file_key
        raise "file_key pas calculée — appelez try_password d'abord" unless key

        case @cipher
        in .rc4?
          per_obj = per_object_key(key, obj_num, gen, with_salt: false)
          RC4.apply(per_obj, data)
        in .aes_128?
          per_obj = per_object_key(key, obj_num, gen, with_salt: true)
          AES.decrypt(per_obj, data)
        in .aes_256?
          # V=5 : pas de dérivation par-objet, on utilise file_key
          # directement (32 octets).
          AES.decrypt(key, data)
        end
      end

      # Chiffre le contenu d'un objet (stream ou string) avec la
      # clé par-objet — opération symétrique de `decrypt_object`.
      # Utilisé par le writer quand le document a `pdf.encrypt(...)`.
      def encrypt_object(data : Bytes, obj_num : Int32, gen : Int32) : Bytes
        key = @file_key
        raise "file_key pas calculée" unless key

        case @cipher
        in .rc4?
          per_obj = per_object_key(key, obj_num, gen, with_salt: false)
          RC4.apply(per_obj, data) # RC4 est symétrique
        in .aes_128?
          per_obj = per_object_key(key, obj_num, gen, with_salt: true)
          AES.encrypt(per_obj, data)
        in .aes_256?
          AES.encrypt(key, data)
        end
      end

      # Calcule la clé par-objet selon l'Algorithm 1 du spec.
      # Pour AES (CryptFilter AESV2), append `sAlT` avant le MD5.
      private def per_object_key(file_key : Bytes, obj_num : Int32, gen : Int32, with_salt : Bool) : Bytes
        suffix_size = with_salt ? SALT_AES.size : 0
        input = IO::Memory.new(file_key.size + 5 + suffix_size)
        input.write(file_key)
        input.write_byte((obj_num & 0xff).to_u8)
        input.write_byte(((obj_num >> 8) & 0xff).to_u8)
        input.write_byte(((obj_num >> 16) & 0xff).to_u8)
        input.write_byte((gen & 0xff).to_u8)
        input.write_byte(((gen >> 8) & 0xff).to_u8)
        input.write(SALT_AES) if with_salt
        hash = ::Digest::MD5.digest(input.to_slice)
        # n+5 bytes, plafonné à 16 (taille MD5)
        out_size = {file_key.size + 5, 16}.min
        hash[0, out_size]
      end

      # Algorithm 2 du spec § 7.6.3.3 — calcul de la clé du fichier
      # à partir du mot de passe (V=1/2/4).
      private def compute_file_key(password : String) : Bytes
        compute_file_key_from_padded(pad_password(password))
      end

      # Variante de `compute_file_key` prenant un mot de passe DÉJÀ
      # padded à 32 bytes — utilisé par Algorithm 7 quand on a
      # déchiffré /O et que le résultat est déjà au format attendu.
      private def compute_file_key_from_padded(padded : Bytes) : Bytes
        # 2. Concaténer : padded || /O || /P (4 bytes LE) || /ID
        ctx = IO::Memory.new
        ctx.write(padded)
        ctx.write(@o)
        ctx.write_byte((@p & 0xff).to_u8)
        ctx.write_byte(((@p >> 8) & 0xff).to_u8)
        ctx.write_byte(((@p >> 16) & 0xff).to_u8)
        ctx.write_byte(((@p >> 24) & 0xff).to_u8)
        ctx.write(@id)
        # 2b. Si R≥4 et /EncryptMetadata = false, ajouter 0xFFFFFFFF.
        if @r >= 4 && !@encrypt_metadata
          4.times { ctx.write_byte(0xff_u8) }
        end
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

      # Algorithm 7 du spec § 7.6.3.4 — authentification via le mot
      # de passe owner (V=1/2/4, R=2/3/4).
      #
      # Étapes :
      #   1. Padded owner password → MD5
      #   2. R≥3 : 50 itérations de MD5
      #   3. RC4-déchiffrer /O avec la clé obtenue
      #      - R=2 : un round
      #      - R≥3 : 20 rounds (i de 19 à 0, key XOR i)
      #   4. Le résultat est le mot de passe utilisateur (déjà padded)
      #   5. Authentifier ce padded user password (Algorithm 6)
      private def try_password_owner_legacy(password : String) : Bool
        owner_pad = pad_password(password)
        hash = ::Digest::MD5.digest(owner_pad)
        n_bytes = @length // 8
        if @r >= 3
          50.times { hash = ::Digest::MD5.digest(hash[0, n_bytes]) }
        end
        rc4_key = hash[0, n_bytes]

        # Décrypter /O pour obtenir le padded user password
        purported_user_pad =
          if @r == 2
            RC4.apply(rc4_key, @o)
          else
            # 20 rounds en sens inverse : i = 19, 18, …, 0
            result = @o.dup
            19.downto(0) do |i|
              xor_key = Bytes.new(rc4_key.size) { |k| (rc4_key[k] ^ i.to_u8).to_u8 }
              result = RC4.apply(xor_key, result)
            end
            result
          end

        # Authentifier comme mot de passe utilisateur. Le résultat
        # est déjà un padded password (32 bytes), on le passe direct
        # à `compute_file_key_from_padded`.
        padded_32 = purported_user_pad[0, 32]
        key = compute_file_key_from_padded(padded_32)
        if validate_user_password(key)
          @file_key = key
          return true
        end
        false
      end

      # Vérifie que la clé calculée déchiffre correctement `/U`.
      # Algorithm 5 (R=3, R=4) ou Algorithm 4 (R=2) du spec § 7.6.3.4.
      # NOTE : R=4 utilise la même validation que R=3 ; la différence
      # entre R=3 et R=4 est uniquement dans /EncryptMetadata et le
      # CryptFilter, pas dans la dérivation de /U.
      private def validate_user_password(file_key : Bytes) : Bool
        case @r
        when 2
          expected = RC4.apply(file_key, PADDING)
          @u[0, 32] == expected
        when 3, 4
          ctx = IO::Memory.new
          ctx.write(PADDING)
          ctx.write(@id)
          hash = ::Digest::MD5.digest(ctx.to_slice)
          result = RC4.apply(file_key, hash)
          (1..19).each do |i|
            xor_key = Bytes.new(file_key.size) { |k| (file_key[k] ^ i.to_u8).to_u8 }
            result = RC4.apply(xor_key, result)
          end
          @u[0, 16] == result[0, 16]
        else
          false
        end
      end

      # ----------------------------------------------------------------
      # V=5 (AES-256, R=6) — ISO 32000-2 § 7.6.4
      # ----------------------------------------------------------------

      # /U (V=5) = 48 octets : Hash (32) || ValidationSalt (8) || KeySalt (8)
      private def u_hash : Bytes
        @u[0, 32]
      end

      private def u_validation_salt : Bytes
        @u[32, 8]
      end

      private def u_key_salt : Bytes
        @u[40, 8]
      end

      # /O (V=5) = 48 octets : Hash (32) || ValidationSalt (8) || KeySalt (8)
      private def o_hash : Bytes
        @o[0, 32]
      end

      private def o_validation_salt : Bytes
        @o[32, 8]
      end

      private def o_key_salt : Bytes
        @o[40, 8]
      end

      # Tente le mot de passe en V=5 (R=6). Algorithme :
      # 1. Calculer le hash du mot de passe utilisateur avec
      #    ValidationSalt (8 octets) ; comparer aux 32 premiers
      #    octets de /U.
      # 2. Si OK, recalculer avec KeySalt → intermediate_key.
      # 3. file_key = AES-256-CBC-decrypt(/UE, key=intermediate_key,
      #    iv=0, pas de padding) → 32 octets.
      # 4. Pareil pour /O / /OE si on essaye le mot de passe owner.
      private def try_password_v5(password : String) : Bool
        pwd_bytes = password.to_slice
        # 96 octets max (Saslprep est censé être appliqué — UTF-8
        # tronqué à 127 octets pour la simplicité ; à raffiner).
        pwd_bytes = pwd_bytes[0, 127] if pwd_bytes.size > 127

        # 1. Tenter user
        if try_password_v5_user(pwd_bytes)
          return true
        end
        # 2. Tenter owner
        if try_password_v5_owner(pwd_bytes)
          return true
        end
        false
      end

      private def try_password_v5_user(password : Bytes) : Bool
        hash = compute_hash_r6(password, u_validation_salt, Bytes.empty)
        return false unless hash == u_hash

        intermediate = compute_hash_r6(password, u_key_salt, Bytes.empty)
        iv_zero = Bytes.new(16, 0_u8)
        key = AES.decrypt_no_iv(intermediate, @ue, iv_zero, padding: false)
        return false unless validate_perms_v5(key)
        @file_key = key
        true
      end

      private def try_password_v5_owner(password : Bytes) : Bool
        # Pour valider le mot de passe owner, on hash : password ||
        # OwnerValidationSalt || /U[0, 48].
        additional = @u[0, {@u.size, 48}.min]
        hash = compute_hash_r6(password, o_validation_salt, additional)
        return false unless hash == o_hash

        intermediate = compute_hash_r6(password, o_key_salt, additional)
        iv_zero = Bytes.new(16, 0_u8)
        key = AES.decrypt_no_iv(intermediate, @oe, iv_zero, padding: false)
        return false unless validate_perms_v5(key)
        @file_key = key
        true
      end

      # Algorithm 13 du spec ISO 32000-2 § 7.6.4.4.10 — vérifie le
      # bloc /Perms après dérivation de la clé du fichier.
      #
      # Décrypte les 16 octets de /Perms en AES-256-ECB (équivalent
      # à CBC IV=0 sur un seul bloc) avec `file_key`, puis vérifie :
      #   - bytes 0..3   : /P en little-endian (sécurité belt-and-suspenders ;
      #                    si différent, /P a été altéré → on log mais ne fail
      #                    pas, le spec dit de privilégier /Perms sur /P)
      #   - bytes 4..7   : 0xFFFFFFFF (marqueur)
      #   - byte 8       : 'T' si /EncryptMetadata, 'F' sinon
      #   - bytes 9..11  : "adb" (signature Adobe)
      #   - bytes 12..15 : aléatoire (non vérifié)
      #
      # Si la signature "adb" est absente, c'est que la clé est
      # fausse → le mot de passe ne convient pas.
      #
      # Optionnel pour la rétrocompatibilité : si /Perms est vide ou
      # de taille incorrecte, on saute la vérif.
      private def validate_perms_v5(file_key : Bytes) : Bool
        return true if @perms.size != 16

        iv_zero = Bytes.new(16, 0_u8)
        decrypted = AES.decrypt_no_iv(file_key, @perms, iv_zero, padding: false)

        # Signature "adb" sur les bytes 9..11 — la seule vérif vraiment
        # fiable. Si elle passe, la clé est bonne.
        return false unless decrypted[9] == 'a'.ord.to_u8
        return false unless decrypted[10] == 'd'.ord.to_u8
        return false unless decrypted[11] == 'b'.ord.to_u8

        # Marqueur 0xFFFFFFFF (bytes 4..7) — supplémentaire.
        return false unless decrypted[4] == 0xff_u8 &&
                            decrypted[5] == 0xff_u8 &&
                            decrypted[6] == 0xff_u8 &&
                            decrypted[7] == 0xff_u8

        # Byte 8 : 'T' ou 'F' selon /EncryptMetadata. Si différent,
        # le PDF a été altéré : on refuse plutôt que d'avoir un
        # comportement incohérent.
        expected_meta = @encrypt_metadata ? 'T'.ord.to_u8 : 'F'.ord.to_u8
        return false unless decrypted[8] == expected_meta

        true
      end

      # Algorithm 2.B du spec ISO 32000-2 § 7.6.4.3.4 — fonction de
      # hash itérative spécifique à R=6.
      #
      # Entrées :
      #   - password : mot de passe brut (UTF-8, ≤127 octets)
      #   - salt     : sel de validation ou de clé (8 octets)
      #   - extra    : données additionnelles (vide pour user,
      #                /U[0,48] pour owner)
      #
      # Sortie : 32 octets (hash final).
      private def compute_hash_r6(password : Bytes, salt : Bytes, extra : Bytes) : Bytes
        # 1. K = SHA-256(password || salt || extra)
        ctx = IO::Memory.new(password.size + salt.size + extra.size)
        ctx.write(password)
        ctx.write(salt)
        ctx.write(extra) if extra.size > 0
        k = sha_digest("SHA256", ctx.to_slice)

        round = 0
        loop do
          # 2. K1 = (password || K || extra) répété 64 fois
          chunk_size = password.size + k.size + extra.size
          k1 = Bytes.new(chunk_size * 64)
          64.times do |i|
            base = i * chunk_size
            password.size.times { |j| k1[base + j] = password[j] }
            k.size.times { |j| k1[base + password.size + j] = k[j] }
            extra.size.times { |j| k1[base + password.size + k.size + j] = extra[j] }
          end

          # 3. E = AES-128-CBC(K[0,16], K1, IV=K[16,32], pas de padding)
          aes_key = k[0, 16]
          aes_iv = k[16, 16]
          e = AES.encrypt_no_iv(aes_key, k1, aes_iv, padding: false)

          # 4. Choisir le hash : sum(E[0,16]) mod 3 → SHA-256/384/512
          sum = 0
          16.times { |i| sum += e[i].to_i32 }
          algo = case sum % 3
                 when 0 then "SHA256"
                 when 1 then "SHA384"
                 else        "SHA512"
                 end
          k = sha_digest(algo, e)

          round += 1
          # 5. Sortie : round ≥ 64 ET dernier octet de E ≤ round - 32.
          break if round >= 64 && e[e.size - 1] <= (round - 32)
        end

        k[0, 32]
      end

      # Helper SHA via OpenSSL::Digest (Crystal stdlib n'expose pas
      # SHA-384 dans `Digest::*`, donc on passe par OpenSSL pour les
      # trois variantes utilisées par Algorithm 2.B).
      private def sha_digest(algo : String, data : Bytes) : Bytes
        d = OpenSSL::Digest.new(algo)
        d.update(data)
        d.final
      end

      # ----------------------------------------------------------------
      # Mode ÉCRITURE — fabrique un handler initialisé pour chiffrer.
      # ----------------------------------------------------------------

      # Crée un `StandardSecurity` configuré pour CHIFFRER un document
      # depuis un mot de passe utilisateur (et optionnellement owner).
      #
      # Génère aléatoirement la clé du fichier et calcule /O, /U
      # (et /OE, /UE, /Perms en V=5) selon les algorithmes 3, 5, 8,
      # 9, 10 du spec.
      def self.build_for_encryption(
        user_password : String = "",
        owner_password : String? = nil,
        level : Level = Level::AES_256,
        permissions : Int32 = -4,
        id : Bytes = Bytes.empty,
        encrypt_metadata : Bool = true,
      ) : StandardSecurity
        owner_password ||= user_password

        case level
        in .rc4_128?
          if id.empty?
            raise ArgumentError.new("Chiffrement RC4/AES-128 : /ID requis (utilisé dans la dérivation de clé).")
          end
          build_for_v2(user_password, owner_password, permissions, id, encrypt_metadata)
        in .aes_128?
          if id.empty?
            raise ArgumentError.new("Chiffrement AES-128 : /ID requis.")
          end
          build_for_v4(user_password, owner_password, permissions, id, encrypt_metadata)
        in .aes_256?
          build_for_v5(user_password, owner_password, permissions, id, encrypt_metadata)
        end
      end

      # V=2 R=3 — RC4 128-bit
      private def self.build_for_v2(
        user_password : String, owner_password : String,
        permissions : Int32, id : Bytes, encrypt_metadata : Bool,
      ) : StandardSecurity
        n_bytes = 16 # 128 bits
        o = compute_o_value(user_password, owner_password, n_bytes, r: 3)
        # On a besoin de file_key avant de calculer /U.
        # file_key dépend de /O, donc on construit un handler temporaire.
        tmp = StandardSecurity.new(
          o: o, u: Bytes.new(32), p: permissions, id: id,
          v: 2, r: 3, length: 128, cipher: Cipher::RC4,
          encrypt_metadata: encrypt_metadata,
        )
        file_key = tmp.send_compute_file_key(user_password)
        u = compute_u_value(file_key, id, r: 3)

        ssh = StandardSecurity.new(
          o: o, u: u, p: permissions, id: id,
          v: 2, r: 3, length: 128, cipher: Cipher::RC4,
          encrypt_metadata: encrypt_metadata,
        )
        ssh.set_file_key!(file_key)
        ssh
      end

      # V=4 R=4 — AES-128 + CryptFilter AESV2
      private def self.build_for_v4(
        user_password : String, owner_password : String,
        permissions : Int32, id : Bytes, encrypt_metadata : Bool,
      ) : StandardSecurity
        n_bytes = 16
        # /O et /U sont calculés exactement comme V=2 R=3 (algorithmes
        # identiques selon spec § 7.6.3.4).
        o = compute_o_value(user_password, owner_password, n_bytes, r: 4)
        tmp = StandardSecurity.new(
          o: o, u: Bytes.new(32), p: permissions, id: id,
          v: 4, r: 4, length: 128, cipher: Cipher::AES_128,
          encrypt_metadata: encrypt_metadata,
        )
        file_key = tmp.send_compute_file_key(user_password)
        u = compute_u_value(file_key, id, r: 4)

        ssh = StandardSecurity.new(
          o: o, u: u, p: permissions, id: id,
          v: 4, r: 4, length: 128, cipher: Cipher::AES_128,
          encrypt_metadata: encrypt_metadata,
        )
        ssh.set_file_key!(file_key)
        ssh
      end

      # V=5 R=6 — AES-256 (PDF 2.0)
      private def self.build_for_v5(
        user_password : String, owner_password : String,
        permissions : Int32, id : Bytes, encrypt_metadata : Bool,
      ) : StandardSecurity
        # 1. Génération aléatoire : file_key (32) + 4 sels (8 chacun)
        file_key = Random::Secure.random_bytes(32)
        u_validation_salt = Random::Secure.random_bytes(8)
        u_key_salt = Random::Secure.random_bytes(8)
        o_validation_salt = Random::Secure.random_bytes(8)
        o_key_salt = Random::Secure.random_bytes(8)

        # On utilise une instance temporaire pour appeler compute_hash_r6.
        tmp = StandardSecurity.new(
          o: Bytes.new(48), u: Bytes.new(48), p: permissions, id: id,
          v: 5, r: 6, length: 256, cipher: Cipher::AES_256,
          oe: Bytes.new(32), ue: Bytes.new(32), perms: Bytes.new(16),
          encrypt_metadata: encrypt_metadata,
        )

        u_pwd = user_password.to_slice
        u_pwd = u_pwd[0, 127] if u_pwd.size > 127
        o_pwd = owner_password.to_slice
        o_pwd = o_pwd[0, 127] if o_pwd.size > 127

        # 2. /U = hash || u_validation_salt || u_key_salt
        u_hash = tmp.send_compute_hash_r6(u_pwd, u_validation_salt, Bytes.empty)
        u = Bytes.new(48)
        u_hash.copy_to(u.to_unsafe, 32)
        u_validation_salt.copy_to((u.to_unsafe + 32), 8)
        u_key_salt.copy_to((u.to_unsafe + 40), 8)

        # 3. /UE = AES-256-CBC(intermediate, file_key, IV=zeros, no padding)
        intermediate_u = tmp.send_compute_hash_r6(u_pwd, u_key_salt, Bytes.empty)
        iv_zero = Bytes.new(16, 0_u8)
        ue = AES.encrypt_no_iv(intermediate_u, file_key, iv_zero, padding: false)

        # 4. /O = hash_o || o_validation_salt || o_key_salt
        # extra = U[0,48]
        o_hash = tmp.send_compute_hash_r6(o_pwd, o_validation_salt, u)
        o = Bytes.new(48)
        o_hash.copy_to(o.to_unsafe, 32)
        o_validation_salt.copy_to((o.to_unsafe + 32), 8)
        o_key_salt.copy_to((o.to_unsafe + 40), 8)

        # 5. /OE
        intermediate_o = tmp.send_compute_hash_r6(o_pwd, o_key_salt, u)
        oe = AES.encrypt_no_iv(intermediate_o, file_key, iv_zero, padding: false)

        # 6. /Perms = AES-256-CBC(file_key, perms_block, IV=zeros, no padding)
        # Bloc 16 octets : P (LE 32-bit) || 0xFFFFFFFF || 'T'/'F' || "adb" || 4 random
        perms_block = Bytes.new(16)
        perms_block[0] = (permissions & 0xff).to_u8
        perms_block[1] = ((permissions >> 8) & 0xff).to_u8
        perms_block[2] = ((permissions >> 16) & 0xff).to_u8
        perms_block[3] = ((permissions >> 24) & 0xff).to_u8
        perms_block[4] = 0xff_u8
        perms_block[5] = 0xff_u8
        perms_block[6] = 0xff_u8
        perms_block[7] = 0xff_u8
        perms_block[8] = encrypt_metadata ? 'T'.ord.to_u8 : 'F'.ord.to_u8
        perms_block[9] = 'a'.ord.to_u8
        perms_block[10] = 'd'.ord.to_u8
        perms_block[11] = 'b'.ord.to_u8
        Random::Secure.random_bytes(4).copy_to(perms_block.to_unsafe + 12, 4)
        perms = AES.encrypt_no_iv(file_key, perms_block, iv_zero, padding: false)

        ssh = StandardSecurity.new(
          o: o, u: u, p: permissions, id: id,
          v: 5, r: 6, length: 256, cipher: Cipher::AES_256,
          oe: oe, ue: ue, perms: perms,
          encrypt_metadata: encrypt_metadata,
        )
        ssh.set_file_key!(file_key)
        ssh
      end

      # Algorithm 3 du spec § 7.6.3.4 — calcul de /O.
      private def self.compute_o_value(user_password : String, owner_password : String, n_bytes : Int32, r : Int32) : Bytes
        owner_pad = pad_password_static(owner_password)
        key = ::Digest::MD5.digest(owner_pad)
        if r >= 3
          50.times { key = ::Digest::MD5.digest(key[0, n_bytes]) }
        end
        rc4_key = key[0, n_bytes]
        user_pad = pad_password_static(user_password)
        result = RC4.apply(rc4_key, user_pad)
        if r >= 3
          (1..19).each do |i|
            xor_key = Bytes.new(rc4_key.size) { |k| (rc4_key[k] ^ i.to_u8).to_u8 }
            result = RC4.apply(xor_key, result)
          end
        end
        result # 32 bytes
      end

      # Algorithm 5 (R=3, R=4) du spec § 7.6.3.4 — calcul de /U.
      # Pour R=2 il faut utiliser Algorithm 4 — non géré ici (on
      # n'écrit pas en V=1 R=2).
      private def self.compute_u_value(file_key : Bytes, id : Bytes, r : Int32) : Bytes
        ctx = IO::Memory.new
        ctx.write(PADDING)
        ctx.write(id)
        hash = ::Digest::MD5.digest(ctx.to_slice)
        result = RC4.apply(file_key, hash)
        (1..19).each do |i|
          xor_key = Bytes.new(file_key.size) { |k| (file_key[k] ^ i.to_u8).to_u8 }
          result = RC4.apply(xor_key, result)
        end
        # /U = result (16 bytes) || 16 random bytes (mais en pratique
        # zeros ou padding fonctionnent — Acrobat ne les vérifie pas).
        u = Bytes.new(32)
        result.copy_to(u.to_unsafe, 16)
        # Compléter avec des zéros, qpdf comme PDFium acceptent ça
        # (le validateur ne compare que les 16 premiers octets).
        u
      end

      # Helper statique pour padder un mot de passe sans avoir besoin
      # d'une instance de StandardSecurity (compute_o_value est
      # statique).
      private def self.pad_password_static(password : String) : Bytes
        pwd_bytes = password.to_slice
        out = Bytes.new(32)
        n = {pwd_bytes.size, 32}.min
        n.times { |i| out[i] = pwd_bytes[i] }
        (n...32).each { |i| out[i] = PADDING[i - n] }
        out
      end

      # Setter protégé pour `file_key` (utilisé par les helpers de
      # construction côté chiffrement).
      protected def set_file_key!(key : Bytes) : Nil
        @file_key = key
      end

      # Wrapper public pour `compute_file_key` (privé), utilisé par
      # les helpers de construction côté chiffrement.
      protected def send_compute_file_key(password : String) : Bytes
        compute_file_key(password)
      end

      # Wrapper public pour `compute_hash_r6` (privé).
      protected def send_compute_hash_r6(password : Bytes, salt : Bytes, extra : Bytes) : Bytes
        compute_hash_r6(password, salt, extra)
      end

      # Construit le dictionnaire `/Encrypt` à inclure dans le trailer
      # du PDF chiffré.
      def to_encrypt_dict : Objects::Dictionary
        dict = Objects::Dictionary.new
        dict["Filter"] = Objects::Name.new("Standard")
        dict["V"] = Objects::Number.new(@v)
        dict["R"] = Objects::Number.new(@r)
        dict["O"] = Objects::Str.new(String.new(@o), hex: true)
        dict["U"] = Objects::Str.new(String.new(@u), hex: true)
        dict["P"] = Objects::Number.new(@p)
        dict["Length"] = Objects::Number.new(@length) if @v >= 2
        dict["EncryptMetadata"] = Objects::Boolean.new(false) unless @encrypt_metadata

        case @v
        when 4
          # CryptFilter pour AES-128 ou RC4-128
          cfm = case @cipher
                in .aes_128? then "AESV2"
                in .rc4?     then "V2"
                in .aes_256? then raise "AES-256 non valide pour V=4"
                end

          std_cf = Objects::Dictionary.new
          std_cf["Type"] = Objects::Name.new("CryptFilter")
          std_cf["CFM"] = Objects::Name.new(cfm)
          std_cf["AuthEvent"] = Objects::Name.new("DocOpen")
          std_cf["Length"] = Objects::Number.new(@length // 8)

          cf = Objects::Dictionary.new
          cf["StdCF"] = std_cf
          dict["CF"] = cf
          dict["StmF"] = Objects::Name.new("StdCF")
          dict["StrF"] = Objects::Name.new("StdCF")
        when 5
          # V=5 — ajouter /OE, /UE, /Perms et CryptFilter AESV3
          dict["OE"] = Objects::Str.new(String.new(@oe), hex: true)
          dict["UE"] = Objects::Str.new(String.new(@ue), hex: true)
          dict["Perms"] = Objects::Str.new(String.new(@perms), hex: true)

          std_cf = Objects::Dictionary.new
          std_cf["Type"] = Objects::Name.new("CryptFilter")
          std_cf["CFM"] = Objects::Name.new("AESV3")
          std_cf["AuthEvent"] = Objects::Name.new("DocOpen")
          std_cf["Length"] = Objects::Number.new(32)

          cf = Objects::Dictionary.new
          cf["StdCF"] = std_cf
          dict["CF"] = cf
          dict["StmF"] = Objects::Name.new("StdCF")
          dict["StrF"] = Objects::Name.new("StdCF")
        end

        dict
      end
    end
  end
end
