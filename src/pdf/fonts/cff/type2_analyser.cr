module PDF
  module Fonts
    module CFF
      # Type 2 charstring analyser (Adobe Type 2 Charstring Format,
      # Tech Note #5177). Walks the bytecode of a glyph without
      # rendering it, tracking which local and global subroutines
      # are referenced — transitively, by following `callsubr` (10)
      # and `callgsubr` (29) into their target subrs.
      #
      # This is palier 0.6.2 of the CFF subsetting trajectory. The
      # output (`Set(Int32)` of local and global subr indices) feeds
      # palier 0.6.3 (subsetter), which uses it to compute the
      # transitive closure of subrs to retain when subsetting.
      #
      # ## Subroutine bias
      #
      # Type 2 charstrings reference subrs by a *biased* index — the
      # actual subr index is `raw_index + bias`, where bias depends
      # on the subr count (Tech Note #5176 § 4.7) :
      #
      # * `count < 1240`   → bias = 107
      # * `count < 33900`  → bias = 1131
      # * `count ≥ 33900`  → bias = 32768
      #
      # Negative or out-of-range subrs after bias resolution are
      # silently ignored — they indicate a malformed charstring,
      # which we tolerate at analysis time and surface later if
      # subsetting fails.
      #
      # ## Hint-mask peculiarity
      #
      # `hintmask` (19) and `cntrmask` (20) are followed by a
      # variable-length bitmask of `ceil(num_stems / 8)` bytes, where
      # `num_stems` is the total of all stems declared so far via
      # `hstem`, `vstem`, `hstemhm`, `vstemhm`, plus any *implicit*
      # vstems that the spec says are deduced from operands left on
      # the stack when `hintmask`/`cntrmask` is encountered. The
      # walker tracks this to advance past the mask correctly ;
      # getting it wrong would mis-parse all subsequent bytes.
      class Type2Analyser
        # Maximum recursion depth across nested subroutine calls.
        # The Type 2 spec allows up to 10 levels ; we cap at 11 to
        # surface unexpected recursion as an error rather than blow
        # the call stack.
        MAX_DEPTH = 11

        getter parser : Parser

        def initialize(@parser : Parser)
        end

        # Returns the sets of local and global subroutines referenced
        # — transitively — by glyph `gid`. For CIDFonts the local
        # subr set is selected from the FD that owns the glyph
        # (via `FDSelect`).
        def analyse(gid : Int32) : Tuple(Set(Int32), Set(Int32))
          unless 0 <= gid && gid < @parser.charstrings.entries.size
            raise ArgumentError.new("GID #{gid} out of range (charstrings : #{@parser.charstrings.entries.size})")
          end

          local_subrs = local_subrs_for(gid)
          local_used = Set(Int32).new
          global_used = Set(Int32).new
          stack = [] of Float64

          state = WalkState.new
          walk(
            bytes: @parser.charstrings.entries[gid],
            local_subrs: local_subrs,
            local_used: local_used,
            global_used: global_used,
            stack: stack,
            state: state,
            depth: 0,
          )

          {local_used, global_used}
        end

        # Mutable state that must survive across nested subr calls —
        # only `num_stems` so far, but kept as an object to allow
        # adding more fields cleanly.
        private class WalkState
          property num_stems : Int32 = 0
        end

        # Returns the Local Subr INDEX that applies to `gid` —
        # picks the right FD for CIDFonts, returns the single
        # non-CID set otherwise.
        def local_subrs_for(gid : Int32) : Index
          if @parser.cid_font?
            fd = @parser.fd_select[gid]? || raise "CIDFont : no FDSelect entry for GID #{gid}"
            @parser.fd_local_subrs[fd]
          else
            @parser.local_subrs
          end
        end

        # Computes the subr bias (Tech Note #5176 § 4.7).
        def self.subr_bias(count : Int32) : Int32
          return 107 if count < 1240
          return 1131 if count < 33900
          32768
        end

        # Walks the bytecode of one charstring (a glyph's, or a
        # subr's) and accumulates referenced subr indices into the
        # `*_used` sets.
        #
        # `stack` is shared across the recursive call into a subr,
        # mirroring Type 2 semantics : a subr can consume and push
        # operands left there by its caller.
        private def walk(
          bytes : Bytes,
          local_subrs : Index,
          local_used : Set(Int32),
          global_used : Set(Int32),
          stack : Array(Float64),
          state : WalkState,
          depth : Int32,
        ) : Nil
          raise "Type 2 walker : recursion depth #{depth} exceeded MAX_DEPTH=#{MAX_DEPTH}" if depth > MAX_DEPTH

          i = 0
          while i < bytes.size
            b0 = bytes[i]
            case b0
            when 28
              # 2-byte signed int
              raise "Type 2 : truncated 16-bit int at offset #{i}" if i + 2 >= bytes.size
              v = ((bytes[i + 1].to_i32 << 8) | bytes[i + 2].to_i32).to_i16!.to_f64
              stack << v
              i += 3
            when 32..246
              stack << (b0.to_i32 - 139).to_f64
              i += 1
            when 247..250
              raise "Type 2 : truncated pos int at offset #{i}" if i + 1 >= bytes.size
              stack << (((b0.to_i32 - 247) * 256) + bytes[i + 1].to_i32 + 108).to_f64
              i += 2
            when 251..254
              raise "Type 2 : truncated neg int at offset #{i}" if i + 1 >= bytes.size
              stack << (-((b0.to_i32 - 251) * 256) - bytes[i + 1].to_i32 - 108).to_f64
              i += 2
            when 255
              # 16.16 fixed-point
              raise "Type 2 : truncated fixed at offset #{i}" if i + 4 >= bytes.size
              v = ((bytes[i + 1].to_i32 << 24) | (bytes[i + 2].to_i32 << 16) |
                   (bytes[i + 3].to_i32 << 8) | bytes[i + 4].to_i32).to_i32
              stack << v.to_f64 / 65536.0
              i += 5
            when 10
              # callsubr
              raw_idx = stack.pop.to_i32
              n = local_subrs.entries.size
              subr_idx = raw_idx + Type2Analyser.subr_bias(n)
              if 0 <= subr_idx && subr_idx < n
                first_visit = local_used.add?(subr_idx)
                if first_visit
                  walk(local_subrs.entries[subr_idx], local_subrs, local_used, global_used, stack, state, depth + 1)
                end
              end
              i += 1
            when 29
              # callgsubr
              raw_idx = stack.pop.to_i32
              gsubrs = @parser.global_subrs
              n = gsubrs.entries.size
              subr_idx = raw_idx + Type2Analyser.subr_bias(n)
              if 0 <= subr_idx && subr_idx < n
                first_visit = global_used.add?(subr_idx)
                if first_visit
                  walk(gsubrs.entries[subr_idx], local_subrs, local_used, global_used, stack, state, depth + 1)
                end
              end
              i += 1
            when 11
              # return — exit the current subr, leave the stack alone
              return
            when 14
              # endchar — terminates the charstring
              return
            when 1, 3, 18, 23
              # hstem, vstem, hstemhm, vstemhm — count stem pairs
              # (each pair = 2 operands). The stem counter is shared
              # across nested subrs (Type 2 hintmask refers to all
              # stems declared in the glyph so far).
              state.num_stems += stack.size // 2
              stack.clear
              i += 1
            when 19, 20
              # hintmask, cntrmask — implicit vstem from leftover
              # operands, then the mask follows the operator.
              state.num_stems += stack.size // 2
              stack.clear
              mask_size = (state.num_stems + 7) // 8
              raise "Type 2 : truncated #{b0 == 19 ? "hintmask" : "cntrmask"} at offset #{i}" if i + mask_size >= bytes.size
              i += 1 + mask_size
            when 12
              # 2-byte (escape) operator — math/logic. The Type 2
              # math ops (sub, add, mul, div, etc.) leave one value
              # on the stack ; we conservatively clear since this is
              # rare in real fonts and not needed for subr tracing.
              raise "Type 2 : truncated escape operator at offset #{i}" if i + 1 >= bytes.size
              stack.clear
              i += 2
            when 0, 2, 4, 5, 6, 7, 8, 9, 13, 15, 16, 17, 21, 22, 24, 25, 26, 27, 30, 31
              # All other 1-byte path-painting operators — they
              # consume the entire current operand stack.
              stack.clear
              i += 1
            else
              raise "Type 2 : unknown opcode 0x#{b0.to_s(16)} at offset #{i}"
            end
          end
        end
      end
    end
  end
end
