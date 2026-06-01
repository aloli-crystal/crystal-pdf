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
end
