require "openssl/cipher"
require "random/secure"

module PDF
  module Encryption
    # AES-128-CBC et AES-256-CBC pour le « Standard Security Handler »
    # PDF (V=4 et V=5 du spec ISO 32000-1).
    #
    # Convention PDF (§ 7.6.2) :
    #
    # * À l'encryptage, l'IV est généré aléatoirement (16 octets) et
    #   préfixé au cipher text. La sortie est donc `IV (16) || CT`.
    # * Au déchiffrement, l'IV est lu sur les 16 premiers octets
    #   du blob, le reste est le CT.
    # * Padding PKCS#7 (géré nativement par OpenSSL).
    #
    # Cette classe fournit deux helpers symétriques côté chiffrement
    # et déchiffrement, pour des clés AES de 128 ou 256 bits (16 ou
    # 32 octets). Toute autre taille lève `ArgumentError`.
    module AES
      # Taille du bloc AES en octets (toujours 16 quel que soit V=4
      # ou V=5).
      BLOCK_SIZE = 16

      # Déchiffre `data` (= `IV (16) || CT`) avec la clé `key`.
      # Retourne le plaintext sans le padding PKCS#7.
      def self.decrypt(key : Bytes, data : Bytes) : Bytes
        check_key!(key)
        if data.size < BLOCK_SIZE
          raise ArgumentError.new("AES : données trop courtes (#{data.size} < 16 octets pour l'IV)")
        end
        iv = data[0, BLOCK_SIZE]
        ct = data[BLOCK_SIZE, data.size - BLOCK_SIZE]

        cipher = OpenSSL::Cipher.new(cipher_name(key.size))
        cipher.decrypt
        cipher.key = key
        cipher.iv = iv
        # Le padding PKCS#7 est activé par défaut.
        out = IO::Memory.new(ct.size)
        out.write(cipher.update(ct))
        out.write(cipher.final)
        out.to_slice
      end

      # Chiffre `data` avec la clé `key`. L'IV est tiré aléatoirement
      # via `Random::Secure` et préfixé au cipher text.
      def self.encrypt(key : Bytes, data : Bytes, iv : Bytes? = nil) : Bytes
        check_key!(key)
        actual_iv = iv || Random::Secure.random_bytes(BLOCK_SIZE)
        if actual_iv.size != BLOCK_SIZE
          raise ArgumentError.new("AES : IV doit faire #{BLOCK_SIZE} octets (#{actual_iv.size} reçu)")
        end

        cipher = OpenSSL::Cipher.new(cipher_name(key.size))
        cipher.encrypt
        cipher.key = key
        cipher.iv = actual_iv
        ct = IO::Memory.new(data.size + BLOCK_SIZE)
        ct.write(actual_iv)
        ct.write(cipher.update(data))
        ct.write(cipher.final)
        ct.to_slice
      end

      # Variante sans IV préfixé : on chiffre/déchiffre avec un IV
      # connu (typiquement zéro pour la dérivation /OE et /UE en
      # V=5). Le résultat est UNIQUEMENT le cipher text.
      def self.decrypt_no_iv(key : Bytes, ct : Bytes, iv : Bytes, padding : Bool = true) : Bytes
        check_key!(key)
        cipher = OpenSSL::Cipher.new(cipher_name(key.size))
        cipher.decrypt
        cipher.key = key
        cipher.iv = iv
        cipher.padding = padding
        out = IO::Memory.new(ct.size)
        out.write(cipher.update(ct))
        out.write(cipher.final)
        out.to_slice
      end

      # Chiffrement sans IV préfixé (typiquement /OE, /UE en V=5).
      def self.encrypt_no_iv(key : Bytes, pt : Bytes, iv : Bytes, padding : Bool = true) : Bytes
        check_key!(key)
        cipher = OpenSSL::Cipher.new(cipher_name(key.size))
        cipher.encrypt
        cipher.key = key
        cipher.iv = iv
        cipher.padding = padding
        out = IO::Memory.new(pt.size)
        out.write(cipher.update(pt))
        out.write(cipher.final)
        out.to_slice
      end

      private def self.cipher_name(key_size : Int32) : String
        case key_size
        when 16 then "aes-128-cbc"
        when 32 then "aes-256-cbc"
        else
          raise ArgumentError.new("Taille de clé AES invalide : #{key_size} octets (16 ou 32 attendus)")
        end
      end

      private def self.check_key!(key : Bytes) : Nil
        unless key.size == 16 || key.size == 32
          raise ArgumentError.new("Taille de clé AES invalide : #{key.size} octets (16 ou 32 attendus)")
        end
      end
    end
  end
end
