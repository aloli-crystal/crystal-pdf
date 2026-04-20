# Script de génération des fixtures PDF pour les tests du reader.
#
# Usage: crystal run spec/fixtures/generate_fixtures.cr
#
# Génère des fichiers PDF de test dans spec/fixtures/ en utilisant
# le générateur crystal-pdf existant.

require "../../src/pdf"

# Fixture 1 : PDF simple d'une page
def generate_single_page
  doc = PDF::Document.new

  doc.page do |page|
    page.font "Helvetica", size: 12
    page.text "Hello, Reader!", at: {72, 720}
  end

  path = File.join(__DIR__, "single_page.pdf")
  doc.save(path)
  puts "Généré : #{path}"
end

# Fixture 2 : PDF multi-pages
def generate_multi_page
  doc = PDF::Document.new

  3.times do |i|
    doc.page do |page|
      page.font "Helvetica", size: 14
      page.text "Page #{i + 1}", at: {72, 720}
    end
  end

  path = File.join(__DIR__, "multi_page.pdf")
  doc.save(path)
  puts "Généré : #{path}"
end

generate_single_page
generate_multi_page
