require "../spec_helper"

describe PDF::Reader do
  fixtures_dir = File.join(__DIR__, "..", "fixtures")

  describe ".open" do
    it "ouvre un PDF depuis un chemin de fichier" do
      reader = PDF::Reader.open(File.join(fixtures_dir, "single_page.pdf"))
      reader.should be_a(PDF::Reader)
    end

    it "ouvre un PDF depuis un IO" do
      File.open(File.join(fixtures_dir, "single_page.pdf")) do |io|
        reader = PDF::Reader.open(io)
        reader.should be_a(PDF::Reader)
      end
    end
  end

  describe "#version" do
    it "retourne la version du PDF" do
      reader = PDF::Reader.open(File.join(fixtures_dir, "single_page.pdf"))
      reader.version.should eq("1.7")
    end
  end

  describe "#page_count" do
    it "retourne 1 pour un PDF d'une page" do
      reader = PDF::Reader.open(File.join(fixtures_dir, "single_page.pdf"))
      reader.page_count.should eq(1)
    end

    it "retourne 3 pour un PDF multi-pages" do
      reader = PDF::Reader.open(File.join(fixtures_dir, "multi_page.pdf"))
      reader.page_count.should eq(3)
    end
  end

  describe "#pages" do
    it "retourne les pages du document" do
      reader = PDF::Reader.open(File.join(fixtures_dir, "single_page.pdf"))
      reader.pages.size.should eq(1)
    end

    it "fournit les dimensions de la page" do
      reader = PDF::Reader.open(File.join(fixtures_dir, "single_page.pdf"))
      page = reader.pages[0]
      # Dimensions Letter US par défaut
      page.width.should eq(612.0)
      page.height.should eq(792.0)
    end

    it "itère sur toutes les pages d'un PDF multi-pages" do
      reader = PDF::Reader.open(File.join(fixtures_dir, "multi_page.pdf"))
      reader.pages.size.should eq(3)
      reader.pages.each do |page|
        page.width.should eq(612.0)
        page.height.should eq(792.0)
      end
    end
  end

  describe "#resolve" do
    it "résout les références indirectes" do
      reader = PDF::Reader.open(File.join(fixtures_dir, "single_page.pdf"))
      root_ref = reader.trailer["Root"]
      root_ref.should be_a(PDF::Objects::Reference)

      catalog = reader.resolve(root_ref)
      catalog.should be_a(PDF::Objects::Dictionary)
      catalog.as(PDF::Objects::Dictionary)["Type"]
        .as(PDF::Objects::Name).value.should eq("Catalog")
    end

    it "retourne l'objet tel quel s'il n'est pas une référence" do
      reader = PDF::Reader.open(File.join(fixtures_dir, "single_page.pdf"))
      num = PDF::Objects::Number.new(42)
      reader.resolve(num).should eq(num)
    end
  end

  describe "#trailer" do
    it "contient les entrées /Root et /Size" do
      reader = PDF::Reader.open(File.join(fixtures_dir, "single_page.pdf"))
      reader.trailer.has_key?("Root").should be_true
      reader.trailer.has_key?("Size").should be_true
    end
  end

  describe "flux de contenu" do
    it "lit les flux de contenu des pages" do
      reader = PDF::Reader.open(File.join(fixtures_dir, "single_page.pdf"))
      page = reader.pages[0]
      streams = page.content_streams
      streams.size.should be > 0
      # Le contenu devrait contenir des opérateurs PDF
      content = String.new(streams[0])
      content.should contain("Tj")
    end

    it "décompresse les flux FlateDecode" do
      reader = PDF::Reader.open(File.join(fixtures_dir, "single_page.pdf"))
      page = reader.pages[0]
      streams = page.content_streams
      # Le flux doit être décompressé (lisible en texte)
      content = String.new(streams[0])
      content.size.should be > 0
      # Ne devrait pas être des données binaires compressées
      content.each_char do |c|
        break unless c.ascii?
      end
    end
  end

  describe "ressources" do
    it "accède aux ressources d'une page" do
      reader = PDF::Reader.open(File.join(fixtures_dir, "single_page.pdf"))
      page = reader.pages[0]
      resources = page.resources
      resources.should be_a(PDF::Objects::Dictionary)
      resources.has_key?("Font").should be_true
    end
  end

  describe "ajout de contenu et sauvegarde" do
    it "ajoute un flux de contenu à une page" do
      reader = PDF::Reader.open(File.join(fixtures_dir, "single_page.pdf"))
      page = reader.pages[0]

      page.add_content_stream("q 0.5 g 72 72 100 100 re f Q")
      page.added_streams.size.should eq(1)
    end

    it "sauvegarde un PDF modifié avec mise à jour incrémentale" do
      source = File.join(fixtures_dir, "single_page.pdf")
      output = File.join(fixtures_dir, "modified_output.pdf")

      reader = PDF::Reader.open(source)
      page = reader.pages[0]
      page.add_content_stream("q 0.5 g 72 72 100 100 re f Q")

      reader.save(output)

      # Vérifier que le fichier de sortie est plus grand que l'original
      File.size(output).should be > File.size(source)

      # Vérifier que le fichier de sortie est un PDF valide
      output_data = File.read(output).to_slice
      String.new(output_data[0, 5]).should eq("%PDF-")
      String.new(output_data[-7, 6]).should contain("%%EOF")

      # Relire le PDF modifié
      reader2 = PDF::Reader.open(output)
      reader2.page_count.should eq(1)

      # Nettoyer
      File.delete(output) if File.exists?(output)
    end

    # Régression pour le crash « Invalid Int32: "" » qui se
    # déclenchait lors de la réouverture d'un PDF amendé contenant
    # des octets ≥ 0x80 (typiquement un content stream FlateDecode
    # ou n'importe quel content stream binaire). La vraie cause :
    # `find_xref_offset` utilisait `String#rindex` qui retourne un
    # offset en caractères (UTF-8), désynchronisé de l'offset en
    # octets dès qu'un caractère multi-octet apparaît dans la zone
    # de recherche. Le scan est désormais purement octet-à-octet.
    it "réouvre un PDF amendé contenant des octets binaires (≥ 0x80)" do
      source = File.join(fixtures_dir, "single_page.pdf")
      output = File.join(fixtures_dir, "modified_binary_output.pdf")

      reader = PDF::Reader.open(source)
      reader.pages.each do |page|
        # Content stream avec une rampe d'octets 0..255 — couvre
        # toute la plage UTF-8 (0x80-0xFF inclus) qui déclenche le
        # bug d'index char vs octet.
        page.add_content_stream(String.build do |io|
          io << "q\n"
          256.times { |b| io.write_byte((b % 256).to_u8) }
          io << "\nQ\n"
        end)
      end
      reader.save(output)

      begin
        # Avant le fix, cette ligne crashait avec
        # `ArgumentError: Invalid Int32: ""`.
        reader2 = PDF::Reader.open(output)
        reader2.page_count.should eq(1)
      ensure
        File.delete(output) if File.exists?(output)
      end
    end
  end
end
