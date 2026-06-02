module PDF
  module Fonts
    module CFF
      # Produces a reduced CFF blob from a `Parser` by replacing the
      # charstrings of unused glyphs with a single `endchar` byte.
      # The MVP keeps the original GID numbering and **does not**
      # renumber the local and global subrs — they are copied
      # verbatim with their original indices and bias, which keeps
      # every `callsubr`/`callgsubr` in the surviving charstrings
      # valid without rewriting their operands.
      #
      # On a CJK font the charstrings carry the bulk of the bytes
      # (~80 %), so collapsing 65 000+ unused glyph bodies to a
      # single `endchar` recovers most of the file size on its own.
      # A future palier may add subr renumbering for the last few
      # percent of savings, but that requires a full Type 2 stack
      # interpreter to handle the case where a `callsubr` consumes
      # a value pushed by a previously-called subr — out of MVP
      # scope.
      #
      # ## Pipeline
      #
      # 1. Determine which GIDs to keep (caller decides ; GID 0 is
      #    always added).
      # 2. Replace every non-kept charstring with `Bytes[14_u8]`
      #    (`endchar`).
      # 3. Copy Name / String / Global Subr / Charset / FDSelect /
      #    FDArray / Local Subr INDEXes verbatim.
      # 4. Re-emit Top DICT, FD Font DICTs and Private DICTs with
      #    patched offsets (using the 5-byte long-int form for size
      #    stability).
      #
      # ## Current scope
      #
      # * **CIDFonts only.** Non-CID fonts raise. The same layout
      #   logic applies but with a single Private DICT / Local Subrs
      #   pair ; a follow-up palier will cover it.
      class Subsetter
        getter parser : Parser
        getter kept_gids : Set(Int32)

        def initialize(@parser : Parser, kept_gids : Enumerable(Int32))
          @kept_gids = Set(Int32).new(kept_gids)
          @kept_gids << 0 # always keep .notdef
        end

        def subset : Bytes
          raise NotImplementedError.new("non-CID CFF subsetting not yet implemented") unless @parser.cid_font?

          num_glyphs = @parser.charstrings.entries.size

          # === Rewrite charstrings : keep or replace by endchar ===
          new_charstrings = Array(Bytes).new(num_glyphs)
          (0...num_glyphs).each do |gid|
            new_charstrings << if @kept_gids.includes?(gid)
              @parser.charstrings.entries[gid]
            else
              Bytes[14_u8]
            end
          end

          # === Pre-serialise size-stable sections ===
          header = Bytes[
            @parser.major.to_u8,
            @parser.minor.to_u8,
            4_u8, # hdrSize
            2_u8, # header off_size
          ]

          name_index_bytes = IndexWriter.write(@parser.name_index.entries)
          string_index_bytes = IndexWriter.write(@parser.string_index.entries)
          gsubr_bytes = IndexWriter.write(@parser.global_subrs.entries)
          charset_bytes = extract_charset_bytes
          fdselect_bytes = extract_fdselect_bytes
          charstrings_bytes = IndexWriter.write(new_charstrings)

          fd_local_subr_bytes = @parser.fd_local_subrs.map do |idx|
            IndexWriter.write(idx.entries)
          end

          # Placeholders (offsets = 0). These are size-stable because
          # every patched offset is encoded as a 5-byte long-int.
          fd_dict_placeholder = build_fd_dicts_with(private_offset: 0, private_size: 0)
          fd_array_placeholder = IndexWriter.write(fd_dict_placeholder)
          private_dict_placeholders = @parser.fd_privates.map do |dict|
            build_private_dict(dict, subrs_offset: 0)
          end
          top_dict_placeholder = build_top_dict(charstrings_offset: 0, charset_offset: 0, fdselect_offset: 0, fdarray_offset: 0)
          top_dict_index_placeholder = IndexWriter.write([top_dict_placeholder])

          # === Compute final offsets ===
          pos = header.size
          pos += name_index_bytes.size
          pos += top_dict_index_placeholder.size # Top DICT INDEX
          pos += string_index_bytes.size
          pos += gsubr_bytes.size
          charset_offset = pos
          pos += charset_bytes.size
          fdselect_offset = pos
          pos += fdselect_bytes.size
          charstrings_offset = pos
          pos += charstrings_bytes.size
          fdarray_offset = pos
          pos += fd_array_placeholder.size

          private_offsets = [] of Tuple(Int32, Int32)
          local_subr_positions = [] of Int32
          @parser.fd_privates.size.times do |fd|
            priv_size = private_dict_placeholders[fd].size
            private_offsets << {pos, priv_size}
            pos += priv_size
            local_subr_positions << pos
            pos += fd_local_subr_bytes[fd].size
          end

          # === Re-emit DICTs with real offsets ===
          new_top_dict = build_top_dict(
            charstrings_offset: charstrings_offset,
            charset_offset: charset_offset,
            fdselect_offset: fdselect_offset,
            fdarray_offset: fdarray_offset,
          )
          new_top_dict_index = IndexWriter.write([new_top_dict])
          if new_top_dict_index.size != top_dict_index_placeholder.size
            raise "Subsetter : Top DICT INDEX size shift (#{top_dict_index_placeholder.size} → #{new_top_dict_index.size})"
          end

          new_fd_dicts = @parser.fd_array.map_with_index do |dict, fd|
            offset, size = private_offsets[fd]
            build_fd_dict(dict, private_offset: offset, private_size: size)
          end
          new_fd_array_bytes = IndexWriter.write(new_fd_dicts)
          if new_fd_array_bytes.size != fd_array_placeholder.size
            raise "Subsetter : FDArray INDEX size shift (#{fd_array_placeholder.size} → #{new_fd_array_bytes.size})"
          end

          new_private_dicts = @parser.fd_privates.map_with_index do |dict, fd|
            relative = local_subr_positions[fd] - private_offsets[fd][0]
            build_private_dict(dict, subrs_offset: relative)
          end
          new_private_dicts.each_with_index do |bytes, fd|
            if bytes.size != private_dict_placeholders[fd].size
              raise "Subsetter : Private DICT size shift for FD #{fd}"
            end
          end

          # === Concatenate ===
          out = IO::Memory.new
          out.write(header)
          out.write(name_index_bytes)
          out.write(new_top_dict_index)
          out.write(string_index_bytes)
          out.write(gsubr_bytes)
          out.write(charset_bytes)
          out.write(fdselect_bytes)
          out.write(charstrings_bytes)
          out.write(new_fd_array_bytes)
          new_private_dicts.each_with_index do |priv, fd|
            out.write(priv)
            out.write(fd_local_subr_bytes[fd])
          end
          out.to_slice
        end

        # ---- DICT builders (everything below) ----

        private def build_top_dict(charstrings_offset : Int32, charset_offset : Int32, fdselect_offset : Int32, fdarray_offset : Int32) : Bytes
          long_offsets = {
            Parser::TOP_CHARSTRINGS => charstrings_offset,
            Parser::TOP_CHARSET     => charset_offset,
            Parser::TOP_FDSELECT    => fdselect_offset,
            Parser::TOP_FDARRAY     => fdarray_offset,
          }
          write_dict(@parser.top_dict, long_offsets, {} of Int32 => Tuple(Int32, Int32))
        end

        private def build_fd_dict(original : Hash(Int32, Array(Float64)), private_offset : Int32, private_size : Int32) : Bytes
          pairs = {} of Int32 => Tuple(Int32, Int32)
          pairs[Parser::TOP_PRIVATE] = {private_size, private_offset}
          write_dict(original, {} of Int32 => Int32, pairs)
        end

        private def build_fd_dicts_with(private_offset : Int32, private_size : Int32) : Array(Bytes)
          @parser.fd_array.map do |dict|
            build_fd_dict(dict, private_offset: private_offset, private_size: private_size)
          end
        end

        private def build_private_dict(original : Hash(Int32, Array(Float64)), subrs_offset : Int32) : Bytes
          singles = {} of Int32 => Int32
          singles[Parser::PRIVATE_SUBRS] = subrs_offset if original.has_key?(Parser::PRIVATE_SUBRS)
          write_dict(original, singles, {} of Int32 => Tuple(Int32, Int32))
        end

        # Writes a DICT, forcing the 5-byte long-int encoding for
        # the operators listed in `single_long` (one operand) or
        # `pair_long` (two operands). Other operands use the compact
        # encoding.
        private def write_dict(
          original : Hash(Int32, Array(Float64)),
          single_long : Hash(Int32, Int32),
          pair_long : Hash(Int32, Tuple(Int32, Int32)),
        ) : Bytes
          io = IO::Memory.new
          original.each do |op, operands|
            if v = single_long[op]?
              write_long_int(io, v)
            elsif pair = pair_long[op]?
              write_long_int(io, pair[0])
              write_long_int(io, pair[1])
            else
              operands.each { |o| write_dict_operand_compact(io, o) }
            end
            if op < 0x100
              io.write_byte(op.to_u8)
            else
              io.write_byte(12_u8)
              io.write_byte((op & 0xFF).to_u8)
            end
          end
          io.to_slice
        end

        private def write_long_int(io : IO::Memory, value : Int32) : Nil
          io.write_byte(0x1D_u8)
          io.write_byte(((value >> 24) & 0xFF).to_u8)
          io.write_byte(((value >> 16) & 0xFF).to_u8)
          io.write_byte(((value >> 8) & 0xFF).to_u8)
          io.write_byte((value & 0xFF).to_u8)
        end

        # Encodes a real (non-integer) DICT operand using the BCD
        # nibble format (Adobe CFF spec § 4 table 5), the inverse of
        # `Dict#decode_real`. The shortest round-trip decimal string
        # is produced by `Float64#to_s` and translated nibble by
        # nibble : digits 0-9, `.` → 0xA, `E` → 0xB, `-` → 0xE,
        # end → 0xF.
        private def write_dict_real(io : IO::Memory, value : Float64) : Nil
          s = value.to_s
          nibbles = [] of UInt8
          s.each_char do |c|
            case c
            when '0'..'9' then nibbles << (c.ord - '0'.ord).to_u8
            when '.'      then nibbles << 0xA_u8
            when 'e', 'E' then nibbles << 0xB_u8
            when '-'      then nibbles << 0xE_u8
            when '+'      then nil # implicit positive exponent — skip
            else               raise "Subsetter : unexpected char #{c.inspect} in real operand #{s.inspect}"
            end
          end
          nibbles << 0xF_u8                      # end marker
          nibbles << 0xF_u8 if nibbles.size.odd? # pad to whole byte

          io.write_byte(0x1E_u8) # real number marker
          i = 0
          while i < nibbles.size
            io.write_byte(((nibbles[i] << 4) | nibbles[i + 1]).to_u8)
            i += 2
          end
        end

        private def write_dict_operand_compact(io : IO::Memory, value : Float64) : Nil
          unless value.finite? && value == value.to_i32.to_f64
            write_dict_real(io, value)
            return
          end
          v = value.to_i32
          case v
          when -107..107
            io.write_byte((v + 139).to_u8)
          when 108..1131
            d = v - 108
            io.write_byte((247 + (d >> 8)).to_u8)
            io.write_byte((d & 0xFF).to_u8)
          when -1131..-108
            d = -v - 108
            io.write_byte((251 + (d >> 8)).to_u8)
            io.write_byte((d & 0xFF).to_u8)
          when -32768..32767
            io.write_byte(0x1C_u8)
            io.write_byte(((v >> 8) & 0xFF).to_u8)
            io.write_byte((v & 0xFF).to_u8)
          else
            write_long_int(io, v)
          end
        end

        # ---- Verbatim section extractors ----

        private def extract_charset_bytes : Bytes
          start = @parser.top_dict[Parser::TOP_CHARSET]?.try(&.last.to_i32) || raise "Subsetter : missing /Charset"
          io = IO::Memory.new(@parser.data)
          io.pos = start
          format = io.read_byte.not_nil!
          num_glyphs = @parser.charstrings.entries.size
          n_entries = num_glyphs - 1 # GID 0 implicit
          extra = case format
                  when 0_u8 then n_entries * 2
                  when 1_u8 then walk_charset_range_size(io, n_entries, 3)
                  when 2_u8 then walk_charset_range_size(io, n_entries, 4)
                  else           raise "Subsetter : unsupported Charset format #{format}"
                  end
          @parser.data[start, 1 + extra]
        end

        private def walk_charset_range_size(io : IO::Memory, n : Int32, range_size : Int32) : Int32
          covered = 0
          consumed = 0
          while covered < n
            io.read_byte; io.read_byte # first (u16)
            n_left = if range_size == 3
                       io.read_byte.not_nil!.to_i32
                     else
                       (io.read_byte.not_nil!.to_i32 << 8) | io.read_byte.not_nil!.to_i32
                     end
            covered += 1 + n_left
            consumed += range_size
          end
          consumed
        end

        private def extract_fdselect_bytes : Bytes
          start = @parser.top_dict[Parser::TOP_FDSELECT].last.to_i32
          io = IO::Memory.new(@parser.data)
          io.pos = start
          format = io.read_byte.not_nil!
          num_glyphs = @parser.charstrings.entries.size
          extra = case format
                  when 0_u8
                    num_glyphs
                  when 3_u8
                    n_ranges = (io.read_byte.not_nil!.to_i32 << 8) | io.read_byte.not_nil!.to_i32
                    2 + (n_ranges * 3) + 2
                  else
                    raise "Subsetter : unsupported FDSelect format #{format}"
                  end
          @parser.data[start, 1 + extra]
        end
      end
    end
  end
end
