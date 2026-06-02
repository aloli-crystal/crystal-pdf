require "../../spec_helper"

# End-to-end : loading an OpenType/CFF (.otf) font, using CJK text,
# and emitting a PDF with a CIDFontType0 + FontFile3 (CIDFontType0C)
# embedded subset. Needs a system Noto CJK OTF ; pending otherwise.
{% if flag?(:darwin) %}
  describe "OpenType/CFF embedding (palier 0.6.4)" do
    otf_candidates = [
      "/Users/philippe/zold-mbp-pne/github-prod/ttfunk--prawnpdf/spec/fonts/NotoSansCJKsc-Thin.otf",
      "/Users/philippe/Library/Caches/noto-cjk/NotoSansCJKsc-Regular.otf",
    ]

    it "loads an .otf font without raising UnsupportedFontFormat" do
      otf = otf_candidates.find { |p| File.exists?(p) }
      pending! "no Noto CJK OTF available" unless otf

      font = PDF::Fonts::TrueTypeFont.load(otf)
      font.cff?.should be_true
      font.uses_identity_cid_to_gid?.should be_true
      font.font_file_key.should eq("FontFile3")
    end

    it "emits a CIDFontType0 + FontFile3 subset and extractable CJK text" do
      otf = otf_candidates.find { |p| File.exists?(p) }
      pending! "no Noto CJK OTF available" unless otf

      pdf = PDF::Document.new
      font = pdf.load_font(otf)
      pdf.page(:a4) do |page|
        page.font font, size: 24
        page.text "中文字体测试", at: {72, 750}
      end

      bytes = pdf.to_slice
      out = bytes.map(&.chr).join

      out.should contain("/Subtype /Type0")
      out.should contain("/Subtype /CIDFontType0")
      out.should contain("/CIDToGIDMap /Identity")
      out.should contain("/FontFile3")
      out.should contain("/Subtype /CIDFontType0C")

      # The embedded subset is far smaller than the 15 MB source.
      bytes.size.should be < 4_000_000
    end

    it "produces a PDF whose CFF subset re-parses as a valid CIDFont" do
      otf = otf_candidates.find { |p| File.exists?(p) }
      pending! "no Noto CJK OTF available" unless otf

      # Subset directly and re-parse, mirroring what the PDF embeds.
      tt = PDF::Fonts::TrueType::Parser.parse(otf)
      cff = PDF::Fonts::CFF::Parser.new(tt.table_data("CFF ").not_nil!)
      # Keep a few glyphs typical of a short CJK run.
      subset = PDF::Fonts::CFF::Subsetter.new(cff, [0, 100, 200, 1000]).subset
      re = PDF::Fonts::CFF::Parser.new(subset)
      re.cid_font?.should be_true
    end
  end
{% end %}
