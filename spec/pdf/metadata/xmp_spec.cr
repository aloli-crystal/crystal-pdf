require "../../spec_helper"

describe PDF::Metadata::XMP do
  describe ".build" do
    it "creates an XMP metadata stream" do
      stream = PDF::Metadata::XMP.build(
        title: "Test Document",
        author: "Test Author",
        creator: "Test Creator"
      )
      stream.should be_a(PDF::Objects::Stream)
    end

    it "sets Type to Metadata" do
      stream = PDF::Metadata::XMP.build
      pdf = stream.to_pdf
      pdf.should contain("/Type /Metadata")
    end

    it "sets Subtype to XML" do
      stream = PDF::Metadata::XMP.build
      pdf = stream.to_pdf
      pdf.should contain("/Subtype /XML")
    end

    it "is not compressed (per PDF spec)" do
      stream = PDF::Metadata::XMP.build(title: "Test")
      pdf = stream.to_pdf
      # Should NOT contain FlateDecode filter
      pdf.should_not contain("FlateDecode")
    end

    it "contains xpacket markers" do
      stream = PDF::Metadata::XMP.build(title: "Test")
      xml = String.new(stream.data)
      xml.should contain("<?xpacket begin=")
      xml.should contain("<?xpacket end=")
    end

    it "includes title in Dublin Core" do
      stream = PDF::Metadata::XMP.build(title: "My Title")
      xml = String.new(stream.data)
      xml.should contain("My Title")
      xml.should contain("dc:title")
    end

    it "includes author in Dublin Core creator" do
      stream = PDF::Metadata::XMP.build(author: "John Doe")
      xml = String.new(stream.data)
      xml.should contain("John Doe")
      xml.should contain("dc:creator")
    end

    it "includes producer" do
      stream = PDF::Metadata::XMP.build(producer: "TestLib 1.0")
      xml = String.new(stream.data)
      xml.should contain("TestLib 1.0")
      xml.should contain("pdf:Producer")
    end

    it "includes creation date" do
      stream = PDF::Metadata::XMP.build
      xml = String.new(stream.data)
      xml.should contain("xmp:CreateDate")
    end

    it "includes modification date" do
      stream = PDF::Metadata::XMP.build
      xml = String.new(stream.data)
      xml.should contain("xmp:ModifyDate")
    end

    it "escapes XML special characters" do
      stream = PDF::Metadata::XMP.build(title: "A < B & C > D")
      xml = String.new(stream.data)
      xml.should contain("A &lt; B &amp; C &gt; D")
    end

    it "handles keywords" do
      stream = PDF::Metadata::XMP.build(keywords: "crystal, pdf, library")
      xml = String.new(stream.data)
      xml.should contain("dc:subject")
      xml.should contain("crystal")
      xml.should contain("pdf")
      xml.should contain("library")
    end
  end

  describe "document integration" do
    it "includes XMP metadata in the catalog" do
      doc = PDF::Document.new
      doc.title = "XMP Test"
      doc.author = "Test Author"

      doc.page do |page|
        page.font "Helvetica", size: 12
        page.text "Hello", at: {72, 720}
      end

      bytes = doc.to_slice
      content = String.new(bytes)
      content.should contain("/Metadata")
      content.should contain("/Type /Metadata")
      content.should contain("/Subtype /XML")
    end
  end
end
