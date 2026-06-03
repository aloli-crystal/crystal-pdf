require "../spec_helper"

SPACING_FONT_PATH = "spec/fixtures/fonts/DejaVuSans.ttf"

private def simple_page : PDF::Page
  doc = PDF::Document.new
  page_ref : PDF::Page? = nil
  doc.page do |p|
    p.font("Helvetica", size: 12)
    page_ref = p
  end
  page_ref.not_nil!
end

private def truetype_page : PDF::Page
  doc = PDF::Document.new
  font = doc.load_font(SPACING_FONT_PATH)
  page_ref : PDF::Page? = nil
  doc.page do |p|
    p.font font, size: 12
    page_ref = p
  end
  page_ref.not_nil!
end

describe "PDF::Page character spacing (Tc, ISO 32000-1 § 9.3.2)" do
  it "emits the Tc operator for a simple font and resets it" do
    page = simple_page
    page.text("ABC", at: {0.0, 0.0}, char_spacing: 1.5)
    content = page.@content.to_s
    content.should contain("1.5 Tc")
    content.should contain("0 Tc")
  end

  it "emits Tc for a composite (TrueType) font too" do
    page = truetype_page
    page.text("ABC", at: {0.0, 0.0}, char_spacing: 2.0)
    page.@content.to_s.should contain("2 Tc")
  end

  it "does not emit Tc when char_spacing is zero" do
    page = simple_page
    page.text("ABC", at: {0.0, 0.0})
    page.@content.to_s.should_not contain("Tc")
  end
end

describe "PDF::Page TJ positioning (text_positioned, ISO 32000-1 § 9.4.3)" do
  it "emits a TJ array mixing strings and adjustments" do
    page = simple_page
    page.text_positioned(["A", -80, "V"] of PDF::Page::TextRun, at: {0.0, 0.0})
    content = page.@content.to_s
    content.should contain("] TJ")
    content.should contain("-80")
  end

  it "works for a composite font" do
    page = truetype_page
    page.text_positioned(["AB", -50, "CD"] of PDF::Page::TextRun, at: {0.0, 0.0})
    page.@content.to_s.should contain("] TJ")
  end

  it "combines Tc with TJ positioning" do
    page = simple_page
    page.text_positioned(["A", -80, "V"] of PDF::Page::TextRun, at: {0.0, 0.0}, char_spacing: 2.0)
    content = page.@content.to_s
    content.should contain("2 Tc")
    content.should contain("] TJ")
  end
end
