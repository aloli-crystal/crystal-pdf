module PDF
  module Metadata
    # Generates an XMP metadata stream for inclusion in a PDF document.
    #
    # XMP (Extensible Metadata Platform) embeds metadata as XML in the
    # document catalog's /Metadata entry. Per the PDF spec, this stream
    # must be uncompressed (no filters).
    module XMP
      # Builds an XMP metadata stream object.
      def self.build(
        title : String? = nil,
        author : String? = nil,
        subject : String? = nil,
        keywords : String? = nil,
        creator : String? = nil,
        producer : String = "pdf.cr #{PDF::VERSION}",
        creation_date : Time = Time.utc,
        modification_date : Time = Time.utc,
        pdfa_part : Int32? = nil,
        pdfa_conformance : String? = nil,
      ) : Objects::Stream
        xml = generate_xml(
          title: title,
          author: author,
          subject: subject,
          keywords: keywords,
          creator: creator,
          producer: producer,
          creation_date: creation_date,
          modification_date: modification_date,
          pdfa_part: pdfa_part,
          pdfa_conformance: pdfa_conformance
        )

        stream = Objects::Stream.new
        stream.data = xml
        # XMP metadata must NOT be compressed (PDF spec requirement)
        stream["Type"] = Objects::Name.new("Metadata")
        stream["Subtype"] = Objects::Name.new("XML")
        stream
      end

      # Generates the XMP XML string.
      private def self.generate_xml(
        title : String?,
        author : String?,
        subject : String?,
        keywords : String?,
        creator : String?,
        producer : String,
        creation_date : Time,
        modification_date : Time,
        pdfa_part : Int32? = nil,
        pdfa_conformance : String? = nil,
      ) : String
        create_iso = xmp_date(creation_date)
        modify_iso = xmp_date(modification_date)

        String.build do |io|
          io << %(<?xpacket begin="\xEF\xBB\xBF" id="W5M0MpCehiHzreSzNTczkc9d"?>\n)
          io << %(<x:xmpmeta xmlns:x="adobe:ns:meta/">\n)
          io << %(<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">\n)
          io << %(<rdf:Description rdf:about=""\n)
          io << %(  xmlns:dc="http://purl.org/dc/elements/1.1/"\n)
          io << %(  xmlns:xmp="http://ns.adobe.com/xap/1.0/"\n)
          io << %(  xmlns:pdf="http://ns.adobe.com/pdf/1.3/"\n)
          io << %(  xmlns:pdfaid="http://www.aiim.org/pdfa/ns/id/">\n)

          # Dublin Core: title
          if t = title
            io << %(<dc:title><rdf:Alt><rdf:li xml:lang="x-default">)
            io << escape_xml(t)
            io << %(</rdf:li></rdf:Alt></dc:title>\n)
          end

          # Dublin Core: creator (author)
          if a = author
            io << %(<dc:creator><rdf:Seq><rdf:li>)
            io << escape_xml(a)
            io << %(</rdf:li></rdf:Seq></dc:creator>\n)
          end

          # Dublin Core: description (subject)
          if s = subject
            io << %(<dc:description><rdf:Alt><rdf:li xml:lang="x-default">)
            io << escape_xml(s)
            io << %(</rdf:li></rdf:Alt></dc:description>\n)
          end

          # Dublin Core: subject (keywords)
          if k = keywords
            io << %(<dc:subject><rdf:Bag>)
            k.split(",").each do |kw|
              io << %(<rdf:li>) << escape_xml(kw.strip) << %(</rdf:li>)
            end
            io << %(</rdf:Bag></dc:subject>\n)
          end

          # XMP: CreatorTool
          if c = creator
            io << %(<xmp:CreatorTool>) << escape_xml(c) << %(</xmp:CreatorTool>\n)
          end

          # PDF: Producer
          io << %(<pdf:Producer>) << escape_xml(producer) << %(</pdf:Producer>\n)

          # XMP dates
          io << %(<xmp:CreateDate>) << create_iso << %(</xmp:CreateDate>\n)
          io << %(<xmp:ModifyDate>) << modify_iso << %(</xmp:ModifyDate>\n)

          # PDF/A identification (pdfaid). REQUIRED for a conforming
          # PDF/A file : declares the part (1/2/3/4) and conformance
          # level (A/B/U). Emitted only when set by the pdf-a shard.
          if part = pdfa_part
            io << %(<pdfaid:part>) << part << %(</pdfaid:part>\n)
          end
          if conf = pdfa_conformance
            io << %(<pdfaid:conformance>) << escape_xml(conf) << %(</pdfaid:conformance>\n)
          end

          io << %(</rdf:Description>\n)
          io << %(</rdf:RDF>\n)
          io << %(</x:xmpmeta>\n)

          # Padding (recommended by XMP spec to allow in-place editing)
          20.times { io << "                                                                                \n" }

          io << %(<?xpacket end="w"?>)
        end
      end

      # Format a Time as XMP date (ISO 8601)
      private def self.xmp_date(time : Time) : String
        time.to_s("%Y-%m-%dT%H:%M:%S%:z")
      end

      # Escape XML special characters
      private def self.escape_xml(text : String) : String
        text.gsub('&', "&amp;")
          .gsub('<', "&lt;")
          .gsub('>', "&gt;")
          .gsub('"', "&quot;")
      end
    end
  end
end
