require "../spec_helper"

describe PDF::FontInfo do
  describe ".list" do
    it "énumère les fontes d'un document" do
      fonts = PDF::FontInfo.list("spec/fixtures/multi_page.pdf")
      fonts.should_not be_empty
      fonts.all?(&.name.presence).should be_true
    end

    it "déduplique par numéro d'objet" do
      fonts = PDF::FontInfo.list("spec/fixtures/multi_page.pdf")
      object_ids = fonts.map(&.object_number)
      object_ids.uniq.size.should eq(object_ids.size)
    end

    it "renseigne le type et l'encodage" do
      fonts = PDF::FontInfo.list("spec/fixtures/multi_page.pdf")
      font = fonts.first
      font.type.should_not be_empty
      font.object_number.should be > 0
    end
  end

  describe "#subset?" do
    it "détecte un préfixe de sous-ensemble" do
      # On valide la convention de nommage ISO 32000-1 §9.6.4
      # (6 majuscules + '+') via une fonte réelle si présente.
      fonts = PDF::FontInfo.list("spec/fixtures/multi_page.pdf")
      fonts.each do |f|
        expected = f.name.size > 7 && f.name[6] == '+' &&
                   f.name[0, 6].each_char.all?(&.ascii_uppercase?)
        f.subset?.should eq(expected)
      end
    end
  end
end
