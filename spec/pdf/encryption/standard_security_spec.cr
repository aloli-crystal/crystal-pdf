require "spec"
require "../../../src/pdf"

describe "PDF::Encryption::StandardSecurity (intégration Reader)" do
  # Vecteur réel produit par qpdf --encrypt '' owner 128 :
  # un PDF chiffré RC4 128-bit R=3 avec mot de passe utilisateur vide
  # et permissions restreintes (P=-4 = pas de print/copy/modify).
  it "ouvre un PDF chiffré RC4 128-bit R=3 avec mot de passe vide" do
    # On encode-on-the-fly un PDF de référence chiffré pour ne pas
    # dépendre d'un fichier binaire commité dans le repo. qpdf est
    # disponible dans la CI Linux et FreeBSD.
    plain = File.tempname("plain", ".pdf")
    encrypted = File.tempname("encrypted", ".pdf")

    begin
      # 1. Construire un PDF source minimal via le shard lui-même.
      pdf = PDF::Document.new
      pdf.page do |page|
        page.font("Helvetica", size: 24)
        page.text("Hello, encrypted PDF !", at: {72, 720})
      end
      pdf.save(plain)

      # 2. Chiffrer via qpdf (RC4 128 R=3, user pwd vide, owner pwd
      # « owner »). Skip le test si qpdf n'est pas installé.
      unless Process.find_executable("qpdf")
        pending! "qpdf n'est pas installé — test sautée"
      end
      io = IO::Memory.new
      status = Process.run(
        "qpdf",
        ["--allow-weak-crypto", "--encrypt", "", "owner", "128", "--", plain, encrypted],
        output: io, error: io,
      )
      unless status.success?
        pending! "qpdf a refusé le chiffrement (#{io.to_s.lines.first?}) — test sautée"
      end

      # 3. Le shard arrive à ouvrir et lire le PDF chiffré.
      reader = PDF::Reader.open(encrypted)
      reader.page_count.should eq(1)

      # 4. Le content stream est bien déchiffré ET décompressé.
      streams = reader.pages.first.content_streams
      streams.size.should be > 0
      content = String.new(streams.first)
      content.should contain("Hello") # texte original retrouvé
    ensure
      File.delete(plain) if File.exists?(plain)
      File.delete(encrypted) if File.exists?(encrypted)
    end
  end

  it "lève EncryptedPdfError sur mauvais mot de passe" do
    plain = File.tempname("plain", ".pdf")
    encrypted = File.tempname("encrypted", ".pdf")

    begin
      pdf = PDF::Document.new
      pdf.page do |page|
        page.font("Helvetica", size: 12)
        page.text("Secret", at: {72, 720})
      end
      pdf.save(plain)

      unless Process.find_executable("qpdf")
        pending! "qpdf non installé"
      end
      io = IO::Memory.new
      status = Process.run(
        "qpdf",
        ["--allow-weak-crypto", "--encrypt", "user", "owner", "128", "--", plain, encrypted],
        output: io, error: io,
      )
      pending! "qpdf KO" unless status.success?

      expect_raises(PDF::EncryptedPdfError, /mot de passe utilisateur invalide/i) do
        PDF::Reader.open(encrypted) # mot de passe vide essayé
      end
    ensure
      File.delete(plain) if File.exists?(plain)
      File.delete(encrypted) if File.exists?(encrypted)
    end
  end

  it "ouvre un PDF chiffré avec mot de passe utilisateur fourni" do
    plain = File.tempname("plain", ".pdf")
    encrypted = File.tempname("encrypted", ".pdf")

    begin
      pdf = PDF::Document.new
      pdf.page do |page|
        page.font("Helvetica", size: 12)
        page.text("Confidential", at: {72, 720})
      end
      pdf.save(plain)

      unless Process.find_executable("qpdf")
        pending! "qpdf non installé"
      end
      io = IO::Memory.new
      status = Process.run(
        "qpdf",
        ["--allow-weak-crypto", "--encrypt", "user-pwd", "owner-pwd", "128", "--", plain, encrypted],
        output: io, error: io,
      )
      pending! "qpdf KO" unless status.success?

      reader = PDF::Reader.open(encrypted, password: "user-pwd")
      reader.page_count.should eq(1)
      content = String.new(reader.pages.first.content_streams.first)
      content.should contain("Confidential")
    ensure
      File.delete(plain) if File.exists?(plain)
      File.delete(encrypted) if File.exists?(encrypted)
    end
  end
end
