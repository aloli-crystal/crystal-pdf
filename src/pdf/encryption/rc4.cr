module PDF
  module Encryption
    # RC4 stream cipher (Rivest Cipher 4).
    #
    # PDF utilise RC4 pour le chiffrement Standard Security V=1
    # (40 bit) et V=2 (40-128 bit). Crystal stdlib ne fournit pas
    # RC4 (algorithme déprécié pour la sécurité — mais incontournable
    # pour lire les PDFs des années 2000-2015).
    #
    # Implémentation directe de l'algorithme RFC-equivalent
    # (Schneier, Applied Cryptography, §17.1). ~50 lignes.
    #
    # Symétrique : `encrypt(key, encrypt(key, data)) == data`.
    # Pour PDF on n'utilise donc qu'`apply` qui sert d'aller comme
    # de retour.
    #
    # ```
    # cipher = PDF::Encryption::RC4.new(key)
    # plain = cipher.apply(encrypted_bytes)
    # ```
    class RC4
      @s : StaticArray(UInt8, 256)

      def initialize(key : Bytes)
        raise ArgumentError.new("RC4 key must not be empty") if key.empty?
        @s = StaticArray(UInt8, 256).new(0_u8)
        # KSA — Key-Scheduling Algorithm. Toutes les arithmétiques
        # se font en UInt32 puis on tronque, pour éviter les
        # overflows UInt8 (sum 0..255+0..255+0..255 ne tient pas
        # dans un UInt8).
        256.times { |i| @s[i] = i.to_u8 }
        j = 0_u32
        256.times do |i|
          j = (j + @s[i].to_u32 + key[i % key.size].to_u32) & 0xff_u32
          @s[i], @s[j] = @s[j], @s[i]
        end
      end

      # Applique le keystream (XOR) sur `data`. Retourne un nouveau
      # `Bytes`. Ne mute PAS l'instance — chaque `apply` repart de
      # l'état KSA initial. Pour traiter un grand flux par morceaux,
      # créer une nouvelle instance par message.
      def apply(data : Bytes) : Bytes
        # Copie de l'état pour ne pas muter le S original
        s_local = StaticArray(UInt8, 256).new(0_u8)
        256.times { |k| s_local[k] = @s[k] }

        out = Bytes.new(data.size)
        i = 0_u32
        j = 0_u32
        data.each_with_index do |byte, idx|
          i = (i + 1_u32) & 0xff_u32
          j = (j + s_local[i].to_u32) & 0xff_u32
          s_local[i], s_local[j] = s_local[j], s_local[i]
          k_idx = (s_local[i].to_u32 + s_local[j].to_u32) & 0xff_u32
          out[idx] = byte ^ s_local[k_idx]
        end
        out
      end

      # Helper one-shot.
      def self.apply(key : Bytes, data : Bytes) : Bytes
        new(key).apply(data)
      end
    end
  end
end
