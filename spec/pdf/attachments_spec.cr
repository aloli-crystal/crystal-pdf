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
end
