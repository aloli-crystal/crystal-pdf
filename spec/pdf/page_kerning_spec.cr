require "../spec_helper"

KERNING_PAGE_FONT_PATH = "spec/fixtures/fonts/DejaVuSans.ttf"

describe "Page kerning" do
  describe "#text_kerned" do
    it "renders text with kerning using a TrueType font" do
      doc = PDF::Document.new
      font = doc.load_font(KERNING_PAGE_FONT_PATH)

      doc.page do |page|
        page.font font, size: 24
        page.text_kerned "AVATAR", at: {72, 720}
      end

      bytes = doc.to_slice
      TestHelpers.valid_pdf_header?(bytes).should be_true
      TestHelpers.valid_pdf_trailer?(bytes).should be_true
    end

    it "falls back to normal text for Type1 fonts" do
      doc = PDF::Document.new

      doc.page do |page|
        page.font "Helvetica", size: 12
        page.text_kerned "Hello", at: {72, 720}
      end

      bytes = doc.to_slice
      TestHelpers.valid_pdf_header?(bytes).should be_true
    end

    it "renders correctly even without kerning data in font" do
      doc = PDF::Document.new
      font = doc.load_font(KERNING_PAGE_FONT_PATH)

      doc.page do |page|
        page.font font, size: 12
        page.text_kerned "Simple text", at: {72, 720}
      end

      bytes = doc.to_slice
      TestHelpers.valid_pdf_header?(bytes).should be_true
    end
  end
end
