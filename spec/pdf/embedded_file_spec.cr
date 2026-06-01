require "../spec_helper"

describe PDF::EmbeddedFile do
  describe ".new" do
    it "carries the raw bytes and the mime type" do
      ef = PDF::EmbeddedFile.new("hello".to_slice, mime_type: "text/plain")
      ef.data.size.should eq(5)
      ef.mime_type.should eq("text/plain")
    end
  end

  describe "#to_stream" do
    it "emits /Type /EmbeddedFile with /Params (Size, ModDate, CheckSum)" do
      ef = PDF::EmbeddedFile.new("hello world".to_slice, mime_type: "text/plain")
      stream = ef.to_stream
      stream["Type"].to_pdf.should eq("/EmbeddedFile")
      # PDF Name escape : `/` becomes `#2F` (spec § 7.3.5).
      stream["Subtype"].to_pdf.should eq("/text#2Fplain")
      params = stream["Params"].as(PDF::Objects::Dictionary)
      params["Size"].to_pdf.should eq("11")
      params.has_key?("ModDate").should be_true
      params.has_key?("CheckSum").should be_true
    end
  end
end

describe PDF::FileSpec do
  it "rejects an unknown relationship" do
    ef = PDF::EmbeddedFile.new("x".to_slice)
    expect_raises(ArgumentError, /Unknown.*AFRelationship/) do
      PDF::FileSpec.new(name: "x", embedded_file: ef, relationship: :bogus)
    end
  end

  it "emits a /Filespec dict with /F /UF /EF /AFRelationship" do
    ef = PDF::EmbeddedFile.new("invoice".to_slice)
    spec = PDF::FileSpec.new(
      name: "factur-x.xml",
      embedded_file: ef,
      description: "Factur-X data",
      relationship: :data,
    )
    fake_ref = PDF::Objects::Reference.new(7)
    d = spec.to_dictionary(fake_ref)
    d["Type"].to_pdf.should eq("/Filespec")
    d["F"].to_pdf.should eq("(factur-x.xml)")
    d["AFRelationship"].to_pdf.should eq("/Data")
    ef_dict = d["EF"].as(PDF::Objects::Dictionary)
    ef_dict["F"].to_pdf.should eq("7 0 R")
  end
end

describe "Document#attach_file (integration)" do
  it "emits /AF in the catalog and a /Names /EmbeddedFiles tree" do
    pdf = PDF::Document.new
    pdf.page { |_| }
    pdf.attach_file(
      bytes: "invoice".to_slice,
      name: "factur-x.xml",
      description: "Factur-X invoice data",
      relationship: :data,
      mime_type: "application/xml",
    )

    bytes = pdf.to_slice
    out = bytes.map(&.chr).join
    out.should contain("/AF")
    out.should contain("/Filespec")
    out.should contain("/AFRelationship /Data")
    out.should contain("/EmbeddedFile")
    out.should contain("/EmbeddedFiles")
    out.should contain("(factur-x.xml)")
  end

  it "rejects attach_file with no source" do
    pdf = PDF::Document.new
    expect_raises(ArgumentError, /requires one of path:, bytes:, or io:/) do
      pdf.attach_file(name: "x.xml")
    end
  end

  it "requires a `name:` for bytes-based attachments" do
    pdf = PDF::Document.new
    expect_raises(ArgumentError, /requires a `name:`/) do
      pdf.attach_file(bytes: "x".to_slice)
    end
  end
end
