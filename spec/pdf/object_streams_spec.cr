require "../spec_helper"

describe "Object streams (object_streams = true)" do
  it "is false by default" do
    PDF::Document.new.object_streams?.should be_false
  end

  it "setting object_streams = true forces xref_format = :stream" do
    pdf = PDF::Document.new
    pdf.xref_format.should eq(:table)
    pdf.object_streams = true
    pdf.xref_format.should eq(:stream)
  end

  it "emits a /Type /ObjStm in the PDF when enabled" do
    pdf = PDF::Document.new
    pdf.object_streams = true
    pdf.page do |p|
      p.font "Helvetica", size: 12
      p.text "Hello", at: {72, 720}
    end

    bytes = pdf.to_slice
    out = bytes.map(&.chr).join

    out.should contain("/Type /ObjStm")
    out.should contain("/N ") # number of compressed objects
    out.should contain("/First ")
  end

  it "produces a readable PDF (round-trip via PDF::Reader)" do
    pdf = PDF::Document.new
    pdf.object_streams = true
    pdf.title = "ObjStm round-trip"
    pdf.page do |p|
      p.font "Helvetica", size: 12
      p.text "Compressed", at: {72, 720}
    end

    bytes = pdf.to_slice
    reader = PDF::Reader.new(bytes)
    reader.page_count.should eq(1)
  end

  it "is smaller than the same document with object_streams off" do
    text = "X" * 200
    build = ->(compress : Bool) {
      pdf = PDF::Document.new
      pdf.object_streams = compress
      3.times do
        pdf.page do |p|
          p.font "Helvetica", size: 12
          p.text text, at: {72, 720}
        end
      end
      pdf.to_slice.size
    }
    compressed_size = build.call(true)
    uncompressed_size = build.call(false)
    compressed_size.should be < uncompressed_size
  end
end
