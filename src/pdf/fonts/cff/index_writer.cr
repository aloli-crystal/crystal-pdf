module PDF
  module Fonts
    module CFF
      # Writes a CFF INDEX from a list of byte entries (Adobe CFF
      # spec § 5). The reverse of `CFF::Index`. Used by the subsetter
      # to emit reduced INDEXes (CharStrings, Subrs, FDArray).
      module IndexWriter
        # Serialises `entries` as a CFF INDEX into `io`.
        def self.write(entries : Array(Bytes), io : IO) : Nil
          if entries.empty?
            io.write_byte(0_u8)
            io.write_byte(0_u8)
            return
          end

          # Compute total data size to size the offsets correctly.
          data_size = entries.reduce(0) { |acc, e| acc + e.size }
          max_offset = data_size + 1
          off_size = case max_offset
                     when 0..0xFF     then 1
                     when 0..0xFFFF   then 2
                     when 0..0xFFFFFF then 3
                     else                  4
                     end

          # count (u16 BE)
          count = entries.size
          io.write_byte(((count >> 8) & 0xFF).to_u8)
          io.write_byte((count & 0xFF).to_u8)

          # offSize
          io.write_byte(off_size.to_u8)

          # offsets — count+1 entries, 1-based
          cumul = 1
          write_offset(io, cumul, off_size)
          entries.each do |e|
            cumul += e.size
            write_offset(io, cumul, off_size)
          end

          # data — concatenation of all entries
          entries.each { |e| io.write(e) }
        end

        # Convenience : serialise into a `Bytes` slice.
        def self.write(entries : Array(Bytes)) : Bytes
          io = IO::Memory.new
          write(entries, io)
          io.to_slice
        end

        private def self.write_offset(io : IO, offset : Int32, off_size : Int32) : Nil
          case off_size
          when 1
            io.write_byte((offset & 0xFF).to_u8)
          when 2
            io.write_byte(((offset >> 8) & 0xFF).to_u8)
            io.write_byte((offset & 0xFF).to_u8)
          when 3
            io.write_byte(((offset >> 16) & 0xFF).to_u8)
            io.write_byte(((offset >> 8) & 0xFF).to_u8)
            io.write_byte((offset & 0xFF).to_u8)
          when 4
            io.write_byte(((offset >> 24) & 0xFF).to_u8)
            io.write_byte(((offset >> 16) & 0xFF).to_u8)
            io.write_byte(((offset >> 8) & 0xFF).to_u8)
            io.write_byte((offset & 0xFF).to_u8)
          else
            raise "IndexWriter : unsupported off_size #{off_size}"
          end
        end
      end
    end
  end
end
