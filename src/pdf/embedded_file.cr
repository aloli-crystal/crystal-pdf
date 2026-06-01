require "digest/md5"

module PDF
  # Embedded file stream (PDF spec § 7.11.4) — wraps the raw bytes
  # of a file plus a `/Params` dict with size, dates and checksum.
  #
  # `EmbeddedFile` is the *stream* half ; `FileSpec` is the *dict*
  # half that references it. Both are emitted via
  # `Document#attach_file`.
  class EmbeddedFile
    getter data : Bytes
    getter mime_type : String?
    getter creation_date : Time
    getter modification_date : Time

    # Builds an embedded-file payload from raw bytes.
    #
    # `mime_type` is optional but recommended — PDF/A-3 § 6.8 expects
    # the `/Subtype` entry to carry the MIME type. The string is
    # name-escaped (e.g. `application/xml` → `/application#2Fxml`).
    def initialize(
      @data : Bytes,
      @mime_type : String? = nil,
      @creation_date : Time = Time.utc,
      @modification_date : Time = Time.utc,
    )
    end

    # Convenience : load from a path on disk. Sets dates from the
    # file's mtime when available.
    def self.from_file(path : String, mime_type : String? = nil) : EmbeddedFile
      bytes = File.read(path).to_slice
      stat = File.info(path)
      new(
        data: bytes,
        mime_type: mime_type,
        creation_date: stat.modification_time,
        modification_date: stat.modification_time,
      )
    end

    # Builds the indirect stream object that PDF readers see.
    def to_stream : Objects::Stream
      stream = Objects::Stream.new
      stream["Type"] = Objects::Name.new("EmbeddedFile")
      if mime = @mime_type
        stream["Subtype"] = Objects::Name.new(mime)
      end

      params = Objects::Dictionary.new
      params["Size"] = Objects::Number.new(@data.size)
      params["CreationDate"] = Objects::Str.new(format_pdf_date(@creation_date))
      params["ModDate"] = Objects::Str.new(format_pdf_date(@modification_date))
      params["CheckSum"] = Objects::Str.new(String.new(Digest::MD5.digest(@data)))
      stream["Params"] = params

      stream.data = @data
      stream.add_filter(Filters::Flate.new)
      stream
    end

    # Formats a `Time` per the PDF date format (PDF spec § 7.9.4) :
    # `D:YYYYMMDDHHmmSSOHH'mm'`.
    private def format_pdf_date(time : Time) : String
      offset = time.offset
      offset_hours = offset // 3600
      offset_minutes = (offset.abs % 3600) // 60
      sign = offset >= 0 ? "+" : "-"
      "D:#{time.to_s("%Y%m%d%H%M%S")}#{sign}#{offset_hours.abs.to_s.rjust(2, '0')}'#{offset_minutes.to_s.rjust(2, '0')}'"
    end
  end

  # File specification dict (PDF spec § 7.11.3). Carries the file
  # name, description, an indirect reference to the embedded stream,
  # and a relationship value (PDF/A-3 § 6.8 — `/Data`, `/Source`,
  # `/Alternative`, `/Supplement`, `/Unspecified`).
  class FileSpec
    # PDF/A-3 § 6.8 enumeration of `/AFRelationship` values.
    VALID_RELATIONSHIPS = {
      data:              "Data",             # data referenced by the PDF content
      source:            "Source",           # source the PDF was generated from
      alternative:       "Alternative",      # alternative representation of the PDF content
      supplement:        "Supplement",       # additional material
      encrypted_payload: "EncryptedPayload", # an encrypted payload (PDF 2.0)
      form_data:         "FormData",         # data describing how to fill the form (PDF 2.0)
      unspecified:       "Unspecified",      # default when nothing else fits
    }

    getter name : String
    getter description : String?
    getter relationship : Symbol
    getter embedded_file : EmbeddedFile

    def initialize(
      @name : String,
      @embedded_file : EmbeddedFile,
      @description : String? = nil,
      @relationship : Symbol = :unspecified,
    )
      unless VALID_RELATIONSHIPS.has_key?(@relationship)
        raise ArgumentError.new("Unknown /AFRelationship #{@relationship.inspect}. Valid : #{VALID_RELATIONSHIPS.keys.inspect}")
      end
    end

    # Builds the indirect dict. Caller registers the embedded stream
    # first and passes its reference.
    def to_dictionary(embedded_ref : Objects::Reference) : Objects::Dictionary
      d = Objects::Dictionary.new
      d["Type"] = Objects::Name.new("Filespec")
      # Both /F (PDFDocEncoding) and /UF (UTF-16BE) — viewers prefer
      # the latter ; the former is kept for legacy compatibility.
      d["F"] = Objects::Str.new(@name)
      d["UF"] = Objects::Str.unicode(@name)
      if desc = @description
        d["Desc"] = Objects::Str.unicode(desc)
      end
      d["AFRelationship"] = Objects::Name.new(VALID_RELATIONSHIPS[@relationship])
      ef = Objects::Dictionary.new
      ef["F"] = embedded_ref
      ef["UF"] = embedded_ref
      d["EF"] = ef
      d
    end
  end
end
