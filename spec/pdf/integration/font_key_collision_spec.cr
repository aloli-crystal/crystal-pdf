require "spec"
require "../../../src/pdf"

# Spec de non-régression : avant le fix, mélanger des TTF et des Type1
# sur la même page provoquait une collision de clés `F<n>` dans
# `/Resources /Font`. Le rendu des Type1 ajoutés après un TTF était
# invisible parce qu'Acrobat interprétait leur clé comme la TTF.
#
# Cas réel : crystal-asciidoctor-pdf rendait un mot en gras+italique
# (ex. `*_mécanique_*`) qui disparaissait du PDF — le thème par défaut
# DejaVu Sans n'inclut pas BoldOblique, le shard fallback sur
# Helvetica-BoldOblique (Type1), et la collision F<n> rendait le
# mot invisible.
describe "Page : pas de collision de clés font Type1 / TTF" do
  it "rend correctement le mélange TTF → Type1 → TTF sur la même page" do
    fonts_dir = File.join(__DIR__, "..", "fonts", "fixtures")
    # Charger une fixture TTF disponible
    ttf_candidates = Dir.glob(File.join(__DIR__, "..", "..", "..", "lib", "pdf", "spec", "fixtures", "fonts", "*.ttf"))
    ttf_candidates += Dir.glob(File.join(__DIR__, "..", "..", "fixtures", "fonts", "*.ttf"))
    ttf_candidates += Dir.glob(File.join(__DIR__, "..", "..", "..", "..", "crystal-asciidoctor-pdf", "data", "fonts", "*.ttf"))
    ttf_path = ttf_candidates.find { |p| File.exists?(p) }
    pending! "pas de fixture TTF trouvée" unless ttf_path

    output_pdf = File.tempname("font-key", ".pdf")
    begin
      doc = PDF::Document.new
      ttf = doc.load_font(ttf_path.not_nil!)
      doc.page do |p|
        p.font(ttf, size: 12)
        p.text("ttf-1", at: {72, 750})
        p.font("Helvetica-BoldOblique", size: 12)
        p.text("type1-bo", at: {72, 720})
        p.font(ttf, size: 12)
        p.text("ttf-2", at: {72, 690})
      end
      doc.save(output_pdf)

      reader = PDF::Reader.open(output_pdf)
      reader.page_count.should eq(1)

      # Vérifier que le content stream a 3 textes distincts (pas de
      # contenu vide pour le segment Type1 du milieu)
      streams = reader.pages.first.content_streams
      content = String.new(streams.first)
      # Helvetica-BoldOblique encode "type1-bo" en WinAnsi : tous les
      # caractères ASCII restent identiques. On cherche la séquence.
      # Helvetica-BoldOblique encode "type1-bo" en WinAnsi → ASCII
      # identique. Le run Type1 doit ÊTRE PRÉSENT entre les deux runs TTF.
      content.should contain("(type1-bo)")

      # On vérifie l'unicité des clés utilisées dans le content stream.
      # Avant le fix : F1 était utilisé à la fois pour le TTF et pour
      # Helvetica-BoldOblique → collision. Après le fix : deux clés
      # distinctes, pas de collision.
      f_keys = content.scan(/\/F\d+/).map(&.[0]).to_a.uniq.sort
      f_keys.size.should eq(2) # 1 TTF + 1 Type1
      # Le run Type1 doit utiliser sa propre clé, distincte du TTF.
      ttf_runs = content.scan(/<[0-9A-Fa-f]+> Tj/).size
      ttf_runs.should eq(2) # ttf-1 et ttf-2
      type1_runs = content.scan(/\(type1-bo\) Tj/).size
      type1_runs.should eq(1)
    ensure
      File.delete(output_pdf) if File.exists?(output_pdf)
    end
  end
end
