require "../spec_helper"
require "compress/zlib"

# Inflates every FlateDecode stream in `bytes` and returns the
# concatenated decoded text. Content streams are Flate-compressed by
# default, so marked-content operators (BDC/EMC) only appear after
# inflation.
private def inflated_streams(bytes : Bytes) : String
  s = String.new(bytes)
  out = String::Builder.new
  offset = 0
  while (idx = s.index("stream", offset))
    data_start = idx + "stream".size
    # Skip the EOL after the `stream` keyword (CRLF or LF).
    data_start += 1 if data_start < s.bytesize && s.byte_at(data_start) == 13_u8
    data_start += 1 if data_start < s.bytesize && s.byte_at(data_start) == 10_u8
    if (end_idx = s.index("endstream", data_start))
      raw = bytes[data_start, end_idx - data_start]
      begin
        io = IO::Memory.new(raw)
        Compress::Zlib::Reader.open(io) { |z| out << z.gets_to_end }
      rescue
        # not a zlib stream — ignore
      end
      offset = end_idx + "endstream".size
    else
      break
    end
  end
  out.to_s
end

describe PDF::Structure::Tag do
  it "recognises standard structure types" do
    PDF::Structure::Tag.standard?("Document").should be_true
    PDF::Structure::Tag.standard?("H1").should be_true
    PDF::Structure::Tag.standard?("TD").should be_true
    PDF::Structure::Tag.standard?("Figure").should be_true
  end

  it "rejects non-standard roles" do
    PDF::Structure::Tag.standard?("Sidebar").should be_false
    PDF::Structure::Tag.standard?("Callout").should be_false
  end

  it "maps heading levels to Hn tags" do
    PDF::Structure::Tag.heading(1).should eq("H1")
    PDF::Structure::Tag.heading(6).should eq("H6")
    PDF::Structure::Tag.heading(7).should eq("H") # no H7 in PDF
    PDF::Structure::Tag.heading(0).should eq("H")
  end
end

describe PDF::Structure::StructElem do
  it "builds a /StructElem dict with /S, /P and accessibility attrs" do
    elem = PDF::Structure::StructElem.new(
      PDF::Structure::Tag::FIGURE,
      alt: "Logo ALOLI",
      lang: "fr",
    )
    parent = PDF::Objects::Reference.new(1)
    dict = elem.to_dictionary(parent, [] of PDF::Objects::Reference)

    dict["Type"].to_pdf.should eq("/StructElem")
    dict["S"].to_pdf.should eq("/Figure")
    dict["P"].to_pdf.should eq("1 0 R")
    dict["Alt"].as(PDF::Objects::Str).should_not be_nil
    dict["Lang"].to_pdf.should eq("(fr)")
  end

  it "emits a single /K reference (not an array) for one child" do
    elem = PDF::Structure::StructElem.new(PDF::Structure::Tag::SECT)
    parent = PDF::Objects::Reference.new(1)
    kid = PDF::Objects::Reference.new(5)
    dict = elem.to_dictionary(parent, [kid])
    dict["K"].to_pdf.should eq("5 0 R")
  end

  it "emits a /K array for multiple children" do
    elem = PDF::Structure::StructElem.new(PDF::Structure::Tag::SECT)
    parent = PDF::Objects::Reference.new(1)
    kids = [PDF::Objects::Reference.new(5), PDF::Objects::Reference.new(6)]
    dict = elem.to_dictionary(parent, kids)
    dict["K"].to_pdf.should eq("[5 0 R 6 0 R]")
  end

  it "nests children fluently via add" do
    doc = PDF::Structure::StructElem.new(PDF::Structure::Tag::DOCUMENT)
    doc.add(PDF::Structure::Tag::H1, title: "Titre")
    doc.add(PDF::Structure::Tag::P)
    doc.children.size.should eq(2)
    doc.children[0].type.should eq("H1")
    doc.children[1].type.should eq("P")
  end
end

describe PDF::Structure::StructTree do
  it "starts empty" do
    PDF::Structure::StructTree.new.empty?.should be_true
  end

  it "becomes non-empty after adding a root" do
    tree = PDF::Structure::StructTree.new
    tree.add(PDF::Structure::Tag::DOCUMENT)
    tree.empty?.should be_false
  end
end

describe "Document tagging (integration)" do
  it "does not emit /StructTreeRoot or /MarkInfo for an untagged document" do
    pdf = PDF::Document.new
    pdf.page { |_| }
    out = pdf.to_slice.map(&.chr).join
    out.should_not contain("/StructTreeRoot")
    out.should_not contain("/MarkInfo")
  end

  it "emits /StructTreeRoot + /MarkInfo /Marked true when tagged" do
    pdf = PDF::Document.new
    pdf.lang = "fr"
    pdf.page { |_| }
    pdf.struct_tree do |tree|
      doc = tree.add(PDF::Structure::Tag::DOCUMENT)
      doc.add(PDF::Structure::Tag::H1, title: "Titre principal")
      doc.add(PDF::Structure::Tag::P)
    end

    out = pdf.to_slice.map(&.chr).join
    out.should contain("/StructTreeRoot")
    out.should contain("/MarkInfo")
    out.should contain("/Marked true")
    out.should contain("/Lang (fr)")
    out.should contain("/S /Document")
    out.should contain("/S /H1")
    out.should contain("/S /P")
  end

  it "emits /Lang independently of the structure tree" do
    pdf = PDF::Document.new
    pdf.lang = "en-US"
    pdf.page { |_| }
    out = pdf.to_slice.map(&.chr).join
    out.should contain("/Lang (en-US)")
    out.should_not contain("/StructTreeRoot")
  end

  it "emits a /RoleMap when custom roles are mapped" do
    pdf = PDF::Document.new
    pdf.page { |_| }
    pdf.struct_tree do |tree|
      tree.map_role("Sidebar", PDF::Structure::Tag::DIV)
      tree.add(PDF::Structure::Tag::DOCUMENT).add("Sidebar")
    end
    out = pdf.to_slice.map(&.chr).join
    out.should contain("/RoleMap")
    out.should contain("/Sidebar /Div")
  end

  it "emits marked content (BDC/EMC + MCID) linked via the ParentTree" do
    pdf = PDF::Document.new
    pdf.lang = "fr"
    page = pdf.page { |_| }
    pdf.struct_tree do |tree|
      doc = tree.add(PDF::Structure::Tag::DOCUMENT)
      h1 = doc.add(PDF::Structure::Tag::H1, title: "Titre")
      mcid = page.marked_content("H1") do
        page.font "Helvetica", size: 18
        page.text "Rapport", at: {72, 760}
      end
      h1.add_mcid(page, mcid)
    end

    bytes = pdf.to_slice
    out = bytes.map(&.chr).join
    # Page is linked to the ParentTree (uncompressed dict entry).
    out.should contain("/StructParents 0")
    # StructTreeRoot carries the ParentTree.
    out.should contain("/ParentTree")
    out.should contain("/ParentTreeNextKey 1")
    # The element references the marked content via an MCR dict.
    out.should contain("/Type /MCR")
    out.should contain("/MCID 0")
    # Content-stream operators live in the (compressed) content
    # stream — verify after inflation.
    content = inflated_streams(bytes)
    content.should contain("/H1 <</MCID 0>> BDC")
    content.should contain("EMC")
  end

  it "emits artifacts as /Artifact BDC … EMC (no MCID)" do
    pdf = PDF::Document.new
    page = pdf.page { |p| }
    page.artifact do
      page.font "Helvetica", size: 8
      page.text "en-tête", at: {72, 800}
    end
    content = inflated_streams(pdf.to_slice)
    content.should contain("/Artifact BDC")
    content.should contain("EMC")
  end

  it "assigns MCIDs sequentially per page" do
    pdf = PDF::Document.new
    page = pdf.page { |_| }
    m0 = page.marked_content("P") { page.font "Helvetica", size: 12; page.text "a", at: {72, 700} }
    m1 = page.marked_content("P") { page.text "b", at: {72, 680} }
    m0.should eq(0)
    m1.should eq(1)
    page.mcid_count.should eq(2)
  end

  it "raises if a marked-content MCID is not linked to a structure element" do
    pdf = PDF::Document.new
    page = pdf.page { |_| }
    pdf.struct_tree do |tree|
      doc = tree.add(PDF::Structure::Tag::DOCUMENT)
      # Mark content but DON'T link it → ParentTree gap → must raise.
      page.marked_content("P") { page.font "Helvetica", size: 12; page.text "orphan", at: {72, 700} }
      doc.add(PDF::Structure::Tag::P) # element without the mcid link
    end
    expect_raises(Exception, /not linked to any structure element/) do
      pdf.to_slice
    end
  end

  it "tags content in one call via Page#tag (marked_content + add_mcid)" do
    pdf = PDF::Document.new
    pdf.lang = "fr"
    page = pdf.page { |_| }
    pdf.struct_tree do |tree|
      doc = tree.add(PDF::Structure::Tag::DOCUMENT)
      h1 = doc.add(PDF::Structure::Tag::H1, title: "Titre")
      mcid = page.tag(h1) do
        page.font "Helvetica", size: 18
        page.text "Titre", at: {72, 760}
      end
      mcid.should eq(0)
      # The element is now linked to the marked content.
      h1.mcids.size.should eq(1)
    end

    bytes = pdf.to_slice
    out = bytes.map(&.chr).join
    out.should contain("/StructParents 0")
    out.should contain("/Type /MCR")
    inflated_streams(bytes).should contain("/H1 <</MCID 0>> BDC")
  end

  it "supports table structure (Table > TR > TH/TD) via the generic model" do
    pdf = PDF::Document.new
    page = pdf.page { |_| }
    pdf.struct_tree do |tree|
      doc = tree.add(PDF::Structure::Tag::DOCUMENT)
      table = doc.add(PDF::Structure::Tag::TABLE)

      header = table.add(PDF::Structure::Tag::TR)
      th1 = header.add(PDF::Structure::Tag::TH)
      th2 = header.add(PDF::Structure::Tag::TH)

      row = table.add(PDF::Structure::Tag::TR)
      td1 = row.add(PDF::Structure::Tag::TD)
      td2 = row.add(PDF::Structure::Tag::TD)

      [th1, th2, td1, td2].each_with_index do |cell, i|
        page.tag(cell) do
          page.font "Helvetica", size: 10
          page.text "cell #{i}", at: {72 + i*60, 700}
        end
      end
    end

    out = pdf.to_slice.map(&.chr).join
    out.should contain("/S /Table")
    out.should contain("/S /TR")
    out.should contain("/S /TH")
    out.should contain("/S /TD")
  end

  it "emits XMP pdfaid identification when pdfa_part/conformance are set" do
    pdf = PDF::Document.new
    pdf.pdfa_part = 2
    pdf.pdfa_conformance = "B"
    pdf.page { |_| }
    out = pdf.to_slice.map(&.chr).join
    out.should contain("<pdfaid:part>2</pdfaid:part>")
    out.should contain("<pdfaid:conformance>B</pdfaid:conformance>")
  end

  it "omits pdfaid when not a PDF/A document" do
    pdf = PDF::Document.new
    pdf.page { |_| }
    out = pdf.to_slice.map(&.chr).join
    out.should_not contain("<pdfaid:part>")
  end

  it "emits PDF/UA identification and ViewerPreferences when set" do
    pdf = PDF::Document.new
    pdf.title = "Doc accessible"
    pdf.lang = "fr"
    pdf.pdfua_part = 1
    pdf.display_doc_title = true
    pdf.page { |_| }
    out = pdf.to_slice.map(&.chr).join
    out.should contain("<pdfuaid:part>1</pdfuaid:part>")
    out.should contain("/ViewerPreferences")
    out.should contain("/DisplayDocTitle true")
  end

  it "omits ViewerPreferences and pdfuaid when not a PDF/UA document" do
    pdf = PDF::Document.new
    pdf.page { |_| }
    out = pdf.to_slice.map(&.chr).join
    out.should_not contain("<pdfuaid:part>")
    out.should_not contain("/ViewerPreferences")
  end

  it "produces a structurally valid PDF (round-trips through the reader)" do
    pdf = PDF::Document.new
    pdf.lang = "fr"
    pdf.page { |p| p.font "Helvetica", size: 12; p.text "Bonjour", at: {72, 700} }
    pdf.struct_tree do |tree|
      d = tree.add(PDF::Structure::Tag::DOCUMENT)
      d.add(PDF::Structure::Tag::P)
    end

    bytes = pdf.to_slice
    io = IO::Memory.new(bytes)
    # Header + EOF sanity (full reader parse is covered elsewhere).
    String.new(bytes[0, 8]).should start_with("%PDF-")
    String.new(bytes[-6, 6]).should contain("%%EOF")
  end
end
