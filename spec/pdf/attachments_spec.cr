require "../spec_helper"

# Construit un document avec une pièce jointe et le relit.
private def build_with_attachment : PDF::Reader
  pdf = PDF::Document.new
  pdf.page { |_| }
  pdf.attach_file(
    bytes: "invoice".to_slice,
    name: "factur-x.xml",
    description: "Factur-X invoice data",
    relationship: :data,
    mime_type: "application/xml",
  )
  PDF::Reader.open(IO::Memory.new(pdf.to_slice))
end

describe PDF::AttachedFile do
  describe ".list" do
    it "découvre une pièce jointe via l'arbre /EmbeddedFiles et /AF" do
      files = PDF::AttachedFile.list(build_with_attachment)
      files.size.should eq(1)
      files.first.name.should eq("factur-x.xml")
    end

    it "restitue les octets décompressés du fichier embarqué" do
      file = PDF::AttachedFile.list(build_with_attachment).first
      String.new(file.data).should eq("invoice")
    end

    it "expose la description, le type MIME et la relation" do
      file = PDF::AttachedFile.list(build_with_attachment).first
      file.description.should eq("Factur-X invoice data")
      file.mime_type.should eq("application/xml")
      file.relationship.should eq("Data")
    end

    it "renvoie une liste vide pour un document sans pièce jointe" do
      reader = PDF::Reader.open("spec/fixtures/single_page.pdf")
      PDF::AttachedFile.list(reader).should be_empty
    end

    it "déduplique les attachements partagés entre /AF et l'arbre de noms" do
      # factur-x.xml apparaît dans /Names /EmbeddedFiles ET /AF : une
      # seule entrée attendue (dédup par numéro d'objet du flux).
      files = PDF::AttachedFile.list(build_with_attachment)
      files.map(&.object_number).uniq.size.should eq(files.size)
    end
  end

  describe ".attach" do
    it "ajoute une pièce jointe relisible (aller-retour attach → list)" do
      base = PDF::Document.new
      base.page { |_| }
      reader = PDF::Reader.open(IO::Memory.new(base.to_slice))

      PDF::AttachedFile.attach(
        reader, "facture".to_slice, "factur-x.xml",
        description: "Données Factur-X", relationship: :data,
        mime_type: "application/xml",
      )

      io = IO::Memory.new
      reader.write(io)
      reopened = PDF::Reader.open(IO::Memory.new(io.to_slice))

      files = PDF::AttachedFile.list(reopened)
      files.size.should eq(1)
      files.first.name.should eq("factur-x.xml")
      String.new(files.first.data).should eq("facture")
      files.first.mime_type.should eq("application/xml")
      files.first.relationship.should eq("Data")
    end

    it "préserve une pièce jointe existante lors d'un second ajout" do
      base = PDF::Document.new
      base.page { |_| }
      r1 = PDF::Reader.open(IO::Memory.new(base.to_slice))
      PDF::AttachedFile.attach(r1, "un".to_slice, "a.txt")
      io1 = IO::Memory.new
      r1.write(io1)

      r2 = PDF::Reader.open(IO::Memory.new(io1.to_slice))
      PDF::AttachedFile.attach(r2, "deux".to_slice, "b.txt")
      io2 = IO::Memory.new
      r2.write(io2)

      reopened = PDF::Reader.open(IO::Memory.new(io2.to_slice))
      names = PDF::AttachedFile.list(reopened).map(&.name).sort
      names.should eq(["a.txt", "b.txt"])
    end
  end

  describe "Reader#add_object / #replace_object" do
    it "alloue un numéro d'objet et émet le nouvel objet" do
      base = PDF::Document.new
      base.page { |_| }
      reader = PDF::Reader.open(IO::Memory.new(base.to_slice))

      before = reader.trailer["Size"]?.as(PDF::Objects::Number).to_i64
      str = PDF::Objects::Str.new("marqueur")
      ref = reader.add_object(str)
      ref.object_number.should be >= before

      io = IO::Memory.new
      reader.write(io)
      reopened = PDF::Reader.open(IO::Memory.new(io.to_slice))
      reopened.resolve(ref).as(PDF::Objects::Str).value.should eq("marqueur")
    end
  end
end
