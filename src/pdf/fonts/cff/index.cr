module PDF
  module Fonts
    module CFF
      # CFF INDEX structure (Adobe CFF spec § 5).
      #
      # An INDEX is the workhorse container of CFF — used for Name,
      # Top DICT, String, Global Subr, Local Subr, CharStrings, FD
      # Array, and Encoding/Charset arrays. Its layout :
      #
      # ```
      # count      : u16 (number of entries)
      # offSize    : u8  (size of each offset, 1..4 bytes)
      # offsets    : (count + 1) entries of offSize bytes, 1-based
      # data       : variable bytes
      # ```
      #
      # Each entry `i` (0-based externally) is the byte slice from
      # `offsets[i]` to `offsets[i+1]` (exclusive) inside `data`.
      #
      # A degenerate empty INDEX has `count = 0` and occupies exactly
      # 2 bytes (only the count field, no offSize, no offsets, no data).
      struct Index
        include TrueType::IOHelpers

        getter entries : Array(Bytes)

        # Total size of the INDEX in bytes (including header). Useful
        # for the parser to advance past it.
        getter size : Int32

        def initialize(@entries : Array(Bytes), @size : Int32)
        end

        # Reads an INDEX starting at the current position in `io`.
        def self.read(io : IO) : Index
          parser = new([] of Bytes, 0)
          parser.read_index(io)
        end

        protected def read_index(io : IO) : Index
          start_pos = io.pos.to_i32
          count = read_uint16(io).to_i32
          if count == 0
            return Index.new([] of Bytes, 2)
          end

          off_size = read_uint8(io).to_i32
          unless (1..4).includes?(off_size)
            raise ArgumentError.new("CFF INDEX : invalid offSize #{off_size} (expected 1..4)")
          end

          # `count + 1` offsets, each `off_size` bytes. Offsets are
          # 1-based relative to the byte *before* the data block.
          offsets = Array(Int32).new(count + 1)
          (count + 1).times do
            offsets << read_offset(io, off_size)
          end

          # `data` starts at the current position and has length
          # `offsets[-1] - 1` (because offsets are 1-based).
          data_size = offsets[count] - 1
          data_start = io.pos.to_i32
          data = Bytes.new(data_size)
          io.read_fully(data) if data_size > 0

          entries = Array(Bytes).new(count)
          count.times do |i|
            from = offsets[i] - 1
            to = offsets[i + 1] - 1
            entries << data[from, to - from]
          end

          total = io.pos.to_i32 - start_pos
          Index.new(entries, total)
        end

        private def read_offset(io : IO, off_size : Int32) : Int32
          case off_size
          when 1 then read_uint8(io).to_i32
          when 2 then read_uint16(io).to_i32
          when 3
            b1 = read_uint8(io).to_i32
            b2 = read_uint8(io).to_i32
            b3 = read_uint8(io).to_i32
            (b1 << 16) | (b2 << 8) | b3
          when 4 then read_uint32(io).to_i32!
          else        raise "unreachable"
          end
        end
      end
    end
  end
end
