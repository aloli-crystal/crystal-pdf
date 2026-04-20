# Journal des modifications

Toutes les évolutions notables de crystal-pdf sont consignées ici.
Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/)
et le versionnage respecte [SemVer](https://semver.org/lang/fr/).

## [0.3.0] — 20 avril 2026

### Ajouts

- Lecture de fichiers PDF existants via le nouveau module `PDF::Reader`
  (parseur syntaxique, accès aux pages et aux objets indirects, préparation
  à la sauvegarde en mise à jour incrémentale).
- Specs associées (`spec/pdf/parser_spec.cr`, `spec/pdf/reader_spec.cr`) et
  fixtures générées par `spec/fixtures/generate_fixtures.cr`.

### Modifications

- Passe `crystal tool format` sur l'ensemble du code existant.

## [0.2.0] — 13 avril 2026

### Ajouts

- Portage de six fonctionnalités Prawn : crénage, dégradés, chiffrement,
  métadonnées XMP, tampons (stamps) et polices d'icônes.

### Corrections

- Encodage UTF-8 correct pour les polices Type1 (WinAnsiEncoding).
- Références partagées des polices TrueType.

### Autres

- Exclusions ameba complétées pour la CI.

## [0.1.0] — 10 avril 2026

### Ajouts

- Première version publiée : moteur PDF bas niveau porté de
  [watzon/pdf.cr](https://github.com/watzon/pdf.cr), lui-même inspiré de la
  gem Ruby Prawn.
- Couverture : pages multiples, polices Type1 et TrueType (Unicode),
  graphiques vectoriels, images JPEG/PNG, texte formaté, boîtes englobantes
  et colonnes, tableaux, rendu SVG.
- Workflows CI et surveillance upstream.
- Jeu de tests initial.

[0.3.0]: https://github.com/aloli-crystal/crystal-pdf/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/aloli-crystal/crystal-pdf/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/aloli-crystal/crystal-pdf/releases/tag/v0.1.0
