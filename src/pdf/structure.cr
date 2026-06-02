# Tagged PDF logical structure (PDF 32000-1 § 14.7-14.8) — the
# foundation of PDF/UA accessibility and PDF/A-2u/3 semantic
# structure.
#
# This is palier 0.7.0 (J2 of the ISO trajectory) : the structure
# *object model*. It builds a `/StructTreeRoot` with a hierarchy of
# `/StructElem`s, plus the catalog `/MarkInfo` and `/Lang` entries.
#
# Not yet here (palier 0.7.1+) :
# * Marked-content operators (BDC/EMC + MCID) in page content
#   streams, which tie structure elements to rendered glyphs.
# * The `/ParentTree` number tree (MCID → structure element).
# * A high-level tagging DSL (`page.tag(:h1) { ... }`).
#
# See `doc/RATIONALE.adoc` § J2.

require "./structure/tag"
require "./structure/struct_elem"
require "./structure/struct_tree"
