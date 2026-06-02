# CFF (Compact Font Format) parser — Adobe CFF specification, also
# embedded in OpenType (.otf) fonts as the `CFF ` table.
#
# This module is the first palier (0.6.1) of CFF support in
# `aloli-crystal/pdf` :
#
# * **0.6.1 — this file** : read-only parser. Decodes the CFF
#   structure into in-memory objects (INDEX, DICT, CharStrings,
#   subroutines, FD arrays for CIDFonts). No bytecode interpretation,
#   no modification.
# * **0.6.2 — next palier** : Type 2 charstring analyser. Walks the
#   bytecode of each glyph to identify the referenced global and
#   local subroutines.
# * **0.6.3 — next palier** : subsetter. Selects GIDs, collects
#   the transitive subr closure, rebuilds the CFF tables with
#   renumbered indices.
# * **0.6.4 — next palier** : wires OTF/CFF into `TrueTypeFont.load`
#   so `.otf` files (notably Noto CJK) are subsetted natively
#   instead of raising `UnsupportedFontFormat`.
#
# See `roadmap_pdf_cff_subsetting.md` in the user's memory for the
# rationale.

require "./truetype/io_helpers"
require "./cff/index"
require "./cff/dict"
require "./cff/parser"
require "./cff/type2_analyser"
