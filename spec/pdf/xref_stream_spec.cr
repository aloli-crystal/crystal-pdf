require "../spec_helper"

describe "Cross-reference stream (xref_format = :stream)" do
  it "defaults to :table for backward compatibility" do
    pdf = PDF::Document.new
    pdf.xref_format.should eq(:table)
  end

  it "emits a /Type /XRef stream when xref_format = :stream" do
    pdf = PDF::Document.new
    pdf.xref_format = :stream
    pdf.page { |_| }

    bytes = pdf.to_slice
    out = bytes.map(&.chr).join

    # Stream-based xref : no classic "xref\n0 N" table.
    out.should_not contain("xref\n0 ")
    out.should contain("/Type /XRef")
    out.should contain("/W ")
    out.should contain("startxref")
    out.should contain("%%EOF")
  end

  it "produces a PDF whose objects can be re-read via PDF::Reader" do
    pdf = PDF::Document.new
    pdf.xref_format = :stream
    pdf.title = "XRef stream test"
    pdf.page do |p|
      p.font "Helvetica", size: 12
      p.text "Hello via xref stream", at: {72, 720}
    end

    bytes = pdf.to_slice
    reader = PDF::Reader.new(bytes)
    reader.page_count.should eq(1)
  end

  it "embeds the trailer entries inside the stream dict" do
    pdf = PDF::Document.new
    pdf.xref_format = :stream
    pdf.page { |_| }
    pdf.attach_file(bytes: "x".to_slice, name: "x.txt")

    out = pdf.to_slice.map(&.chr).join
    out.should contain("/Root ")
    out.should contain("/Size ")
    # No separate `trailer <<>>` block in stream mode.
    out.should_not contain("trailer\n<<")
  end
end
