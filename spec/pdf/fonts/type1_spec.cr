require "../../spec_helper"

describe PDF::Fonts::Type1 do
  describe "initialization" do
    it "creates font with valid name" do
      font = PDF::Fonts::Type1.new("Helvetica")
      font.name.should eq("Helvetica")
    end

    it "raises for invalid font name" do
      expect_raises(ArgumentError, /Unknown Type1 font/) do
        PDF::Fonts::Type1.new("InvalidFont")
      end
    end

    it "accepts all standard fonts" do
      PDF::Fonts::Type1::STANDARD_FONTS.each do |name|
        font = PDF::Fonts::Type1.new(name)
        font.name.should eq(name)
      end
    end
  end

  describe "#to_dictionary" do
    it "creates proper font dictionary for Helvetica" do
      font = PDF::Fonts::Type1.new("Helvetica")
      dict = font.to_dictionary

      dict["Type"].should eq(PDF::Objects::Name::FONT)
      dict["Subtype"].should eq(PDF::Objects::Name.new("Type1"))
      dict["BaseFont"].should eq(PDF::Objects::Name.new("Helvetica"))
      dict["Encoding"].should eq(PDF::Objects::Name.new("WinAnsiEncoding"))
    end

    it "omits encoding for Symbol font" do
      font = PDF::Fonts::Type1.new("Symbol")
      dict = font.to_dictionary

      dict["BaseFont"].should eq(PDF::Objects::Name.new("Symbol"))
      dict["Encoding"]?.should be_nil
    end

    it "omits encoding for ZapfDingbats font" do
      font = PDF::Fonts::Type1.new("ZapfDingbats")
      dict = font.to_dictionary

      dict["Encoding"]?.should be_nil
    end
  end

  describe "#glyph_width" do
    it "returns correct width for Helvetica 'A'" do
      font = PDF::Fonts::Type1.new("Helvetica")
      font.glyph_width('A').should eq(667)
    end

    it "returns correct width for Helvetica space" do
      font = PDF::Fonts::Type1.new("Helvetica")
      font.glyph_width(' ').should eq(278)
    end

    it "returns correct width for Courier (monospaced)" do
      font = PDF::Fonts::Type1.new("Courier")
      font.glyph_width('A').should eq(600)
      font.glyph_width('i').should eq(600)
      font.glyph_width('W').should eq(600)
    end

    it "returns zero width for characters outside WinAnsiEncoding" do
      font = PDF::Fonts::Type1.new("Helvetica")
      # Character outside WinAnsi range (null, CJK, etc.)
      font.glyph_width('\u0000').should eq(0)
      font.glyph_width('\u4E2D').should eq(0) # Chinese character
    end

    it "returns correct width for accented Latin characters" do
      font = PDF::Fonts::Type1.new("Helvetica")
      # é (U+00E9) maps to WinAnsi 0xE9 — should have width 556 (same as 'e')
      font.glyph_width('é').should eq(556)
      # à (U+00E0) maps to WinAnsi 0xE0
      font.glyph_width('à').should eq(556)
      # ç (U+00E7) maps to WinAnsi 0xE7
      font.glyph_width('ç').should eq(500)
    end

    it "returns correct width for WinAnsi special characters" do
      font = PDF::Fonts::Type1.new("Helvetica")
      # Em dash U+2014 → WinAnsi 0x97
      font.glyph_width('\u2014').should eq(1000)
      # Euro sign U+20AC → WinAnsi 0x80
      font.glyph_width('\u20AC').should eq(556)
      # Bullet U+2022 → WinAnsi 0x95
      font.glyph_width('\u2022').should eq(350)
    end
  end

  describe "#encode_text" do
    it "encodes ASCII text unchanged" do
      font = PDF::Fonts::Type1.new("Helvetica")
      bytes = font.encode_text("Hello")
      bytes.should eq("Hello".to_slice)
    end

    it "encodes French accented characters to WinAnsi" do
      font = PDF::Fonts::Type1.new("Helvetica")
      bytes = font.encode_text("Spécifications")
      # é (U+00E9) should become byte 0xE9
      bytes[2].should eq(0xE9_u8)
      bytes.size.should eq(14) # Same number of characters, but single bytes
    end

    it "encodes em dash to WinAnsi" do
      font = PDF::Fonts::Type1.new("Helvetica")
      bytes = font.encode_text("A\u2014B") # A—B
      bytes[0].should eq(0x41_u8)          # A
      bytes[1].should eq(0x97_u8)          # em dash in WinAnsi
      bytes[2].should eq(0x42_u8)          # B
    end

    it "encodes smart quotes and bullets" do
      font = PDF::Fonts::Type1.new("Helvetica")
      bytes = font.encode_text("\u201Ctest\u201D") # "test"
      bytes[0].should eq(0x93_u8)                  # left double quote
      bytes[5].should eq(0x94_u8)                  # right double quote
    end

    it "replaces unmappable characters with ?" do
      font = PDF::Fonts::Type1.new("Helvetica")
      bytes = font.encode_text("A\u4E2DB") # Chinese character
      bytes[1].should eq(0x3F_u8)          # ?
    end

    it "encodes euro sign" do
      font = PDF::Fonts::Type1.new("Helvetica")
      bytes = font.encode_text("\u20AC100")
      bytes[0].should eq(0x80_u8) # Euro sign in WinAnsi
    end
  end

  describe "#string_width" do
    it "calculates width of string at given size" do
      font = PDF::Fonts::Type1.new("Helvetica")
      # "A" = 667 units, at 12pt: 667 * 12 / 1000 = 8.004
      width = font.string_width("A", 12.0)
      width.should be_close(8.004, 0.001)
    end

    it "calculates width of multi-character string" do
      font = PDF::Fonts::Type1.new("Helvetica")
      # "AB" = 667 + 667 = 1334 units, at 10pt: 13.34
      width = font.string_width("AB", 10.0)
      width.should be_close(13.34, 0.01)
    end

    it "correctly measures French accented text" do
      font = PDF::Fonts::Type1.new("Helvetica")
      # "é" has same width as "e" (556) in Helvetica
      width_e = font.string_width("e", 12.0)
      width_eacute = font.string_width("é", 12.0)
      width_e.should eq(width_eacute)
    end

    it "correctly measures text with em dashes" do
      font = PDF::Fonts::Type1.new("Helvetica")
      # Em dash is 1000 units wide in Helvetica
      width = font.string_width("\u2014", 10.0)
      width.should be_close(10.0, 0.01)
    end
  end
end
