module PDF
  module Fonts
    module TrueType
      module Tables
        # The 'kern' table contains kerning pairs — adjustments to
        # the spacing between specific pairs of glyphs.
        class Kern
          include IOHelpers

          # A single kerning pair
          struct KernPair
            getter left : UInt16
            getter right : UInt16
            getter value : Int16

            def initialize(@left : UInt16, @right : UInt16, @value : Int16)
            end
          end

          # All kerning pairs indexed by (left << 16 | right)
          getter pairs : Hash(UInt32, Int16)

          def initialize(@pairs : Hash(UInt32, Int16))
          end

          # Parse the kern table from raw bytes
          def self.parse(data : Bytes) : Kern
            io = IO::Memory.new(data)
            pairs = Hash(UInt32, Int16).new

            version = read_uint16(io)

            case version
            when 0
              # Microsoft format (version 0)
              n_tables = read_uint16(io)
              n_tables.times do
                _sub_version = read_uint16(io)
                sub_length = read_uint16(io)
                coverage = read_uint16(io)

                format = coverage >> 8
                horizontal = (coverage & 0x01) != 0

                if format == 0 && horizontal
                  parse_format0(io, pairs)
                else
                  # Skip unsupported subtable
                  remaining = sub_length.to_i - 6
                  skip_bytes(io, remaining) if remaining > 0
                end
              end
            when 1
              # Apple format (version 1.0 stored as fixed 0x00010000)
              # Re-read as 32-bit
              io.seek(0)
              _version32 = read_uint32(io)
              n_tables = read_uint32(io)
              n_tables.times do
                _sub_length = read_uint32(io)
                coverage = read_uint16(io)
                _tuple_index = read_uint16(io)

                format = coverage & 0xFF
                horizontal = (coverage & 0x8000) == 0
                # cross_stream = (coverage & 0x4000) != 0

                if format == 0 && horizontal
                  parse_format0(io, pairs)
                else
                  # Skip — we only handle format 0
                  break
                end
              end
            end

            new(pairs)
          end

          # Parse format 0 subtable (ordered list of kerning pairs)
          private def self.parse_format0(io : IO, pairs : Hash(UInt32, Int16)) : Nil
            n_pairs = read_uint16(io)
            _search_range = read_uint16(io)
            _entry_selector = read_uint16(io)
            _range_shift = read_uint16(io)

            n_pairs.times do
              left = read_uint16(io)
              right = read_uint16(io)
              value = read_int16(io)
              key = (left.to_u32 << 16) | right.to_u32
              pairs[key] = value
            end
          end

          # Look up kerning value for a pair of glyph IDs.
          # Returns 0 if no kerning pair exists.
          def kerning(left_glyph : UInt16, right_glyph : UInt16) : Int16
            key = (left_glyph.to_u32 << 16) | right_glyph.to_u32
            @pairs[key]? || 0_i16
          end

          extend IOHelpers
        end
      end
    end
  end
end
