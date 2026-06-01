require "random/secure"

module PDF
  # Represents a PDF document.
  #
  # A PDF document consists of a collection of objects that describe
  # the structure and content of the document. The main components are:
  # - Catalog: The root of the document's object hierarchy
  # - Pages tree: A tree structure containing all pages
  # - Resources: Fonts, images, and other shared resources
  #
  # ## Basic Usage
  #
  # ```
  # pdf = PDF::Document.new
  #
  # pdf.page do |page|
  #   page.font "Helvetica", size: 12
  #   page.text "Hello, World!", at: {72, 720}
  # end
  #
  # pdf.save("output.pdf")
  # ```
  class Document
    # Default page size constants (in points, 72 points = 1 inch)
    PAGE_SIZES = {
      letter:    {612, 792},  # 8.5 x 11 inches
      a4:        {595, 842},  # 210 x 297 mm
      legal:     {612, 1008}, # 8.5 x 14 inches
      tabloid:   {792, 1224}, # 11 x 17 inches
      a3:        {842, 1191}, # 297 x 420 mm
      a5:        {420, 595},  # 148 x 210 mm
      executive: {522, 756},  # 7.25 x 10.5 inches
    }

    # All indirect objects in the document
    getter objects : Array(Objects::Indirect)

    # All pages in the document
    getter pages : Array(Page)

    # Document metadata
    property title : String?
    property author : String?
    property subject : String?
    property keywords : String?
    property creator : String?
    property producer : String = "pdf.cr #{PDF::VERSION}"

    # Next available object ID
    @next_object_id : Int32

    # Catalog object (document root)
    @catalog : Objects::Indirect?

    # Pages tree root
    @pages_root : Objects::Indirect?

    # Registered fonts (name -> font object)
    @fonts : Hash(String, Fonts::Base)

    # Loaded TrueType fonts (path -> font object)
    @truetype_fonts : Hash(String, Fonts::TrueTypeFont)

    # Named destinations (name -> destination array)
    @named_dests : Hash(String, Objects::Array)

    # Document outline (bookmarks)
    @outline : Outline?

    # Interactive form (AcroForm). Nil until `#acroform` is called.
    @acroform : AcroForm::Form?

    # Output intent — declares the colour reproduction characteristics
    # the document was targeted at. Required for PDF/A conformance.
    # Set via `Document#output_intent=`.
    property output_intent : OutputIntent? = nil

    # Cached indirect reference to the embedded Helvetica Type1 dict.
    # Used by AcroForm appearance streams (text field captions,
    # default appearance `/DA`). Created lazily on first access.
    @acroform_helvetica_ref : Objects::Reference?

    # File specifications for attached files (PDF/A-3, Factur-X).
    # Populated via `Document#attach_file`.
    @attached_files : Array(FileSpec) = [] of FileSpec

    # Cross-reference format selector :
    # * `:table` (default) — classic `xref ... trailer << ... >>`
    #   block. Maximum viewer compatibility, slightly more verbose.
    # * `:stream` — `/Type /XRef` cross-reference stream (PDF 1.5+).
    #   Compresses the cross-ref table with Flate, embeds the
    #   trailer in the stream dict. Required by Object streams (J1).
    property xref_format : Symbol = :table

    # When `object_streams` is true, the writer groups all compressible
    # indirect objects (dicts, arrays, names, numbers, strings, bools,
    # nulls) into a single `/Type /ObjStm` and references them with
    # type-2 entries in the cross-reference stream. Streams remain
    # standalone indirect objects.
    #
    # Setting `object_streams = true` requires `xref_format = :stream`
    # (a classic `xref` table cannot reference compressed objects).
    # The setter performs that switch automatically.
    @object_streams : Bool = false

    def object_streams=(value : Bool) : Bool
      @xref_format = :stream if value
      @object_streams = value
    end

    def object_streams? : Bool
      @object_streams
    end

    # AcroForm's catalog reference, computed by `finalize!` *before*
    # pages are finalized so that widget annotations are attached
    # to the right pages' /Annots arrays.
    @acroform_ref : Objects::Reference?

    # Encryption settings (nil = no encryption)
    # Conservé pour rétrocompatibilité — `pdf.encrypt(...)` initialise
    # AUSSI `@security_handler` (le moteur réel de chiffrement) ; les
    # deux pointent sur les mêmes paramètres.
    @encryption : Security::Encryption?

    # Handler de chiffrement (Standard Security Handler) — fournit
    # /Encrypt + chiffrement par-objet RC4 / AES-128 / AES-256.
    # Mis en place par `Document#encrypt(...)` et consommé par le
    # `DocumentWriter`.
    property security_handler : Encryption::StandardSecurity?

    # Premier élément de /ID — file identifier permanent. Généré au
    # premier accès si non fixé (Random::Secure 16 octets).
    @file_id : Bytes?

    # Stamps (Form XObjects) — name => indirect object reference
    @stamps : Hash(String, Objects::Indirect)

    # Cache for finalized TrueType font references (shared across pages).
    # When multiple pages use the same TrueTypeFont object, the PDF objects
    # (Type0 dict, CIDFont, FontDescriptor, FontFile2, CIDToGIDMap, ToUnicode)
    # are created only once and referenced by all pages.
    getter finalized_ttf_refs : Hash(Fonts::TrueTypeFont, Objects::Reference)

    # Cache of SVG parsers keyed by the source string. Rendering the same
    # SVG document multiple times (e.g. repeated country flags in a
    # table column) avoids re-running the XML parser.
    @svg_parsers : Hash(String, SVG::Parser)

    def initialize
      @objects = [] of Objects::Indirect
      @pages = [] of Page
      @next_object_id = 1
      @fonts = {} of String => Fonts::Base
      @truetype_fonts = {} of String => Fonts::TrueTypeFont
      @named_dests = {} of String => Objects::Array
      @stamps = {} of String => Objects::Indirect
      @finalized_ttf_refs = {} of Fonts::TrueTypeFont => Objects::Reference
      @svg_parsers = {} of String => SVG::Parser
    end

    # Returns a cached `SVG::Parser` for `svg_data`, parsing on demand.
    # Two calls with identical strings return the same parser instance,
    # which avoids re-running the XML parser when the same SVG is drawn
    # multiple times on the same document.
    def svg_parser_for(svg_data : String) : SVG::Parser
      @svg_parsers[svg_data] ||= SVG::Parser.new(svg_data)
    end

    # Creates a new page and yields it for content.
    #
    # ```
    # pdf.page do |page|
    #   page.text "Hello!", at: {72, 720}
    # end
    # ```
    def page(width : Number = 612, height : Number = 792, &block : Page ->) : Page
      page = Page.new(self, width.to_f, height.to_f)
      @pages << page
      yield page
      page
    end

    # Creates a new page with a named size.
    #
    # ```
    # pdf.page(size: :a4) do |page|
    #   page.text "A4 page", at: {72, 800}
    # end
    # ```
    def page(size : Symbol, orientation : Symbol = :portrait, &block : Page ->) : Page
      dimensions = PAGE_SIZES[size]? || raise ArgumentError.new("Unknown page size: #{size}")

      width, height = dimensions
      if orientation == :landscape
        width, height = height, width
      end

      page(width, height, &block)
    end

    # Allocates a new object ID.
    def allocate_object_id : Int32
      id = @next_object_id
      @next_object_id += 1
      id
    end

    # Registers an indirect object and returns it.
    def register_object(value : Objects::Base) : Objects::Indirect
      obj = Objects::Indirect.new(allocate_object_id, value)
      @objects << obj
      obj
    end

    # Gets or registers a font by name.
    def font(name : String) : Fonts::Base
      @fonts[name] ||= begin
        if Fonts::Type1::STANDARD_FONTS.includes?(name)
          font = Fonts::Type1.new(name)
          font
        else
          raise ArgumentError.new("Unknown font: #{name}. Use load_font to load TrueType fonts.")
        end
      end
    end

    # Loads a TrueType font from a file path.
    #
    # The font will be automatically subsetted to include only the glyphs
    # used in the document.
    #
    # ```
    # my_font = pdf.load_font("./fonts/OpenSans-Regular.ttf")
    # pdf.page do |page|
    #   page.font my_font, size: 12
    #   page.text "Hello!", at: {72, 720}
    # end
    # ```
    def load_font(path : String) : Fonts::TrueTypeFont
      @truetype_fonts[path] ||= Fonts::TrueTypeFont.load(path)
    end

    # Loads a TrueType font from bytes.
    def load_font(data : Bytes, name : String = "embedded") : Fonts::TrueTypeFont
      @truetype_fonts[name] ||= Fonts::TrueTypeFont.load(data)
    end

    # Gets all TrueType fonts used in this document.
    def truetype_fonts : Hash(String, Fonts::TrueTypeFont)
      @truetype_fonts
    end

    # Adds a named destination to the document.
    #
    # Named destinations allow internal links (from annotations or outline items)
    # to reference a specific page view by name.
    #
    # ```
    # page_ref = page.page_reference
    # dest = PDF::Destination.fit(page_ref)
    # pdf.add_dest("chapter-1", dest)
    # ```
    def add_dest(name : String, dest : Objects::Array) : Nil
      @named_dests[name] = dest
    end

    # Returns the document outline, creating it if needed.
    #
    # ```
    # pdf.outline.define do |o|
    #   o.section("Chapter 1", dest: dest1) do
    #     o.item("Section 1.1", dest: dest2)
    #   end
    # end
    # ```
    def outline : Outline
      @outline ||= Outline.new(self)
    end

    # Returns the document's interactive form, creating it on first
    # access. Yields it to the block if one is given.
    #
    # ```
    # pdf.acroform do |form|
    #   form.text_field("nom", page: page, x: 100, y: 700, width: 200, height: 20)
    #   form.checkbox("rgpd", page: page, x: 100, y: 650)
    # end
    # ```
    def acroform(&) : AcroForm::Form
      form = (@acroform ||= AcroForm::Form.new(self))
      yield form
      form
    end

    # ditto
    def acroform : AcroForm::Form
      @acroform ||= AcroForm::Form.new(self)
    end

    # `true` if the document has an AcroForm with at least one field.
    def acroform? : Bool
      if f = @acroform
        !f.fields.empty?
      else
        false
      end
    end

    # Returns the indirect reference to the embedded Helvetica font
    # used by AcroForm appearance streams. Created and cached on
    # first call so multiple fields share a single font object.
    def acroform_helvetica_ref : Objects::Reference
      @acroform_helvetica_ref ||= begin
        font_obj = font("Helvetica").as(Fonts::Type1)
        register_object(font_obj.to_dictionary).reference
      end
    end

    # Attaches a file to the document. Becomes accessible as an
    # `EmbeddedFile` stream + `FileSpec` dict ; the catalog gets a
    # `/Names /EmbeddedFiles` name tree and an `/AF` array for
    # PDF/A-3 / Factur-X conformance.
    #
    # Exactly one of `path:`, `bytes:` or `io:` must be provided.
    #
    # `relationship:` selects the `/AFRelationship` value (PDF/A-3
    # § 6.8) — `:data` for Factur-X / ZUGFeRD XML, `:source` for
    # the file the PDF was generated from, etc.
    #
    # ```
    # pdf.attach_file(
    #   path: "factur-x.xml",
    #   description: "Factur-X invoice data",
    #   relationship: :data,
    #   mime_type: "application/xml",
    # )
    # ```
    def attach_file(
      *,
      path : String? = nil,
      bytes : Bytes? = nil,
      io : IO? = nil,
      name : String? = nil,
      description : String? = nil,
      relationship : Symbol = :unspecified,
      mime_type : String? = nil,
    ) : FileSpec
      ef = case
           when path
             name ||= File.basename(path)
             EmbeddedFile.from_file(path, mime_type)
           when bytes
             EmbeddedFile.new(bytes, mime_type)
           when io
             content = io.gets_to_end.to_slice
             EmbeddedFile.new(content, mime_type)
           else
             raise ArgumentError.new("attach_file requires one of path:, bytes:, or io:")
           end

      raise ArgumentError.new("attach_file requires a `name:` when bytes/io is given") if name.nil?

      spec = FileSpec.new(
        name: name,
        embedded_file: ef,
        description: description,
        relationship: relationship,
      )
      @attached_files << spec
      spec
    end

    # `true` if at least one file is attached.
    def attached_files? : Bool
      !@attached_files.empty?
    end

    getter attached_files : Array(FileSpec)

    # Chiffre le document avec un mot de passe et un niveau de
    # protection (RC4 128-bit, AES-128 ou AES-256).
    #
    # ```
    # pdf.encrypt(
    #   user_password: "",
    #   owner_password: "secret",
    #   permissions: [PDF::Security::Permission::Print],
    #   level: :aes_256, # défaut — PDF 2.0 / Acrobat ≥ X
    # )
    # ```
    #
    # Niveaux disponibles (cf. `Encryption::StandardSecurity::Level`) :
    # * `:rc4_128` — RC4 128-bit (V=2, R=3). Compatible Acrobat ≥ 5
    #   mais cryptographiquement faible. À éviter sauf legacy.
    # * `:aes_128` — AES-128-CBC (V=4, R=4 + CryptFilter AESV2).
    #   Compatible Acrobat ≥ 7. Bon compromis.
    # * `:aes_256` — AES-256-CBC (V=5, R=6, PDF 2.0). Compatible
    #   Acrobat ≥ X. À privilégier pour les nouveaux documents.
    def encrypt(
      user_password : String = "",
      owner_password : String = "",
      permissions : Array(Security::Permission) = [Security::Permission::Print],
      level : Symbol = :aes_256,
      encrypt_metadata : Bool = true,
    ) : Nil
      lvl = case level
            when :rc4_128 then Encryption::StandardSecurity::Level::RC4_128
            when :aes_128 then Encryption::StandardSecurity::Level::AES_128
            when :aes_256 then Encryption::StandardSecurity::Level::AES_256
            else
              raise ArgumentError.new("Niveau de chiffrement inconnu : #{level.inspect} (attendu :rc4_128, :aes_128 ou :aes_256)")
            end

      perms_value = compute_permissions_value(permissions)
      @security_handler = Encryption::StandardSecurity.build_for_encryption(
        user_password: user_password,
        owner_password: owner_password.empty? ? user_password : owner_password,
        level: lvl,
        permissions: perms_value,
        id: file_id,
        encrypt_metadata: encrypt_metadata,
      )
      # Conservé pour rétrocompatibilité (les anciens specs vérifient
      # que `@encryption` est défini après un appel à `encrypt`).
      @encryption = Security::Encryption.new(
        user_password: user_password,
        owner_password: owner_password,
        permissions: permissions,
        key_length: lvl.rc4_128? ? 128 : 128, # purement informatif
      )
    end

    # Surcharge legacy : conserve `key_length:` pour ne pas casser
    # le code existant. Mappe vers `level:` automatiquement.
    def encrypt(
      *,
      user_password : String = "",
      owner_password : String = "",
      permissions : Array(Security::Permission) = [Security::Permission::Print],
      key_length : Int32,
    ) : Nil
      level = case key_length
              when 40, 128 then :rc4_128
              else
                raise ArgumentError.new("key_length doit être 40 ou 128 ; pour AES, utilisez `level: :aes_128` ou `:aes_256`.")
              end
      encrypt(
        user_password: user_password,
        owner_password: owner_password,
        permissions: permissions,
        level: level,
      )
    end

    # Returns the encryption settings, or nil if not encrypted.
    def encryption : Security::Encryption?
      @encryption
    end

    # Renvoie le premier élément du /ID du document, en générant
    # 16 octets aléatoires au premier accès. C'est ce qui est
    # injecté dans la dérivation de la clé du fichier (V=1/2/4) et
    # écrit comme premier élément du tableau /ID dans le trailer.
    def file_id : Bytes
      @file_id ||= Random::Secure.random_bytes(16)
    end

    # Permet d'imposer un /ID explicite (utile pour reproduire un
    # document à l'octet près, ou pour des tests déterministes).
    def file_id=(id : Bytes) : Bytes
      @file_id = id
    end

    # `true` si un /ID a déjà été matérialisé (utilisé par le writer
    # pour décider d'écrire le tableau /ID dans le trailer même sans
    # chiffrement).
    def has_file_id? : Bool
      !@file_id.nil?
    end

    # Calcule la valeur entière du champ /P (permissions) selon le
    # spec § 7.6.3.2.
    private def compute_permissions_value(permissions : Array(Security::Permission)) : Int32
      value = -1_i32
      value &= ~0b00111100 # bits 3..6 à 0
      permissions.each { |p| value |= p.value }
      value &= ~0b11 # bits 1..2 à 0
      value
    end

    # Creates a reusable stamp (Form XObject).
    # The block receives a Page object for drawing content.
    # Returns the indirect object reference to use with Page#stamp.
    #
    # ```
    # stamp_ref = pdf.create_stamp("watermark", 200, 50) do |page|
    #   page.fill_color(0.8, 0.8, 0.8)
    #   page.font "Helvetica", size: 36
    #   page.text "DRAFT", at: {10, 15}
    # end
    #
    # pdf.page do |page|
    #   page.stamp(stamp_ref)
    # end
    # ```
    def create_stamp(name : String, width : Number = 612, height : Number = 792, &block : Page ->) : Objects::Reference
      raise ArgumentError.new("Stamp name cannot be empty") if name.empty?
      raise ArgumentError.new("Stamp '#{name}' already exists") if @stamps.has_key?(name)

      # Create a temporary page for drawing
      stamp_page = Page.new(self, width.to_f, height.to_f)
      yield stamp_page

      # Finalize the stamp page to get its content
      stamp_page.finalize!

      # Build the Form XObject
      form_dict = Objects::Dictionary.new
      form_dict["Type"] = Objects::Name.new("XObject")
      form_dict["Subtype"] = Objects::Name.new("Form")

      bbox = Objects::Array.new
      bbox << Objects::Number.new(0)
      bbox << Objects::Number.new(0)
      bbox << Objects::Number.new(width.to_i)
      bbox << Objects::Number.new(height.to_i)
      form_dict["BBox"] = bbox

      # Create the Form XObject as a stream with the page content
      stream = Objects::Stream.new
      content_str = stamp_page.content_string
      stream.data = content_str
      stream.add_filter(Filters::Flate.new) unless content_str.empty?

      # Copy resources from the stamp page
      resources = stamp_page.build_resources_public
      stream["Resources"] = resources unless resources.empty?

      # Merge the form dictionary into the stream
      form_dict.each do |key, value|
        stream[key] = value
      end

      stamp_obj = register_object(stream)
      @stamps[name] = stamp_obj
      stamp_obj.reference
    end

    # Returns a stamp reference by name.
    def stamp(name : String) : Objects::Reference
      obj = @stamps[name]? || raise ArgumentError.new("Unknown stamp: #{name}")
      obj.reference
    end

    # Saves the document to a file.
    def save(path : String) : Nil
      File.open(path, "wb") do |file|
        write(file)
      end
    end

    # Writes the document to an IO.
    def write(io : IO) : Nil
      writer = Writer::DocumentWriter.new(self)
      writer.write(io)
    end

    # Returns the document as bytes.
    def to_slice : Bytes
      io = IO::Memory.new
      write(io)
      io.to_slice
    end

    # Builds and returns the catalog object.
    def catalog : Objects::Indirect
      @catalog ||= build_catalog
    end

    # Builds and returns the pages tree root.
    def pages_root : Objects::Indirect
      @pages_root ||= build_pages_tree
    end

    # Returns the document info dictionary, or nil if no metadata.
    def info_dict : Objects::Dictionary?
      dict = Objects::Dictionary.new

      dict["Title"] = Objects::Str.unicode(@title.not_nil!) if @title
      dict["Author"] = Objects::Str.unicode(@author.not_nil!) if @author
      dict["Subject"] = Objects::Str.unicode(@subject.not_nil!) if @subject
      dict["Keywords"] = Objects::Str.unicode(@keywords.not_nil!) if @keywords
      dict["Creator"] = Objects::Str.unicode(@creator.not_nil!) if @creator
      dict["Producer"] = Objects::Str.unicode(@producer)

      # Add creation date
      dict["CreationDate"] = Objects::Str.new(pdf_date(Time.utc))

      dict.empty? ? nil : dict
    end

    # Finalizes all pages and objects for writing.
    # Called by the writer before serialization.
    def finalize! : Nil
      # Pre-finalize AcroForm so widget annotation references are
      # attached to each page's /Annots *before* the page is
      # finalized. Without this, the widgets would be registered as
      # indirect objects but never linked from /Annots.
      if (form = @acroform) && !form.fields.empty?
        @acroform_ref = form.finalize!
      end

      # Finalize each page (creates content streams, registers resources)
      @pages.each(&.finalize!)

      # Build the pages tree
      pages_root

      # Build the catalog
      catalog
    end

    private def build_catalog : Objects::Indirect
      dict = Objects::Dictionary.new
      dict["Type"] = Objects::Name::CATALOG
      dict["Pages"] = pages_root.reference

      # Add named destinations if any
      unless @named_dests.empty?
        dests_dict = Objects::Dictionary.new
        @named_dests.each do |name, dest|
          dests_dict[name] = dest
        end
        dict["Dests"] = dests_dict
      end

      # Add outline (bookmarks) if defined
      if outline_obj = @outline
        if outline_ref = outline_obj.finalize!
          dict["Outlines"] = outline_ref
        end
      end

      # Add /AcroForm if it was pre-finalized in `#finalize!`.
      if ref = @acroform_ref
        dict["AcroForm"] = ref
      end

      # Add /OutputIntents if an output intent was set. PDF allows
      # several intents per document, but ALOLI ships one at a time
      # in this MVP.
      if oi = @output_intent
        profile_stream = oi.dest_output_profile.to_stream
        profile_obj = register_object(profile_stream)
        intent_dict = oi.to_dictionary(profile_obj.reference)
        intent_obj = register_object(intent_dict)
        intents = Objects::Array.new
        intents << intent_obj.reference
        dict["OutputIntents"] = intents
      end

      # Add attached files (PDF/A-3, Factur-X). Each FileSpec is
      # registered as an indirect object ; the catalog gets a /AF
      # array (PDF 2.0, accepted by PDF/A-3 validators) and a
      # /Names /EmbeddedFiles name tree (PDF 1.x compatibility).
      unless @attached_files.empty?
        af_refs = [] of Objects::Reference
        name_tree_entries = [] of {String, Objects::Reference}

        @attached_files.each do |spec|
          ef_stream = spec.embedded_file.to_stream
          ef_obj = register_object(ef_stream)
          spec_dict = spec.to_dictionary(ef_obj.reference)
          spec_obj = register_object(spec_dict)
          af_refs << spec_obj.reference
          name_tree_entries << {spec.name, spec_obj.reference}
        end

        # /AF — PDF 2.0 and PDF/A-3 location.
        af = Objects::Array.new
        af_refs.each { |r| af << r }
        dict["AF"] = af

        # /Names /EmbeddedFiles /Names [name spec name spec ...] —
        # PDF 1.x legacy location, still expected by many viewers.
        names_subdict = Objects::Dictionary.new
        names_arr = Objects::Array.new
        name_tree_entries.each do |entry|
          names_arr << Objects::Str.new(entry[0])
          names_arr << entry[1]
        end
        names_subdict["Names"] = names_arr

        embedded_files = Objects::Dictionary.new
        embedded_files["EmbeddedFiles"] = names_subdict

        # Merge with an existing /Names if /Dests already created
        # one (named destinations). For the MVP we replace ; named
        # destinations live under /Dests, not /Names.
        dict["Names"] = embedded_files
      end

      # Add XMP metadata
      xmp_stream = Metadata::XMP.build(
        title: @title,
        author: @author,
        subject: @subject,
        keywords: @keywords,
        creator: @creator,
        producer: @producer
      )
      xmp_obj = register_object(xmp_stream)
      dict["Metadata"] = xmp_obj.reference

      register_object(dict)
    end

    private def build_pages_tree : Objects::Indirect
      # Create the pages tree root
      pages_dict = Objects::Dictionary.new
      pages_dict["Type"] = Objects::Name::PAGES

      # Register pages tree first to get its reference
      pages_obj = register_object(pages_dict)

      # Build kids array with references to all pages
      kids = Objects::Array.new
      @pages.each do |page|
        page_obj = page.to_indirect_object(pages_obj.reference)
        kids << page_obj.reference
      end

      pages_dict["Kids"] = kids
      pages_dict["Count"] = Objects::Number.new(@pages.size)

      pages_obj
    end

    private def pdf_date(time : Time) : String
      # PDF date format: D:YYYYMMDDHHmmSSOHH'mm'
      # Example: D:20240115123045+00'00'
      offset = time.offset
      offset_hours = offset // 3600
      offset_minutes = (offset.abs % 3600) // 60
      sign = offset >= 0 ? "+" : "-"

      "D:#{time.to_s("%Y%m%d%H%M%S")}#{sign}#{offset_hours.abs.to_s.rjust(2, '0')}'#{offset_minutes.to_s.rjust(2, '0')}'"
    end
  end
end
