require "spec"
require "../../../src/pdf"

# Spec de non-régression : un PDF où le `/Length` d'un content stream
# est une référence indirecte vers un objet **stocké dans un object
# stream** (PDF 1.5+). Ghostscript ≥ 9.x produit ce genre de structure
# par défaut quand il « normalise » un PDF.
#
# Avant le fix, `parse_stream` ne consultait que `@xref` (uncompressed
# entries) → la longueur restait à 0 → on lisait 0 octets → les pages
# apparaissaient vides après fusion. cf. bug rapporté sur le livret
# « 2026-05-08--messe-laguiole » (pages 11/12 vides venant d'un PDF
# normalisé via gs depuis un original chiffré).
describe "Parser — /Length indirect dans un object stream (PDF 1.5+)" do
  it "résout correctement /Length quand il pointe sur un objet compressé" do
    unless Process.find_executable("gs")
      pending! "ghostscript (gs) requis pour produire la fixture"
    end

    plain = File.tempname("plain", ".pdf")
    normalized = File.tempname("gs", ".pdf")

    begin
      # 1. Génère un PDF simple via le shard
      pdf = PDF::Document.new
      pdf.page do |page|
        page.font("Helvetica", size: 14)
        page.text("Page 1 — du contenu pour le content stream", at: {72, 720})
      end
      pdf.page do |page|
        page.font("Helvetica", size: 14)
        page.text("Page 2 — encore du contenu visible", at: {72, 720})
      end
      pdf.save(plain)

      # 2. Ghostscript le « normalise » : produit un PDF 1.5+ avec
      # object streams ET un /Length indirect compressé pour les
      # content streams (le cas qui plantait).
      io = IO::Memory.new
      status = Process.run("gs", [
        "-sDEVICE=pdfwrite", "-dPDFSETTINGS=/default",
        "-o", normalized,
        "-dNOPAUSE", "-dQUIET", "-dBATCH",
        plain,
      ], output: io, error: io)
      pending!("gs a échoué : #{io}") unless status.success? && File.exists?(normalized)

      # Vérification de forme : le PDF a bien des object streams
      raw = File.read(normalized)
      raw.includes?("/ObjStm").should be_true

      # 3. Notre reader doit retrouver le contenu sur les deux pages
      reader = PDF::Reader.open(normalized)
      reader.page_count.should eq(2)

      page1_streams = reader.pages.first.content_streams
      page1_streams.size.should be > 0
      page1_total = page1_streams.sum(&.size)
      page1_total.should be > 0
      String.new(page1_streams.first).should contain("BT") # debut bloc texte PDF

      page2_streams = reader.pages[1].content_streams
      page2_streams.sum(&.size).should be > 0
    ensure
      File.delete(plain) if File.exists?(plain)
      File.delete(normalized) if File.exists?(normalized)
    end
  end
end
