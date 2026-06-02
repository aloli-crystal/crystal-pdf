require "../../spec_helper"

# Helper : a Parser whose internals point at the supplied bytecode
# and subrs, without going through actual CFF blob parsing. Declared
# at top level because Crystal does not allow `class` declarations
# inside `describe` blocks.
class FakeCFFParser < PDF::Fonts::CFF::Parser
  def initialize(charstring : Bytes, global_subrs : Array(Bytes), local_subrs : Array(Bytes))
    @data = Bytes.empty
    @major = 1
    @minor = 0
    @name_index = PDF::Fonts::CFF::Index.new([] of Bytes, 0)
    @top_dict_index = PDF::Fonts::CFF::Index.new([] of Bytes, 0)
    @string_index = PDF::Fonts::CFF::Index.new([] of Bytes, 0)
    @global_subrs = PDF::Fonts::CFF::Index.new(global_subrs, 0)
    @top_dict = {} of Int32 => Array(Float64)
    @charstrings = PDF::Fonts::CFF::Index.new([charstring], 0)
    @private_dict = {} of Int32 => Array(Float64)
    @local_subrs = PDF::Fonts::CFF::Index.new(local_subrs, 0)
    @fd_array = [] of Hash(Int32, Array(Float64))
    @fd_privates = [] of Hash(Int32, Array(Float64))
    @fd_local_subrs = [] of PDF::Fonts::CFF::Index
    @fd_select = {} of Int32 => Int32
  end
end

describe PDF::Fonts::CFF::Type2Analyser do
  describe ".subr_bias" do
    it "returns 107 below 1240 subrs" do
      PDF::Fonts::CFF::Type2Analyser.subr_bias(0).should eq(107)
      PDF::Fonts::CFF::Type2Analyser.subr_bias(1239).should eq(107)
    end

    it "returns 1131 between 1240 and 33899 subrs" do
      PDF::Fonts::CFF::Type2Analyser.subr_bias(1240).should eq(1131)
      PDF::Fonts::CFF::Type2Analyser.subr_bias(33899).should eq(1131)
    end

    it "returns 32768 at and above 33900 subrs" do
      PDF::Fonts::CFF::Type2Analyser.subr_bias(33900).should eq(32768)
      PDF::Fonts::CFF::Type2Analyser.subr_bias(100_000).should eq(32768)
    end
  end

  describe "#analyse" do
    it "returns empty sets for a charstring with no subr calls (just endchar)" do
      # endchar = opcode 14
      parser = FakeCFFParser.new(Bytes[14], [] of Bytes, [] of Bytes)
      analyser = PDF::Fonts::CFF::Type2Analyser.new(parser)
      local, global = analyser.analyse(0)
      local.should be_empty
      global.should be_empty
    end

    it "traces a callsubr (opcode 10) — local subr 0 at bias 107" do
      # 1 local subr exists ; bias = 107. To call subr index 0
      # (after bias), the charstring must push -107 then 10.
      # -107 encoded as 1-byte: 32..246 means (b0-139); so -107 → 32.
      # The subr itself ends with `return` (opcode 11).
      subr = Bytes[11]
      charstring = Bytes[32_u8, 10_u8, 14_u8] # push -107, callsubr, endchar
      parser = FakeCFFParser.new(charstring, [] of Bytes, [subr])
      analyser = PDF::Fonts::CFF::Type2Analyser.new(parser)
      local, global = analyser.analyse(0)
      local.should eq(Set{0})
      global.should be_empty
    end

    it "traces a callgsubr (opcode 29)" do
      gsubr = Bytes[11]
      charstring = Bytes[32_u8, 29_u8, 14_u8] # push -107, callgsubr, endchar
      parser = FakeCFFParser.new(charstring, [gsubr], [] of Bytes)
      analyser = PDF::Fonts::CFF::Type2Analyser.new(parser)
      local, global = analyser.analyse(0)
      local.should be_empty
      global.should eq(Set{0})
    end

    it "traces nested subrs (callgsubr from inside a callsubr)" do
      # Local subr 0 calls global subr 0, then returns.
      # Charstring : push -107, callsubr (10), endchar (14).
      # Local subr 0 : push -107, callgsubr (29), return (11).
      local_subr = Bytes[32_u8, 29_u8, 11_u8]
      gsubr = Bytes[11_u8]
      charstring = Bytes[32_u8, 10_u8, 14_u8]
      parser = FakeCFFParser.new(charstring, [gsubr], [local_subr])
      analyser = PDF::Fonts::CFF::Type2Analyser.new(parser)
      local, global = analyser.analyse(0)
      local.should eq(Set{0})
      global.should eq(Set{0})
    end

    it "ignores callsubr with an index that resolves outside the subr array" do
      # No subrs at all : bias = 107, but no subrs means any call
      # is out-of-range and silently ignored.
      charstring = Bytes[32_u8, 10_u8, 14_u8]
      parser = FakeCFFParser.new(charstring, [] of Bytes, [] of Bytes)
      analyser = PDF::Fonts::CFF::Type2Analyser.new(parser)
      local, global = analyser.analyse(0)
      local.should be_empty
      global.should be_empty
    end

    it "deduplicates repeated calls to the same subr" do
      subr = Bytes[11_u8]
      # Call subr 0 twice in the same charstring.
      charstring = Bytes[32_u8, 10_u8, 32_u8, 10_u8, 14_u8]
      parser = FakeCFFParser.new(charstring, [] of Bytes, [subr])
      analyser = PDF::Fonts::CFF::Type2Analyser.new(parser)
      local, _ = analyser.analyse(0)
      local.should eq(Set{0}) # Set ignores duplicates
    end

    it "skips past a hintmask bitmask (variable-length operand)" do
      # 2 stems declared via hstem (3 stems → 1 byte mask).
      # opcodes : 32, 32, 32, 32, hstem(1), hintmask(19), <1 byte mask>, endchar
      # 4 operands = 2 stem pairs, hintmask follows.
      bs = Bytes[32_u8, 32_u8, 32_u8, 32_u8, 1_u8, 19_u8, 0xFF_u8, 14_u8]
      parser = FakeCFFParser.new(bs, [] of Bytes, [] of Bytes)
      analyser = PDF::Fonts::CFF::Type2Analyser.new(parser)
      # No subrs, but the walk must traverse all bytes without
      # erroring on the bitmask byte.
      local, global = analyser.analyse(0)
      local.should be_empty
      global.should be_empty
    end
  end
end
