# A pure Crystal library for PDF generation and parsing.
#
# ## Quick Start
#
# ```
# require "pdf"
#
# pdf = PDF::Document.new
#
# pdf.page do |page|
#   page.font "Helvetica", size: 12
#   page.text "Hello, Crystal!", at: {72, 720}
# end
#
# pdf.save("output.pdf")
# ```
module PDF
  # Lue au compile-time depuis `shard.yml` via le macro `read_file`,
  # pour qu'on ne puisse plus jamais désynchroniser la constante
  # Crystal du `version:` du shard.yml. Cf. note mémoire
  # `feedback_shard_version_macro.md`.
  VERSION = {{
              (read_file("#{__DIR__}/../shard.yml")
                .lines
                .find(&.starts_with?("version:")) || "version: 0.0.0")
                .gsub(/^version:\s*/, "")
                .chomp
            }}

  # PDF version to generate (1.7 = ISO 32000-1:2008)
  PDF_VERSION = "1.7"

  # Upstream Prawn gem version we track for feature parity
  UPSTREAM_VERSION = "2.5.0"
end

# Core object model (order matters - base first)
require "./pdf/objects/base"
require "./pdf/objects/null"
require "./pdf/objects/boolean"
require "./pdf/objects/number"
require "./pdf/objects/name"
require "./pdf/objects/string"
require "./pdf/objects/array"
require "./pdf/objects/dictionary"
require "./pdf/objects/reference"
require "./pdf/objects/stream"
require "./pdf/objects/indirect"
require "./pdf/objects/ext_g_state"

# Filters (compression/encoding)
require "./pdf/filters/base"
require "./pdf/filters/flate"
require "./pdf/filters/dct"

# Content stream operations
require "./pdf/content/color"
require "./pdf/content/graphics_state"

# Font handling
require "./pdf/fonts/base"
require "./pdf/fonts/type1"
require "./pdf/fonts/truetype"
require "./pdf/fonts/truetype_font"
require "./pdf/fonts/icon_font"

# Image handling
require "./pdf/images/base"
require "./pdf/images/jpeg"
require "./pdf/images/png"
require "./pdf/images/image"

# Document writer
require "./pdf/writer/document_writer"

# Text layout engine
require "./pdf/text/formatted"

# Layout engine
require "./pdf/layout"

# Table engine
require "./pdf/table"

# SVG rendering engine
require "./pdf/svg"

# Gradient support
require "./pdf/gradient/gradient"

# Security / Encryption
require "./pdf/security/arcfour"
require "./pdf/security/encryption"

# XMP Metadata
require "./pdf/metadata/xmp"

# Annotations, destinations, and outline (bookmarks)
require "./pdf/annotations"
require "./pdf/destinations"
require "./pdf/outline"

# Chiffrement (Standard Security Handler — RC4 + AES)
require "./pdf/encryption/rc4"
require "./pdf/encryption/aes"
require "./pdf/encryption/standard_security"

# PDF reader (analyseur et lecteur)
require "./pdf/parser"
require "./pdf/reader_page"
require "./pdf/reader"

# Document structure
require "./pdf/document"
require "./pdf/page"
require "./pdf/page_formatted_text"
require "./pdf/page_bounding_box"
require "./pdf/page_table"
require "./pdf/page_svg"

# Interactive forms (AcroForm — PDF spec § 12.7)
require "./pdf/acroform"
