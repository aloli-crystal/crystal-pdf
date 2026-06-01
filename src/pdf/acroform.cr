# AcroForm — interactive PDF forms (PDF spec § 12.7).
#
# This is the J0 MVP : structure /AcroForm in the catalog, with
# /NeedAppearances true so visualizers regenerate appearance streams
# on the fly when the user fills the form. Supports four field types :
# text, checkbox, radio group, dropdown.
#
# Hors scope J0 (will come in J1 or later) :
# * Custom appearance streams (visual styling of widgets)
# * Signature fields (/FT /Sig) — couples with pdf-signature
# * Calculations, actions, JavaScript (forbidden in PDF/A anyway)
# * FDF/XFDF export-import
# * Explicit tab order
#
# See `doc/RATIONALE.adoc` § "J0 — AcroForm interactif" for full context.

require "./acroform/field"
require "./acroform/text_field"
require "./acroform/checkbox"
require "./acroform/radio_group"
require "./acroform/dropdown"
require "./acroform/listbox"
require "./acroform/form"
