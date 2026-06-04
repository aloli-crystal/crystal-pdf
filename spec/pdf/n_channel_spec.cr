require "../spec_helper"

private def cmyk_plus_spot
  PDF::ColorSpaces::NChannel.new(
    names: ["Cyan", "Magenta", "Yellow", "Black", "Pantone 877 C"],
    alternate: PDF::ColorSpaces::ICCBased.fogra39,
    c1_per_component: [
      [1.0, 0.0, 0.0, 0.0],
      [0.0, 1.0, 0.0, 0.0],
      [0.0, 0.0, 1.0, 0.0],
      [0.0, 0.0, 0.0, 1.0],
      [0.0, 0.0, 0.0, 0.2],
    ],
    process_components: ["Cyan", "Magenta", "Yellow", "Black"],
  )
end

describe PDF::ColorSpaces::NChannel do
  it "is a DeviceN with /Subtype /NChannel in its attributes" do
    arr = cmyk_plus_spot.to_array(PDF::Objects::Reference.new(7))
    arr[0].to_pdf.should eq("/DeviceN") # NChannel uses the DeviceN family token
    arr.size.should eq(5)               # attributes dictionary always present
    attributes = arr[4].as(PDF::Objects::Dictionary)
    attributes["Subtype"].to_pdf.should eq("/NChannel")
  end

  it "inherits the /Colorants requirement for spot colorants (§ 6.2.4.4)" do
    arr = cmyk_plus_spot.to_array(PDF::Objects::Reference.new(7))
    colorants = arr[4].as(PDF::Objects::Dictionary)["Colorants"].as(PDF::Objects::Dictionary)
    colorants.has_key?("Pantone 877 C").should be_true # the only spot ink
    colorants.has_key?("Cyan").should be_false         # process inks excluded
    colorants.size.should eq(1)
    sep = colorants["Pantone 877 C"].as(PDF::Objects::Array)
    sep[0].to_pdf.should eq("/Separation")
  end

  it "emits a /Process dictionary describing the process colorants" do
    arr = cmyk_plus_spot.to_array(PDF::Objects::Reference.new(7))
    process = arr[4].as(PDF::Objects::Dictionary)["Process"].as(PDF::Objects::Dictionary)
    process["ColorSpace"].to_pdf.should eq("[/ICCBased 7 0 R]")
    components = process["Components"].as(PDF::Objects::Array)
    components.size.should eq(4)
    components.map(&.to_pdf).should eq(["/Cyan", "/Magenta", "/Yellow", "/Black"])
  end

  it "marks /Subtype /NChannel even with no spot colorant and no process" do
    nchan = PDF::ColorSpaces::NChannel.new(
      names: ["Cyan", "Magenta", "Yellow", "Black"],
      alternate: PDF::ColorSpaces::ICCBased.fogra39,
      c1_per_component: [
        [1.0, 0.0, 0.0, 0.0],
        [0.0, 1.0, 0.0, 0.0],
        [0.0, 0.0, 1.0, 0.0],
        [0.0, 0.0, 0.0, 1.0],
      ],
    )
    attributes = nchan.to_array(PDF::Objects::Reference.new(7))[4].as(PDF::Objects::Dictionary)
    attributes["Subtype"].to_pdf.should eq("/NChannel")
    attributes.has_key?("Colorants").should be_false # no spot ink
    attributes.has_key?("Process").should be_false   # not requested
  end

  it "rejects /Process components of the wrong arity" do
    expect_raises(ArgumentError, /needs 4 component/) do
      PDF::ColorSpaces::NChannel.new(
        names: ["Cyan", "Magenta", "Yellow", "Black"],
        alternate: PDF::ColorSpaces::ICCBased.fogra39,
        c1_per_component: [
          [1.0, 0.0, 0.0, 0.0],
          [0.0, 1.0, 0.0, 0.0],
          [0.0, 0.0, 1.0, 0.0],
          [0.0, 0.0, 0.0, 1.0],
        ],
        process_components: ["Cyan", "Magenta"], # only 2 for a 4-channel alternate
      )
    end
  end

  it "rejects /Process components not present in the colorant names" do
    expect_raises(ArgumentError, /not among the colorant names/) do
      PDF::ColorSpaces::NChannel.new(
        names: ["Cyan", "Magenta", "Yellow", "Black"],
        alternate: PDF::ColorSpaces::ICCBased.fogra39,
        c1_per_component: [
          [1.0, 0.0, 0.0, 0.0],
          [0.0, 1.0, 0.0, 0.0],
          [0.0, 0.0, 1.0, 0.0],
          [0.0, 0.0, 0.0, 1.0],
        ],
        process_components: ["Cyan", "Magenta", "Yellow", "Red"], # Red ∉ names
      )
    end
  end

  describe "Page integration (NChannel is-a DeviceN)" do
    it "registers and fills through the existing colour-space API" do
      pdf = PDF::Document.new
      page = pdf.page(:a4) do |p|
        p.fill_color(cmyk_plus_spot, 0.0, 0.0, 0.0, 0.0, 1.0) # 5 tints (5 colorants)
        p.rectangle(100, 600, 200, 100)
        p.fill
      end
      content = page.content_string
      content.should contain("/CS1 cs")
      content.should contain("0 0 0 0 1 scn")
      page.build_resources_public["ColorSpace"].as(PDF::Objects::Dictionary).has_key?("CS1").should be_true
    end

    it "validates the tint count against the colorant count" do
      pdf = PDF::Document.new
      expect_raises(ArgumentError, /expects 5 tint/) do
        pdf.page(:a4) do |p|
          p.fill_color(cmyk_plus_spot, 1.0) # NChannel wants 5
        end
      end
    end

    it "writes /NChannel into the PDF bytes" do
      pdf = PDF::Document.new
      pdf.page(:a4) do |p|
        p.fill_color(cmyk_plus_spot, 0.0, 0.0, 0.0, 0.0, 1.0)
        p.rectangle(100, 600, 200, 100)
        p.fill
      end
      bytes = String.new(pdf.to_slice)
      bytes.should contain("/NChannel")
      bytes.should contain("/Process")
      bytes.should contain("/Colorants")
    end
  end
end
