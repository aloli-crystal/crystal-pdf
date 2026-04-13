module PDF
  module Security
    # RC4 (ARCFOUR) stream cipher implementation.
    #
    # Used by PDF encryption for RC4 40-bit and 128-bit modes.
    # This implements the algorithm described in the PDF specification.
    class Arcfour
      @sbox : Array(UInt8)
      @i : Int32
      @j : Int32

      def initialize(key : Bytes)
        @sbox = (0_u8..255_u8).to_a
        @i = 0
        @j = 0

        # Key-scheduling algorithm (KSA)
        j = 0
        256.times do |i|
          j = (j + @sbox[i].to_i + key[i % key.size].to_i) % 256
          @sbox[i], @sbox[j] = @sbox[j], @sbox[i]
        end
      end

      # Encrypt/decrypt data (RC4 is symmetric)
      def encrypt(data : Bytes) : Bytes
        result = Bytes.new(data.size)
        data.each_with_index do |byte, idx|
          result[idx] = byte ^ next_key_byte
        end
        result
      end

      # Encrypt/decrypt a string
      def encrypt(data : String) : Bytes
        encrypt(data.to_slice)
      end

      private def next_key_byte : UInt8
        @i = (@i + 1) % 256
        @j = (@j + @sbox[@i].to_i) % 256
        @sbox[@i], @sbox[@j] = @sbox[@j], @sbox[@i]
        @sbox[(@sbox[@i].to_i + @sbox[@j].to_i) % 256]
      end
    end
  end
end
