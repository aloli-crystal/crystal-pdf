#!/usr/bin/env crystal
#
# Exemple Tagged PDF — construction d'un arbre de structure logique
# (palier 0.7.0, J2 de la trajectoire ISO).
#
# Ce palier pose la *structure logique* (StructTreeRoot + StructElem
# + /MarkInfo + /Lang). Le marquage du contenu rendu (opérateurs
# BDC/EMC + MCID qui relient l'arbre aux glyphes) arrive au palier
# 0.7.1 ; ici l'arbre décrit la hiérarchie mais ne pointe pas encore
# sur le contenu dessiné.
#
# Lancement :
#   crystal run examples/tagged_structure.cr

require "../src/pdf"

pdf = PDF::Document.new
pdf.title = "Rapport d'audit ISO 27001"
pdf.lang = "fr" # langue principale — recommandé pour PDF/UA

pdf.page(:a4) do |page|
  page.font "Helvetica", size: 20
  page.text "Rapport d'audit", at: {72, 780}
  page.font "Helvetica", size: 11
  page.text "Section 1 — Périmètre", at: {72, 740}
  page.text "Le présent rapport couvre…", at: {72, 720}
end

# Arbre de structure logique du document.
pdf.struct_tree do |tree|
  doc = tree.add(PDF::Structure::Tag::DOCUMENT)

  # Titre principal.
  doc.add(PDF::Structure::Tag.heading(1), title: "Rapport d'audit")

  # Une section avec un titre et un paragraphe.
  sect = doc.add(PDF::Structure::Tag::SECT)
  sect.add(PDF::Structure::Tag.heading(2), title: "Périmètre")
  sect.add(PDF::Structure::Tag::P)

  # Une figure avec texte alternatif (accessibilité).
  doc.add(PDF::Structure::Tag::FIGURE, alt: "Schéma du système d'information")
end

output = "tagged_demo.pdf"
pdf.save(output)
puts "PDF taggé généré : #{output} (#{File.size(output)} octets)"
puts "Inspectez la structure : qpdf --qdf --object-streams=disable #{output} - | grep StructElem"
