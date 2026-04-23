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

    # Encryption settings (nil = no encryption)
    @encryption : Security::Encryption?

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

    # Encrypts the document with password protection and permission control.
    #
    # ```
    # pdf.encrypt(
    #   user_password: "",
    #   owner_password: "secret",
    #   permissions: [PDF::Security::Permission::Print]
    # )
    # ```
    def encrypt(
      user_password : String = "",
      owner_password : String = "",
      permissions : Array(Security::Permission) = [Security::Permission::Print],
      key_length : Int32 = 40,
    ) : Nil
      @encryption = Security::Encryption.new(
        user_password: user_password,
        owner_password: owner_password,
        permissions: permissions,
        key_length: key_length
      )
    end

    # Returns the encryption settings, or nil if not encrypted.
    def encryption : Security::Encryption?
      @encryption
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
