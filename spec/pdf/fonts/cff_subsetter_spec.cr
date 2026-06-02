require "../../spec_helper"

describe PDF::Fonts::CFF::IndexWriter do
  it "writes an empty INDEX as 2 bytes (count = 0)" do
    bytes = PDF::Fonts::CFF::IndexWriter.write([] of Bytes)
    bytes.should eq(Bytes[0x00, 0x00])
  end

  it "round-trips a small INDEX through the reader" do
    entries = [Bytes[0xAB, 0xCD], Bytes[0xEF], Bytes[0x01, 0x02, 0x03]]
    written = PDF::Fonts::CFF::IndexWriter.write(entries)
    io = IO::Memory.new(written)
    idx = PDF::Fonts::CFF::Index.read(io)
    idx.entries.size.should eq(3)
    idx.entries[0].should eq(Bytes[0xAB, 0xCD])
    idx.entries[1].should eq(Bytes[0xEF])
    idx.entries[2].should eq(Bytes[0x01, 0x02, 0x03])
  end

  it "round-trips an INDEX whose data forces a 2-byte offSize" do
    # Build entries totalling > 255 bytes so the writer picks
    # offSize = 2, then read it back.
    big = Bytes.new(300, 0x42_u8)
    entries = [big, Bytes[0x99]]
    written = PDF::Fonts::CFF::IndexWriter.write(entries)
    io = IO::Memory.new(written)
    idx = PDF::Fonts::CFF::Index.read(io)
    idx.entries.size.should eq(2)
    idx.entries[0].size.should eq(300)
    idx.entries[1].should eq(Bytes[0x99])
  end
end

# The Subsetter integration test needs a real CIDFont. We use a
# system Noto CJK OTF if present ; otherwise the test is pending.
{% if flag?(:darwin) %}
  describe PDF::Fonts::CFF::Subsetter do
    noto_candidates = [
      "/Users/philippe/zold-mbp-pne/github-prod/ttfunk--prawnpdf/spec/fonts/NotoSansCJKsc-Thin.otf",
      "/Users/philippe/Library/Caches/noto-cjk/NotoSansCJKsc-Regular.otf",
    ]

    it "collapses unused glyphs and produces a re-parseable CID CFF" do
      otf = noto_candidates.find { |p| File.exists?(p) }
      pending! "no Noto CJK OTF available" unless otf

      tt = PDF::Fonts::TrueType::Parser.parse(otf)
      cff_bytes = tt.table_data("CFF ").not_nil!
      cff = PDF::Fonts::CFF::Parser.new(cff_bytes)

      kept = Set(Int32).new
      (0...200).each { |g| kept << g }
      subset = PDF::Fonts::CFF::Subsetter.new(cff, kept).subset

      # Big size reduction (kept charstrings + verbatim subrs).
      subset.size.should be < cff_bytes.size // 5

      # Re-parse the subset : structure must survive.
      re = PDF::Fonts::CFF::Parser.new(subset)
      re.cid_font?.should be_true
      re.charstrings.entries.size.should eq(cff.charstrings.entries.size)

      # A kept glyph keeps its exact bytes.
      re.charstrings.entries[100].should eq(cff.charstrings.entries[100])
      # A dropped glyph collapses to a single endchar.
      re.charstrings.entries[60_000].should eq(Bytes[14_u8]) if cff.charstrings.entries.size > 60_000

      # Every kept glyph re-analyses without error in the subset.
      analyser = PDF::Fonts::CFF::Type2Analyser.new(re)
      kept.each { |gid| analyser.analyse(gid) }
    end

    it "always keeps GID 0 (.notdef) even when not requested" do
      otf = noto_candidates.find { |p| File.exists?(p) }
      pending! "no Noto CJK OTF available" unless otf

      tt = PDF::Fonts::TrueType::Parser.parse(otf)
      cff = PDF::Fonts::CFF::Parser.new(tt.table_data("CFF ").not_nil!)
      subset = PDF::Fonts::CFF::Subsetter.new(cff, [10, 20, 30]).subset
      re = PDF::Fonts::CFF::Parser.new(subset)
      # GID 0 retained its original (non-endchar) charstring.
      re.charstrings.entries[0].should eq(cff.charstrings.entries[0])
    end
  end
{% end %}
