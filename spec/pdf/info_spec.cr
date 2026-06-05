require "../spec_helper"

describe PDF::Info do
  describe ".open" do
    it "lit les métadonnées d'une page unique" do
      info = PDF::Info.open("spec/fixtures/single_page.pdf")
      info.page_count.should eq(1)
      info.version.should eq("1.7")
      info.encrypted?.should be_false
      info.page_rot.should eq(0)
      info.producer.should_not be_nil
    end

    it "compte correctement les pages d'un document multi-pages" do
      info = PDF::Info.open("spec/fixtures/multi_page.pdf")
      info.page_count.should eq(3)
    end

    it "expose les dimensions de la première page" do
      info = PDF::Info.open("spec/fixtures/single_page.pdf")
      size = info.page_size.should_not be_nil
      size[0].should be_close(612.0, 1.0)
      size[1].should be_close(792.0, 1.0)
    end

    it "renseigne la taille du fichier" do
      info = PDF::Info.open("spec/fixtures/single_page.pdf")
      info.file_size.should eq(File.size("spec/fixtures/single_page.pdf"))
    end
  end

  describe "#page_size_name" do
    it "reconnaît le format Letter" do
      info = PDF::Info.open("spec/fixtures/single_page.pdf")
      info.page_size_name.should eq("Letter")
    end
  end

  describe ".parse_date" do
    it "analyse une date PDF complète avec décalage horaire" do
      time = PDF::Info.parse_date("D:20260604160230+02'00'")
      time.should_not be_nil
      time = time.not_nil!
      time.year.should eq(2026)
      time.month.should eq(6)
      time.day.should eq(4)
      time.hour.should eq(16)
      time.minute.should eq(2)
      time.second.should eq(30)
      time.offset.should eq(2 * 3600)
    end

    it "tolère les champs optionnels et le suffixe Z" do
      time = PDF::Info.parse_date("D:2026Z").should_not be_nil
      time.year.should eq(2026)
      time.month.should eq(1)
      time.day.should eq(1)
      time.offset.should eq(0)
    end

    it "renvoie nil pour une entrée vide ou invalide" do
      PDF::Info.parse_date(nil).should be_nil
      PDF::Info.parse_date("D:").should be_nil
      PDF::Info.parse_date("garbage").should be_nil
    end
  end

  describe ".decode_text_string" do
    it "décode l'UTF-16BE avec BOM" do
      # « é » = U+00E9 → FE FF 00 E9
      raw = String.new(Bytes[0xFE, 0xFF, 0x00, 0xE9])
      PDF::Info.decode_text_string(raw).should eq("é")
    end

    it "laisse passer l'ASCII sans BOM" do
      PDF::Info.decode_text_string("Hello").should eq("Hello")
    end
  end
end
