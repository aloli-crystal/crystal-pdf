require "../../spec_helper"

KERNING_SPEC_FONT_PATH = "spec/fixtures/fonts/DejaVuSans.ttf"

describe PDF::Fonts::TrueTypeFont do
  describe "#has_kerning?" do
    it "reports whether the font has kerning data" do
      font = PDF::Fonts::TrueTypeFont.load(KERNING_SPEC_FONT_PATH)
      font.has_kerning?.should be_a(Bool)
    end
  end

  describe "#kern_pair" do
    it "returns an Int32 for any character pair" do
      font = PDF::Fonts::TrueTypeFont.load(KERNING_SPEC_FONT_PATH)
      result = font.kern_pair('A', 'V')
      result.should be_a(Int32)
    end
  end

  describe "#text_with_kerning" do
    it "returns an array with at least one element for any text" do
      font = PDF::Fonts::TrueTypeFont.load(KERNING_SPEC_FONT_PATH)
      result = font.text_with_kerning("Hello")
      result.should_not be_empty
    end

    it "returns the text unchanged when no kerning is available" do
      font = PDF::Fonts::TrueTypeFont.load(KERNING_SPEC_FONT_PATH)
      unless font.has_kerning?
        result = font.text_with_kerning("AV")
        result.size.should eq(1)
        result[0].should eq("AV")
      end
    end

    it "returns only String and Int32 elements" do
      font = PDF::Fonts::TrueTypeFont.load(KERNING_SPEC_FONT_PATH)
      result = font.text_with_kerning("AVATAR")
      result.each do |element|
        (element.is_a?(String) || element.is_a?(Int32)).should be_true
      end
    end
  end

  describe "#encode_char" do
    it "returns a hex-encoded character" do
      font = PDF::Fonts::TrueTypeFont.load(KERNING_SPEC_FONT_PATH)
      result = font.encode_char('A')
      result.should start_with("<")
      result.should end_with(">")
      result.size.should eq(6) # <XXXX>
    end
  end
end
