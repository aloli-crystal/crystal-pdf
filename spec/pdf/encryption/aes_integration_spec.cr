require "spec"
require "../../../src/pdf"

# Specs d'intégration pour le déchiffrement AES via fixtures qpdf.
# Skippées si qpdf n'est pas installé.
describe "PDF::Encryption (AES)" do
  it "ouvre un PDF chiffré AES-128 R=4 (V=4 + CryptFilter AESV2)" do
    plain = File.tempname("plain", ".pdf")
    encrypted = File.tempname("aes128", ".pdf")

    begin
      pdf = PDF::Document.new
      pdf.page do |page|
        page.font("Helvetica", size: 18)
        page.text("Hello, AES-128 PDF !", at: {72, 720})
      end
      pdf.save(plain)

      unless Process.find_executable("qpdf")
        pending! "qpdf non installé"
      end
      io = IO::Memory.new
      status = Process.run(
        "qpdf",
        ["--encrypt", "user", "owner", "128", "--use-aes=y", "--", plain, encrypted],
        output: io, error: io,
      )
      pending! "qpdf KO (#{io}) — test sautée" unless status.success?

      reader = PDF::Reader.open(encrypted, password: "user")
      reader.page_count.should eq(1)
      streams = reader.pages.first.content_streams
      streams.size.should be > 0
      content = String.new(streams.first)
      content.should contain("Hello") # texte d'origine retrouvé après AES + Flate
    ensure
      File.delete(plain) if File.exists?(plain)
      File.delete(encrypted) if File.exists?(encrypted)
    end
  end

  it "ouvre un PDF chiffré AES-256 R=6 (V=5)" do
    plain = File.tempname("plain", ".pdf")
    encrypted = File.tempname("aes256", ".pdf")

    begin
      pdf = PDF::Document.new
      pdf.page do |page|
        page.font("Helvetica", size: 18)
        page.text("Bonjour, AES-256 PDF !", at: {72, 720})
      end
      pdf.save(plain)

      unless Process.find_executable("qpdf")
        pending! "qpdf non installé"
      end
      io = IO::Memory.new
      status = Process.run(
        "qpdf",
        ["--encrypt", "user", "owner", "256", "--", plain, encrypted],
        output: io, error: io,
      )
      pending! "qpdf KO (#{io}) — test sautée" unless status.success?

      reader = PDF::Reader.open(encrypted, password: "user")
      reader.page_count.should eq(1)
      streams = reader.pages.first.content_streams
      streams.size.should be > 0
      content = String.new(streams.first)
      content.should contain("Bonjour")
    ensure
      File.delete(plain) if File.exists?(plain)
      File.delete(encrypted) if File.exists?(encrypted)
    end
  end

  it "ouvre un PDF chiffré AES-256 avec mot de passe owner" do
    plain = File.tempname("plain", ".pdf")
    encrypted = File.tempname("aes256-owner", ".pdf")

    begin
      pdf = PDF::Document.new
      pdf.page do |page|
        page.font("Helvetica", size: 12)
        page.text("Owner-only data", at: {72, 720})
      end
      pdf.save(plain)

      unless Process.find_executable("qpdf")
        pending! "qpdf non installé"
      end
      io = IO::Memory.new
      status = Process.run(
        "qpdf",
        ["--encrypt", "user-pwd", "owner-pwd", "256", "--", plain, encrypted],
        output: io, error: io,
      )
      pending! "qpdf KO (#{io}) — test sautée" unless status.success?

      # Le mot de passe owner doit aussi déverrouiller le fichier
      # (V=5 sait essayer les deux côtés via /OE).
      reader = PDF::Reader.open(encrypted, password: "owner-pwd")
      reader.page_count.should eq(1)
    ensure
      File.delete(plain) if File.exists?(plain)
      File.delete(encrypted) if File.exists?(encrypted)
    end
  end

  it "lève EncryptedPdfError sur mauvais mot de passe AES-256" do
    plain = File.tempname("plain", ".pdf")
    encrypted = File.tempname("aes256-wrong", ".pdf")

    begin
      pdf = PDF::Document.new
      pdf.page do |page|
        page.font("Helvetica", size: 12)
        page.text("Top secret", at: {72, 720})
      end
      pdf.save(plain)

      unless Process.find_executable("qpdf")
        pending! "qpdf non installé"
      end
      io = IO::Memory.new
      status = Process.run(
        "qpdf",
        ["--encrypt", "the-real-password", "owner", "256", "--", plain, encrypted],
        output: io, error: io,
      )
      pending! "qpdf KO (#{io}) — test sautée" unless status.success?

      expect_raises(PDF::EncryptedPdfError, /mot de passe utilisateur invalide/i) do
        PDF::Reader.open(encrypted, password: "wrong-password")
      end
    ensure
      File.delete(plain) if File.exists?(plain)
      File.delete(encrypted) if File.exists?(encrypted)
    end
  end
end
