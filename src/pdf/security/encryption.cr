require "digest/md5"

module PDF
  module Security
    # PDF permission flags (bit positions, 1-based as per PDF spec)
    @[Flags]
    enum Permission
      # Bit 3: Print the document
      Print = 4 # 1 << 2 (bit 3, 0-indexed = bit 2)
      # Bit 4: Modify the contents
      Modify = 8 # 1 << 3
      # Bit 5: Copy or extract text and graphics
      Copy = 16 # 1 << 4
      # Bit 6: Add or modify text annotations and interactive form fields
      Annotate = 32 # 1 << 5
    end

    # PDF standard security handler password padding string.
    # This is defined in the PDF specification (Table 3.19).
    PASSWORD_PADDING = Bytes[
      0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41,
      0x64, 0x00, 0x4E, 0x56, 0xFF, 0xFA, 0x01, 0x08,
      0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68, 0x3E, 0x80,
      0x2F, 0x0C, 0xA9, 0xFE, 0x64, 0x53, 0x69, 0x7A,
    ]

    # Encryption configuration for a PDF document.
    class Encryption
      # User password (empty string = no password required to open)
      getter user_password : String

      # Owner password
      getter owner_password : String

      # Key length in bytes (5 = 40-bit, 16 = 128-bit)
      getter key_length : Int32

      # Permission flags as a 32-bit integer
      getter permissions_value : Int32

      # Computed encryption key
      getter encryption_key : Bytes

      # Owner password hash (O value)
      getter owner_hash : Bytes

      # User password hash (U value)
      getter user_hash : Bytes

      # Revision number (2 = 40-bit RC4, 3 = 128-bit RC4)
      getter revision : Int32

      # Algorithm version (1 = 40-bit, 2 = longer keys)
      getter version : Int32

      def initialize(
        @user_password : String = "",
        @owner_password : String = "",
        permissions : Array(Permission) = [Permission::Print],
        key_length : Int32 = 40,
      )
        # Validate key length
        unless key_length == 40 || key_length == 128
          raise ArgumentError.new("Key length must be 40 or 128, got #{key_length}")
        end

        @key_length = key_length // 8 # Convert to bytes

        if key_length == 40
          @revision = 2
          @version = 1
        else
          @revision = 3
          @version = 2
        end

        # Use owner_password or fall back to user_password
        if @owner_password.empty?
          @owner_password = @user_password
        end

        # Build permissions value (all bits set except denied permissions)
        @permissions_value = compute_permissions(permissions)

        # Compute password hashes and encryption key (Algorithm 3.2-3.5)
        @owner_hash = compute_owner_hash
        @encryption_key = compute_user_encryption_key
        @user_hash = compute_user_hash
      end

      # Returns the encryption dictionary for the PDF trailer.
      def to_dictionary : Objects::Dictionary
        dict = Objects::Dictionary.new
        dict["Filter"] = Objects::Name.new("Standard")
        dict["V"] = Objects::Number.new(@version)
        dict["R"] = Objects::Number.new(@revision)
        dict["O"] = Objects::Str.new(String.new(@owner_hash), hex: true)
        dict["U"] = Objects::Str.new(String.new(@user_hash), hex: true)
        dict["P"] = Objects::Number.new(@permissions_value)

        if @revision >= 3
          dict["Length"] = Objects::Number.new(@key_length * 8)
        end

        dict
      end

      # Encrypt a string for the given object.
      # PDF spec Algorithm 3.1
      def encrypt_string(data : Bytes, object_number : Int32, generation : Int32) : Bytes
        object_key = compute_object_key(object_number, generation)
        Arcfour.new(object_key).encrypt(data)
      end

      # Encrypt a string for the given object.
      def encrypt_string(data : String, object_number : Int32, generation : Int32) : Bytes
        encrypt_string(data.to_slice, object_number, generation)
      end

      private def compute_permissions(permissions : Array(Permission)) : Int32
        # Start with all bits set (full permissions)
        # Bits 1-2 must be 0, bits 7-8 must be 1 (reserved)
        value = -1_i32 # All bits set

        # Clear bits 3-6 first, then set only the ones in permissions
        value &= ~0b00111100 # Clear bits 3-6

        permissions.each do |perm|
          value |= perm.value
        end

        # Bits 13-32 must be 1 for revision 2
        # Bits 1-2 must be 0
        value &= ~0b11 # Clear bits 1-2

        value
      end

      # Pad or truncate password to 32 bytes (Algorithm 3.2 step a)
      private def pad_password(password : String) : Bytes
        pw_bytes = password.to_slice
        result = Bytes.new(32)

        # Copy password bytes (truncate to 32)
        copy_len = Math.min(pw_bytes.size, 32)
        pw_bytes[0, copy_len].copy_to(result.to_unsafe, copy_len)

        # Pad with standard padding
        if copy_len < 32
          PASSWORD_PADDING[0, 32 - copy_len].copy_to(result.to_unsafe + copy_len, 32 - copy_len)
        end

        result
      end

      # Compute the O (owner) value - Algorithm 3.3
      private def compute_owner_hash : Bytes
        # Step a: Pad the owner password
        padded_owner = pad_password(@owner_password)

        # Step b: MD5 hash of padded owner password
        md5 = Digest::MD5.digest(padded_owner)

        # Step c (Rev 3): Hash 50 more times
        if @revision >= 3
          50.times { md5 = Digest::MD5.digest(md5) }
        end

        # Step d: Use first key_length bytes as RC4 key
        rc4_key = md5[0, @key_length]

        # Step e: Pad the user password
        padded_user = pad_password(@user_password)

        # Step f: RC4 encrypt the padded user password
        result = Arcfour.new(rc4_key).encrypt(padded_user)

        # Step g (Rev 3): Additional encryption rounds
        if @revision >= 3
          19.times do |i|
            new_key = Bytes.new(@key_length)
            rc4_key.each_with_index { |b, j| new_key[j] = b ^ (i + 1).to_u8 }
            result = Arcfour.new(new_key).encrypt(result)
          end
        end

        result
      end

      # Compute the user encryption key - Algorithm 3.2
      private def compute_user_encryption_key : Bytes
        md5 = Digest::MD5.new

        # Step a-b: Pad user password
        md5.update(pad_password(@user_password))

        # Step c: Pass O value
        md5.update(@owner_hash)

        # Step d: Pass permission value as little-endian 4 bytes
        perm = @permissions_value
        perm_bytes = Bytes[
          (perm & 0xFF).to_u8,
          ((perm >> 8) & 0xFF).to_u8,
          ((perm >> 16) & 0xFF).to_u8,
          ((perm >> 24) & 0xFF).to_u8,
        ]
        md5.update(perm_bytes)

        # Step e: File identifier (we use empty for now — will be
        # updated when the document writes its ID)
        # For simplicity, we use an empty file ID

        result = md5.final

        # Step f (Rev 3): Hash 50 more times
        if @revision >= 3
          50.times do
            result = Digest::MD5.digest(result[0, @key_length])
          end
        end

        # Step g: Use first key_length bytes
        result[0, @key_length].dup
      end

      # Compute the U (user) value - Algorithm 3.4 (Rev 2) / 3.5 (Rev 3)
      private def compute_user_hash : Bytes
        if @revision == 2
          # Algorithm 3.4: Encrypt PASSWORD_PADDING with encryption key
          Arcfour.new(@encryption_key).encrypt(PASSWORD_PADDING)
        else
          # Algorithm 3.5
          md5 = Digest::MD5.new
          md5.update(PASSWORD_PADDING)
          # File ID would go here if we had one
          hash = md5.final

          result = Arcfour.new(@encryption_key).encrypt(hash)

          19.times do |i|
            new_key = Bytes.new(@key_length)
            @encryption_key.each_with_index { |b, j| new_key[j] = b ^ (i + 1).to_u8 }
            result = Arcfour.new(new_key).encrypt(result)
          end

          # Pad to 32 bytes
          padded = Bytes.new(32)
          result.copy_to(padded.to_unsafe, Math.min(result.size, 32))
          padded
        end
      end

      # Compute object-specific key - Algorithm 3.1
      private def compute_object_key(object_number : Int32, generation : Int32) : Bytes
        md5 = Digest::MD5.new
        md5.update(@encryption_key)

        # Object number as 3 bytes LE
        md5.update(Bytes[
          (object_number & 0xFF).to_u8,
          ((object_number >> 8) & 0xFF).to_u8,
          ((object_number >> 16) & 0xFF).to_u8,
        ])

        # Generation number as 2 bytes LE
        md5.update(Bytes[
          (generation & 0xFF).to_u8,
          ((generation >> 8) & 0xFF).to_u8,
        ])

        result = md5.final
        n = Math.min(@key_length + 5, 16)
        result[0, n].dup
      end
    end
  end
end
