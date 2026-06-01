require "../../spec_helper"

describe PDF::Fonts::CFF::Index do
  it "reads an empty INDEX (count = 0, 2 bytes total)" do
    io = IO::Memory.new(Bytes[0x00, 0x00])
    idx = PDF::Fonts::CFF::Index.read(io)
    idx.entries.should be_empty
    idx.size.should eq(2)
  end

  it "reads a small INDEX with offSize = 1" do
    # count=2, offSize=1, offsets=[1,3,5], data=[0xAB,0xCD,0xEF,0x10]
    # entry 0 = bytes[0..1] = {0xAB, 0xCD}
    # entry 1 = bytes[2..3] = {0xEF, 0x10}
    bytes = Bytes[0x00, 0x02, 0x01, 0x01, 0x03, 0x05, 0xAB, 0xCD, 0xEF, 0x10]
    io = IO::Memory.new(bytes)
    idx = PDF::Fonts::CFF::Index.read(io)
    idx.entries.size.should eq(2)
    idx.entries[0].should eq(Bytes[0xAB, 0xCD])
    idx.entries[1].should eq(Bytes[0xEF, 0x10])
  end

  it "reads an INDEX with offSize = 2" do
    # count=1, offSize=2, offsets=[0x0001, 0x0003], data=[0xFF, 0xEE]
    bytes = Bytes[0x00, 0x01, 0x02, 0x00, 0x01, 0x00, 0x03, 0xFF, 0xEE]
    io = IO::Memory.new(bytes)
    idx = PDF::Fonts::CFF::Index.read(io)
    idx.entries.size.should eq(1)
    idx.entries[0].should eq(Bytes[0xFF, 0xEE])
  end
end

describe PDF::Fonts::CFF::Dict do
  it "decodes a single short integer operand and its operator" do
    # Operand 100 (encoded as 100+139=239 → 0xEF), operator 0 (version)
    bytes = Bytes[0xEF, 0x00]
    result = PDF::Fonts::CFF::Dict.parse(bytes)
    result.has_key?(0).should be_true
    result[0].should eq([100.0])
  end

  it "decodes a 2-byte 'positive' integer (108..1131)" do
    # 247..250 + next byte : value = (b0-247)*256 + b1 + 108
    # 0xF7 = 247, next byte 0 → value = 0*256 + 0 + 108 = 108
    bytes = Bytes[0xF7, 0x00, 0x00]
    result = PDF::Fonts::CFF::Dict.parse(bytes)
    result[0].should eq([108.0])
  end

  it "decodes a 2-byte 'negative' integer (-1131..-108)" do
    # 251..254 + next byte : value = -(b0-251)*256 - b1 - 108
    # 0xFB = 251, next byte 0 → -108
    bytes = Bytes[0xFB, 0x00, 0x00]
    result = PDF::Fonts::CFF::Dict.parse(bytes)
    result[0].should eq([-108.0])
  end

  it "decodes a 2-byte escape operator (0x0C xx)" do
    # operand 5 (b0=5+139=144=0x90), 2-byte operator 0x0C 0x1E (ROS marker)
    bytes = Bytes[0x90, 0x0C, 0x1E]
    result = PDF::Fonts::CFF::Dict.parse(bytes)
    result.has_key?(0x0C1E).should be_true
    result[0x0C1E].should eq([5.0])
  end

  it "decodes multiple operands before an operator" do
    # operands 1, 2, 3 then operator 21 (Private)
    bytes = Bytes[0x8C, 0x8D, 0x8E, 0x15]
    result = PDF::Fonts::CFF::Dict.parse(bytes)
    result[21].should eq([1.0, 2.0, 3.0])
  end
end

# Optional integration test using a system OTF on macOS. Skipped if
# the file is not present (Linux CI for example).
{% if flag?(:darwin) %}
  describe "PDF::Fonts::CFF::Parser (integration via system OTF)" do
    it "parses /System/Library/Fonts/LastResort.otf when available" do
      otf_path = "/System/Library/Fonts/LastResort.otf"
      pending! "system font not found" unless File.exists?(otf_path)

      # Extract the 'CFF ' table via the existing TrueType parser.
      tt = PDF::Fonts::TrueType::Parser.parse(otf_path)
      tt.cff?.should be_true

      cff_bytes = tt.table_data("CFF ").not_nil!
      parser = PDF::Fonts::CFF::Parser.new(cff_bytes)

      # Successfully parsed — at least one glyph (the .notdef).
      parser.charstrings.entries.size.should be > 0
      # If the font is CID, FDArray must be non-empty. If not,
      # the non-CID private dict must be populated.
      if parser.cid_font?
        parser.fd_array.size.should be > 0
      else
        parser.private_dict.size.should be > 0
      end
    end
  end
{% end %}
