#!/usr/bin/env crystal
#
# Exemple AcroForm — formulaire interactif avec les 4 types de
# champs supportés par le MVP J0 : texte, case à cocher, bouton
# radio, dropdown.
#
# Génère `acroform_demo.pdf` que l'on peut ouvrir dans Acrobat,
# Preview, Firefox ou Chrome, remplir, puis sauvegarder.
#
# Lancement :
#   crystal run examples/acroform.cr

require "../src/pdf"

pdf = PDF::Document.new
pdf.title = "Démo formulaire ALOLI"
pdf.author = "aloli-crystal/pdf"

# Coordonnées de référence : une seule colonne, labels à gauche
# (x=72), champs à x=200, et un pas vertical commun pour éviter
# tout chevauchement.
LABEL_X       =  72
FIELD_X       = 200
RADIO_SIZE    =  12
RADIO_LABEL_X = FIELD_X + RADIO_SIZE + 6 # juste à droite du rond

page = pdf.page(:a4) do |p|
  # Titre + intro.
  p.font "Helvetica", size: 18
  p.text "Démonstration AcroForm", at: {LABEL_X, 780}

  p.font "Helvetica", size: 10
  p.text "Cliquez dans les champs pour les remplir, puis sauvegardez.", at: {LABEL_X, 760}

  # Labels statiques en regard de chaque champ.
  p.font "Helvetica", size: 11

  p.text "Nom :", at: {LABEL_X, 706}
  # Pour un textarea, aligner le label avec la première ligne (haut
  # du champ), pas son centre. Champ multi-ligne : y=580, height=70
  # → haut à 650 ; baseline du label à top - 6 ≈ 644.
  p.text "Commentaire :", at: {LABEL_X, 644}
  p.text "Pays :", at: {LABEL_X, 556}

  # Bloc Genre : on dessine le label « Genre : » puis chaque option
  # avec son texte juste à droite du bouton radio.
  p.text "Genre :", at: {LABEL_X, 506}
  radio_labels = ["Masculin", "Féminin", "Autre", "Préfère ne pas répondre"]
  radio_y_top = 500
  radio_spacing = 22
  radio_labels.each_with_index do |label, i|
    y = radio_y_top - i * radio_spacing
    # Léger décalage vertical pour aligner avec le centre du rond.
    p.text label, at: {RADIO_LABEL_X, y + 2}
  end

  # Cases à cocher — décalées plus bas que la fin du groupe radio.
  newsletter_y = radio_y_top - radio_labels.size * radio_spacing - 20
  conditions_y = newsletter_y - 30

  p.text "Newsletter :", at: {LABEL_X, newsletter_y}
  p.text "Conditions :", at: {LABEL_X, conditions_y}
end

pdf.acroform do |form|
  # Champ texte simple.
  form.text_field(
    "nom",
    page: page,
    x: FIELD_X, y: 700,
    width: 250, height: 20,
    required: true,
  )

  # Champ texte multi-ligne.
  form.text_field(
    "commentaire",
    page: page,
    x: FIELD_X, y: 580,
    width: 300, height: 70,
    multiline: true,
  )

  # Liste déroulante.
  form.dropdown(
    "pays",
    page: page,
    options: ["France", "Belgique", "Suisse", "Canada", "Autre"],
    x: FIELD_X, y: 550,
    width: 120, height: 20,
    default_value: "France",
  )

  # Boutons radio. spacing=22 doit matcher celui du label dessiné
  # plus haut pour que chaque rond soit pile en regard de son texte.
  form.radio_group(
    "genre",
    page: page,
    options: ["Masculin", "Féminin", "Autre", "Préfère ne pas répondre"],
    x: FIELD_X, y: 500,
    spacing: 22, size: RADIO_SIZE,
    selected: "Masculin",
  )

  # Case à cocher cochée par défaut.
  form.checkbox(
    "newsletter",
    page: page,
    x: FIELD_X, y: 500 - 4 * 22 - 20,
    size: 12,
    checked: true,
  )

  # Case à cocher requise (consentement).
  form.checkbox(
    "rgpd_consent",
    page: page,
    x: FIELD_X, y: 500 - 4 * 22 - 20 - 30,
    size: 12,
    required: true,
  )
end

output = "acroform_demo.pdf"
pdf.save(output)
puts "Formulaire généré : #{output} (#{File.size(output)} octets)"
puts "Ouvrez le PDF dans Acrobat, Preview, Firefox ou Chrome,"
puts "remplissez les champs, puis sauvegardez."
