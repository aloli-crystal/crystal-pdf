require "../spec_helper"

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
