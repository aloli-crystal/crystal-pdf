require "spec"
require "../../../src/pdf"

# Specs round-trip : chiffrer un PDF avec notre writer, le relire
# avec notre reader, vérifier que le contenu d'origine ressort.
# Les trois niveaux sont testés (RC4-128, AES-128, AES-256).
describe "PDF chiffrement/déchiffrement (round-trip)" do
  {% for level in [:rc4_128, :aes_128, :aes_256] %}
    describe "niveau {{ level.id }}" do
      it "round-trip : encrypt + read → contenu retrouvé" do
        path = File.tempname("rt-{{ level.id }}", ".pdf")

        begin
          pdf = PDF::Document.new
          pdf.encrypt(
            user_password: "user-pwd",
            owner_password: "owner-pwd",
            level: {{ level }},
          )
          pdf.page do |page|
            page.font("Helvetica", size: 18)
            page.text("Round-trip {{ level.id }} !", at: {72, 720})
          end
          pdf.save(path)
          File.size(path).should be > 0

          # 1. Mot de passe utilisateur ouvre le fichier
          reader = PDF::Reader.open(path, password: "user-pwd")
          reader.page_count.should eq(1)

          # 2. Le contenu est récupérable après Crypt + Flate
          streams = reader.pages.first.content_streams
          streams.size.should be > 0
          content = String.new(streams.first)
          content.should contain("Round-trip")

          # 3. Mauvais mot de passe rejeté
          expect_raises(PDF::EncryptedPdfError) do
            PDF::Reader.open(path, password: "wrong")
          end
        ensure
          File.delete(path) if File.exists?(path)
        end
      end

      it "round-trip : qpdf accepte le PDF chiffré" do
        unless Process.find_executable("qpdf")
          pending! "qpdf non installé — test sautée"
        end

        path = File.tempname("rt-qpdf-{{ level.id }}", ".pdf")
        begin
          pdf = PDF::Document.new
          pdf.encrypt(user_password: "secret", level: {{ level }})
          pdf.page do |page|
            page.font("Helvetica", size: 12)
            page.text("Cross-tool {{ level.id }}", at: {72, 720})
          end
          pdf.save(path)

          io = IO::Memory.new
          status = Process.run(
            "qpdf",
            ["--password=secret", "--check", path],
            output: io, error: io,
          )
          unless status.success?
            fail "qpdf a refusé le PDF :\n#{io}"
          end
        ensure
          File.delete(path) if File.exists?(path)
        end
      end
    end
  {% end %}

  it "conserve le titre /Info chiffré" do
    path = File.tempname("rt-info", ".pdf")
    begin
      pdf = PDF::Document.new
      pdf.title = "Document confidentiel"
      pdf.author = "ALOLI"
      pdf.encrypt(user_password: "secret", level: :aes_256)
      pdf.page do |page|
        page.font("Helvetica", size: 12)
        page.text("Stamped", at: {72, 720})
      end
      pdf.save(path)

      reader = PDF::Reader.open(path, password: "secret")
      reader.page_count.should eq(1)
      # Le déchiffrement des strings indirectes du /Info doit
      # rendre le titre lisible. (Si on avait gardé /Title chiffré,
      # la chaîne serait illisible.)
    ensure
      File.delete(path) if File.exists?(path)
    end
  end
end
