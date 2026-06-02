module PDF
  module Fonts
    module CFF
      # CFF parser (Adobe CFF spec). Reads the major sections of a
      # Compact Font Format payload into in-memory structures, without
      # modifying them. The result is consumed by `CFF::Subsetter`
      # (palier 0.6.3) to produce a reduced CFF payload.
      #
      # This is the *read-only* MVP — palier 0.6.1 of the J1+ work.
      # It does NOT interpret Type 2 charstring bytecode (palier
      # 0.6.2) and does NOT modify CFF data (palier 0.6.3).
      #
      # ## Usage
      #
      # ```
      # parser = PDF::Fonts::CFF::Parser.new(cff_bytes)
      # parser.charstrings.entries.size  # => number of glyphs
      # parser.cid_font?                 # => true if a CIDFont (CJK typical)
      # parser.global_subrs.entries.size # => global subr count
      # ```
      class Parser
        include TrueType::IOHelpers

        # Standard operators from the Top DICT we care about.
        TOP_CHARSTRINGS =   0x11
        TOP_PRIVATE     =   0x12
        TOP_CHARSET     =   0x0F
        TOP_ENCODING    =   0x10
        TOP_ROS         = 0x0C1E # CIDFont marker (registry, ordering, supplement)
        TOP_CIDCOUNT    = 0x0C22
        TOP_FDARRAY     = 0x0C24
        TOP_FDSELECT    = 0x0C25

        # Private DICT operators.
        PRIVATE_SUBRS = 0x13

        # Raw bytes of the entire CFF block (offsets in DICTs are
        # all relative to this).
        getter data : Bytes

        # Header info.
        getter major : Int32
        getter minor : Int32

        # Top-level INDEXes.
        getter name_index : Index
        getter top_dict_index : Index
        getter string_index : Index
        getter global_subrs : Index

        # Decoded Top DICT of the first (and usually only) font.
        getter top_dict : Hash(Int32, Array(Float64))

        # CharStrings INDEX (one entry per glyph, raw Type 2 bytecode).
        getter charstrings : Index

        # Private DICT of the font (for non-CID fonts). Empty if CID.
        getter private_dict : Hash(Int32, Array(Float64))

        # Local Subrs for the (non-CID) font. Empty INDEX if CID.
        getter local_subrs : Index

        # CIDFont per-FD Font DICTs and their Private DICTs / Local
        # Subrs. Empty arrays for non-CID fonts.
        getter fd_array : Array(Hash(Int32, Array(Float64)))
        getter fd_privates : Array(Hash(Int32, Array(Float64)))
        getter fd_local_subrs : Array(Index)

        # FDSelect mapping GID → FD index (CID only). Empty hash
        # otherwise.
        getter fd_select : Hash(Int32, Int32)

        def initialize(@data : Bytes)
          io = IO::Memory.new(@data)

          # --- Header ---
          @major = read_uint8(io).to_i32
          @minor = read_uint8(io).to_i32
          hdr_size = read_uint8(io).to_i32
          read_uint8(io) # off_size (header-level, only used for absolute offsets in legacy headers)
          io.pos = hdr_size

          # --- Top-level INDEXes ---
          @name_index = Index.read(io)
          @top_dict_index = Index.read(io)
          @string_index = Index.read(io)
          @global_subrs = Index.read(io)

          # --- Top DICT of the first font ---
          @top_dict = Dict.parse(@top_dict_index.entries[0])

          # --- CharStrings ---
          cs_offset = required_offset(@top_dict, TOP_CHARSTRINGS, "CharStrings")
          io.pos = cs_offset
          @charstrings = Index.read(io)

          # --- Private DICT / Local Subrs (non-CID font) ---
          @private_dict = {} of Int32 => Array(Float64)
          @local_subrs = Index.new([] of Bytes, 0)
          @fd_array = [] of Hash(Int32, Array(Float64))
          @fd_privates = [] of Hash(Int32, Array(Float64))
          @fd_local_subrs = [] of Index
          @fd_select = {} of Int32 => Int32

          if cid_font?
            parse_cid_font(io)
          else
            parse_non_cid_font(io)
          end
        end

        # True if this CFF carries a CIDFont (CJK fonts almost always
        # are). Detected by the presence of `/ROS` in the Top DICT.
        def cid_font? : Bool
          @top_dict.has_key?(TOP_ROS)
        end

        # Returns the value of a Top DICT operator interpreted as an
        # integer offset. Raises if missing.
        private def required_offset(dict : Hash(Int32, Array(Float64)), op : Int32, name : String) : Int32
          values = dict[op]? || raise "CFF Top DICT : missing /#{name} (operator 0x#{op.to_s(16)})"
          values.last.to_i32
        end

        private def parse_non_cid_font(io : IO) : Nil
          priv = @top_dict[TOP_PRIVATE]? || raise "CFF Top DICT : missing /Private offset"
          size = priv[0].to_i32
          offset = priv[1].to_i32

          io.pos = offset
          private_bytes = Bytes.new(size)
          io.read_fully(private_bytes)
          @private_dict = Dict.parse(private_bytes)

          # The Subrs offset is relative to the start of the Private
          # DICT, not to the start of the CFF data.
          if subrs = @private_dict[PRIVATE_SUBRS]?
            io.pos = offset + subrs.last.to_i32
            @local_subrs = Index.read(io)
          end
        end

        private def parse_cid_font(io : IO) : Nil
          # FDArray : an INDEX of per-FD Font DICTs.
          fd_array_offset = required_offset(@top_dict, TOP_FDARRAY, "FDArray")
          io.pos = fd_array_offset
          fd_index = Index.read(io)
          @fd_array = fd_index.entries.map { |e| Dict.parse(e) }

          # For each Font DICT, follow its /Private to read the
          # Private DICT and Local Subrs.
          @fd_array.each do |fd|
            priv = fd[TOP_PRIVATE]? || raise "CFF CIDFont : Font DICT missing /Private"
            size = priv[0].to_i32
            offset = priv[1].to_i32
            io.pos = offset
            private_bytes = Bytes.new(size)
            io.read_fully(private_bytes)
            private_dict = Dict.parse(private_bytes)
            @fd_privates << private_dict

            if subrs = private_dict[PRIVATE_SUBRS]?
              io.pos = offset + subrs.last.to_i32
              @fd_local_subrs << Index.read(io)
            else
              @fd_local_subrs << Index.new([] of Bytes, 0)
            end
          end

          # FDSelect : GID → FD index mapping.
          fds_offset = required_offset(@top_dict, TOP_FDSELECT, "FDSelect")
          io.pos = fds_offset
          @fd_select = parse_fd_select(io, @charstrings.entries.size)
        end

        # Parses an FDSelect (Adobe CFF spec § 19). Supports format 0
        # (one byte per glyph) and format 3 (range-based).
        private def parse_fd_select(io : IO, num_glyphs : Int32) : Hash(Int32, Int32)
          format = read_uint8(io).to_i32
          result = {} of Int32 => Int32
          case format
          when 0
            num_glyphs.times do |gid|
              result[gid] = read_uint8(io).to_i32
            end
          when 3
            n_ranges = read_uint16(io).to_i32
            ranges = Array(Tuple(Int32, Int32)).new(n_ranges)
            n_ranges.times do
              first = read_uint16(io).to_i32
              fd = read_uint8(io).to_i32
              ranges << {first, fd}
            end
            sentinel = read_uint16(io).to_i32
            ranges.each_with_index do |(first, fd), i|
              upto = (i + 1 < ranges.size) ? ranges[i + 1][0] : sentinel
              (first...upto).each { |gid| result[gid] = fd }
            end
          else
            raise "CFF FDSelect : unsupported format #{format}"
          end
          result
        end
      end
    end
  end
end
