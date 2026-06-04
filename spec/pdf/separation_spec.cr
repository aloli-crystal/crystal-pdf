require "../spec_helper"

describe PDF::ColorSpaces::Separation do
  it "rejects c1 of wrong arity" do
    expect_raises(ArgumentError, /must have 3 components/) do
      PDF::ColorSpaces::Separation.new(
        name: "Bad",
        alternate: PDF::ColorSpaces::ICCBased.srgb_v4,
        c1: [0.0, 1.0], # only 2 vals for an RGB fallback
      )
    end
  end

  it "builds an array `[/Separation /name [/ICCBased ref] <tintfn>]`" do
    sep = PDF::ColorSpaces::Separation.new(
      name: "Pantone 185 C",
      alternate: PDF::ColorSpaces::ICCBased.fogra39,
      c1: [0.0, 1.0, 0.7, 0.0],
    )
    fake_ref = PDF::Objects::Reference.new(42)
    arr = sep.to_array(fake_ref)
    arr[0].to_pdf.should eq("/Separation")
    arr[1].to_pdf.should eq("/Pantone#20185#20C") # PDF name encoding
    arr[2].to_pdf.should eq("[/ICCBased 42 0 R]")
    arr[3].as(PDF::Objects::Dictionary)["FunctionType"].to_pdf.should eq("2")
  end

  it "default c0 is `[0 0 0 0]` for a CMYK alternate" do
    sep = PDF::ColorSpaces::Separation.new(
      name: "Spot",
      alternate: PDF::ColorSpaces::ICCBased.fogra39,
      c1: [0.0, 1.0, 0.7, 0.0],
    )
    sep.c0.should eq([0.0, 0.0, 0.0, 0.0])
  end
end

describe PDF::ColorSpaces::DeviceN do
  it "rejects an empty names list" do
    expect_raises(ArgumentError, /at least one component/) do
      PDF::ColorSpaces::DeviceN.new(
        names: [] of String,
        alternate: PDF::ColorSpaces::ICCBased.fogra39,
        c1_per_component: [] of Array(Float64),
      )
    end
  end

  it "rejects mismatched c1 arity per component" do
    expect_raises(ArgumentError, /must have 4 values/) do
      PDF::ColorSpaces::DeviceN.new(
        names: ["A", "B"],
        alternate: PDF::ColorSpaces::ICCBased.fogra39,
        c1_per_component: [[0.0, 1.0, 0.7, 0.0], [0.5, 0.5]], # 2nd is wrong
      )
    end
  end

  it "builds an array `[/DeviceN [/n1 /n2] [/ICCBased ref] <tintfn>]`" do
    multi = PDF::ColorSpaces::DeviceN.new(
      names: ["Pantone 185 C", "Pantone 286 C"],
      alternate: PDF::ColorSpaces::ICCBased.fogra39,
      c1_per_component: [
        [0.0, 1.0, 0.7, 0.0],
        [1.0, 0.6, 0.0, 0.0],
      ],
    )
    fake_ref = PDF::Objects::Reference.new(7)
    arr = multi.to_array(fake_ref)
    arr[0].to_pdf.should eq("/DeviceN")
    arr[1].as(PDF::Objects::Array).size.should eq(2)
    arr[2].to_pdf.should eq("[/ICCBased 7 0 R]")
  end

  it "appends a /Colorants attributes dict describing each spot colorant (ISO 19005-2 § 6.2.4.4)" do
    multi = PDF::ColorSpaces::DeviceN.new(
      names: ["Pantone 185 C", "Pantone 286 C"],
      alternate: PDF::ColorSpaces::ICCBased.fogra39,
      c1_per_component: [
        [0.0, 1.0, 0.7, 0.0],
        [1.0, 0.6, 0.0, 0.0],
      ],
    )
    fake_ref = PDF::Objects::Reference.new(7)
    arr = multi.to_array(fake_ref)

    # The 5th element is the attributes dictionary.
    arr.size.should eq(5)
    attributes = arr[4].as(PDF::Objects::Dictionary)
    colorants = attributes["Colorants"].as(PDF::Objects::Dictionary)

    # One entry per spot colorant, keyed by the colorant name.
    colorants.size.should eq(2)
    colorants.has_key?("Pantone 185 C").should be_true
    colorants.has_key?("Pantone 286 C").should be_true

    # Each entry is a Separation array reusing this DeviceN's
    # alternate and per-component c1 vector.
    sep185 = colorants["Pantone 185 C"].as(PDF::Objects::Array)
    sep185[0].to_pdf.should eq("/Separation")
    sep185[1].to_pdf.should eq("/Pantone#20185#20C")
    sep185[2].to_pdf.should eq("[/ICCBased 7 0 R]")
    tint185 = sep185[3].as(PDF::Objects::Dictionary)
    tint185["FunctionType"].to_pdf.should eq("2")
    tint185["C1"].to_pdf.should eq("[0 1 0.7 0]")
  end

  it "encodes /Colorants keys identically to the names array" do
    multi = PDF::ColorSpaces::DeviceN.new(
      names: ["Pantone 185 C"],
      alternate: PDF::ColorSpaces::ICCBased.fogra39,
      c1_per_component: [[0.0, 1.0, 0.7, 0.0]],
    )
    arr = multi.to_array(PDF::Objects::Reference.new(7))
    colorants = arr[4].as(PDF::Objects::Dictionary)["Colorants"].as(PDF::Objects::Dictionary)
    # The /Colorants key must match the encoded colorant name exactly.
    colorants.to_pdf.should contain("/Pantone#20185#20C")
  end

  it "omits the attributes dict when every colorant is a process ink" do
    process = PDF::ColorSpaces::DeviceN.new(
      names: ["Cyan", "Magenta", "Yellow", "Black"],
      alternate: PDF::ColorSpaces::ICCBased.fogra39,
      c1_per_component: [
        [1.0, 0.0, 0.0, 0.0],
        [0.0, 1.0, 0.0, 0.0],
        [0.0, 0.0, 1.0, 0.0],
        [0.0, 0.0, 0.0, 1.0],
      ],
    )
    arr = process.to_array(PDF::Objects::Reference.new(7))
    arr.size.should eq(4) # no /Colorants attributes dictionary
  end

  it "treats /None and /All as non-spot colorants" do
    reserved = PDF::ColorSpaces::DeviceN.new(
      names: ["None", "All"],
      alternate: PDF::ColorSpaces::ICCBased.fogra39,
      c1_per_component: [
        [0.0, 0.0, 0.0, 0.0],
        [1.0, 1.0, 1.0, 1.0],
      ],
    )
    arr = reserved.to_array(PDF::Objects::Reference.new(7))
    arr.size.should eq(4)
  end

  it "lists only spot colorants when mixed with process inks" do
    mixed = PDF::ColorSpaces::DeviceN.new(
      names: ["Cyan", "Pantone 877 C"],
      alternate: PDF::ColorSpaces::ICCBased.fogra39,
      c1_per_component: [
        [1.0, 0.0, 0.0, 0.0],
        [0.0, 0.0, 0.0, 0.2],
      ],
    )
    arr = mixed.to_array(PDF::Objects::Reference.new(7))
    arr.size.should eq(5)
    colorants = arr[4].as(PDF::Objects::Dictionary)["Colorants"].as(PDF::Objects::Dictionary)
    colorants.size.should eq(1)
    colorants.has_key?("Pantone 877 C").should be_true
    colorants.has_key?("Cyan").should be_false
  end
end
