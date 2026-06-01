module PDF
  module Fonts
    module CFF
      # CFF DICT decoder (Adobe CFF spec § 4).
      #
      # A DICT is a sequence of `(operand* operator)` tuples. Operands
      # are numbers (integers or fixed-point reals) ; operators are
      # 1- or 2-byte codes (the latter prefixed by `0x0C`). The
      # decoder returns a `Hash(Int32, Array(Float64))` keyed by
      # operator id, where 2-byte operators are encoded as
      # `0x0C00 | second_byte` (so `0x0C 0x1E` becomes `0x0C1E`).
      #
      # Float64 covers both integer and real operands uniformly. The
      # caller can `.to_i` when the spec says the operand is integral.
      class Dict
        # Decodes the byte slice into a Hash keyed by operator.
        def self.parse(data : Bytes) : Hash(Int32, Array(Float64))
          result = {} of Int32 => Array(Float64)
          operands = [] of Float64
          i = 0
          while i < data.size
            b0 = data[i]
            case b0
            when 0x1C # short int (2 bytes), signed
              raise "Truncated CFF DICT short int" if i + 2 >= data.size
              v = ((data[i + 1].to_i32 << 8) | data[i + 2].to_i32).to_i16!.to_f64
              operands << v
              i += 3
            when 0x1D # long int (4 bytes), signed
              raise "Truncated CFF DICT long int" if i + 4 >= data.size
              v = ((data[i + 1].to_i32 << 24) | (data[i + 2].to_i32 << 16) |
                   (data[i + 3].to_i32 << 8) | data[i + 4].to_i32).to_i32.to_f64
              operands << v
              i += 5
            when 0x1E # BCD real
              v, consumed = decode_real(data, i + 1)
              operands << v
              i += 1 + consumed
            when 32..246
              # Short integer: -107..107
              operands << (b0.to_i32 - 139).to_f64
              i += 1
            when 247..250
              # Positive integer: 108..1131
              raise "Truncated CFF DICT pos int" if i + 1 >= data.size
              operands << (((b0.to_i32 - 247) * 256) + data[i + 1].to_i32 + 108).to_f64
              i += 2
            when 251..254
              # Negative integer: -1131..-108
              raise "Truncated CFF DICT neg int" if i + 1 >= data.size
              operands << (-((b0.to_i32 - 251) * 256) - data[i + 1].to_i32 - 108).to_f64
              i += 2
            when 12 # 0x0C — escape, 2-byte operator
              raise "Truncated CFF DICT escape operator" if i + 1 >= data.size
              op = 0x0C00 | data[i + 1].to_i32
              result[op] = operands
              operands = [] of Float64
              i += 2
            when 0..21 # 1-byte operator (excluding 12 handled above)
              result[b0.to_i32] = operands
              operands = [] of Float64
              i += 1
            else
              raise "CFF DICT : reserved byte 0x#{b0.to_s(16)} at offset #{i}"
            end
          end
          result
        end

        # Decodes a BCD real (Adobe CFF spec § 4 table 5). Returns
        # the value and number of bytes consumed (excluding the
        # leading 0x1E marker).
        private def self.decode_real(data : Bytes, start : Int32) : Tuple(Float64, Int32)
          chars = String::Builder.new
          consumed = 0
          loop do
            raise "Truncated CFF BCD real" if start + consumed >= data.size
            byte = data[start + consumed]
            consumed += 1
            hi = (byte >> 4) & 0x0F
            lo = byte & 0x0F
            done = false
            [hi, lo].each do |nibble|
              break if done
              case nibble
              when 0..9 then chars << ('0'.ord + nibble).unsafe_chr
              when 0xA  then chars << '.'
              when 0xB  then chars << 'E'
              when 0xC  then chars << "E-"
              when 0xE  then chars << '-'
              when 0xF  then done = true
              end
            end
            break if done
          end
          {chars.to_s.to_f64, consumed}
        end
      end
    end
  end
end
