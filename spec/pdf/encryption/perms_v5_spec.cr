require "spec"
require "../../../src/pdf"

# Tests de la validation /Perms en V=5 (Algorithm 13).
#
# /Perms est un bloc de 16 octets chiffrés AES-256-ECB avec
# `file_key`. Après déchiffrement, il doit contenir la signature
# "adb" sur les bytes 9..11 et 0xFFFFFFFF sur les bytes 4..7.
#
# Si la signature "adb" est absente après déchiffrement, c'est que
# `file_key` est faux → mot de passe à rejeter.
describe "PDF::Encryption /Perms validation (V=5)" do
  it "valide /Perms quand le mot de passe est correct" do
    path = File.tempname("rt-perms-ok", ".pdf")
    begin
      pdf = PDF::Document.new
      pdf.encrypt(user_password: "good", level: :aes_256)
      pdf.page do |page|
        page.font("Helvetica", size: 12)
        page.text("Perms OK", at: {72, 720})
      end
      pdf.save(path)

      reader = PDF::Reader.open(path, password: "good")
      reader.page_count.should eq(1)
    ensure
      File.delete(path) if File.exists?(path)
    end
  end

  it "détecte /Perms altéré (tampering) en levant EncryptedPdfError" do
    path = File.tempname("rt-perms-tamper", ".pdf")
    begin
      pdf = PDF::Document.new
      pdf.encrypt(user_password: "secret", level: :aes_256)
      pdf.page do |page|
        page.font("Helvetica", size: 12)
        page.text("Tampering test", at: {72, 720})
      end
      pdf.save(path)

      # Bricoler /Perms : flipper le 1er chiffre hex.
      bytes = File.read(path).to_slice.dup
      perms_marker = "/Perms".to_slice
      idx = -1
      (0...bytes.size - perms_marker.size).each do |i|
        if bytes[i, perms_marker.size] == perms_marker
          idx = i
          break
        end
      end
      pending!("/Perms tag introuvable") if idx < 0

      open_at = -1
      (idx...bytes.size).each do |i|
        if bytes[i] == '<'.ord.to_u8
          open_at = i
          break
        end
      end
      pending!("'<' après /Perms introuvable") if open_at < 0

      target = open_at + 1
      old = bytes[target]
      bytes[target] = (old == '0'.ord.to_u8 ? 'F'.ord.to_u8 : '0'.ord.to_u8)
      File.write(path, bytes)

      # /Perms est corrompu → la signature "adb" ne sera plus visible
      # après AES → password rejeté.
      expect_raises(PDF::EncryptedPdfError, /mot de passe utilisateur invalide/i) do
        PDF::Reader.open(path, password: "secret")
      end
    ensure
      File.delete(path) if File.exists?(path)
    end
  end
end
