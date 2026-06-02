#!/usr/bin/env crystal
#
# Exemple Tagged PDF — arbre de structure logique RELIÉ au contenu
# rendu via marked content (palier 0.7.1, J2 de la trajectoire ISO).
#
# Chaque bloc de texte est dessiné dans un `marked_content` qui lui
# attribue un MCID, puis relié à son élément de structure par
# `add_mcid`. Le PDF résultant porte un /StructTreeRoot dont les
# feuilles pointent (via le /ParentTree) sur les glyphes réellement
# dessinés — c'est ce que vérifie un validateur PDF/UA. L'en-tête de
# page est marqué comme `artifact` (hors structure logique).
#
# Lancement :
#   crystal run examples/tagged_structure.cr

require "../src/pdf"

pdf = PDF::Document.new
pdf.title = "Rapport d'audit ISO 27001"
pdf.lang = "fr" # langue principale — recommandé pour PDF/UA

page = pdf.page(:a4) { |_| }

pdf.struct_tree do |tree|
  doc = tree.add(PDF::Structure::Tag::DOCUMENT)

  # En-tête de page : artifact (hors structure logique).
  page.artifact do
    page.font "Helvetica", size: 8
    page.text "ALOLI — confidentiel", at: {72, 810}
  end

  # Titre principal, relié à son marked content.
  h1 = doc.add(PDF::Structure::Tag.heading(1), title: "Rapport d'audit")
  mcid = page.marked_content("H1") do
    page.font "Helvetica", size: 20
    page.text "Rapport d'audit", at: {72, 780}
  end
  h1.add_mcid(page, mcid)

  # Une section : titre + paragraphe, chacun relié.
  sect = doc.add(PDF::Structure::Tag::SECT)

  h2 = sect.add(PDF::Structure::Tag.heading(2), title: "Périmètre")
  mcid = page.marked_content("H2") do
    page.font "Helvetica", size: 14
    page.text "Section 1 — Périmètre", at: {72, 740}
  end
  h2.add_mcid(page, mcid)

  para = sect.add(PDF::Structure::Tag::P)
  mcid = page.marked_content("P") do
    page.font "Helvetica", size: 11
    page.text "Le présent rapport couvre le périmètre défini…", at: {72, 718}
  end
  para.add_mcid(page, mcid)
end

output = "tagged_demo.pdf"
pdf.save(output)
puts "PDF taggé généré : #{output} (#{File.size(output)} octets)"
puts "Inspectez la structure :"
puts "  qpdf --qdf --object-streams=disable #{output} - | grep -E 'StructElem|MCID|ParentTree'"
