require "../spec_helper"

private def fogra_separation(name = "Pantone 185 C")
  PDF::ColorSpaces::Separation.new(
    name: name,
    alternate: PDF::ColorSpaces::ICCBased.fogra39,
    c1: [0.0, 1.0, 0.7, 0.0],
  )
end

private def fogra_device_n
  PDF::ColorSpaces::DeviceN.new(
    names: ["Pantone 877 C", "Pantone 185 C"],
    alternate: PDF::ColorSpaces::ICCBased.fogra39,
    c1_per_component: [
      [0.0, 0.0, 0.0, 0.2],
      [0.0, 1.0, 0.7, 0.0],
    ],
  )
end

describe "Page colour-space resources" do
  describe "#color_space" do
    it "registers a Separation and returns its resource name" do
      pdf = PDF::Document.new
      page = pdf.page(:a4) { |_| }
      name = page.color_space(fogra_separation)
      name.should eq("CS1")

      cs = page.build_resources_public["ColorSpace"].as(PDF::Objects::Dictionary)
      cs.has_key?("CS1").should be_true
      cs["CS1"].should be_a(PDF::Objects::Reference)
    end

    it "deduplicates the same space instance" do
      pdf = PDF::Document.new
      page = pdf.page(:a4) { |_| }
      spot = fogra_separation
      page.color_space(spot).should eq("CS1")
      page.color_space(spot).should eq("CS1") # same instance → same key
      page.build_resources_public["ColorSpace"].as(PDF::Objects::Dictionary).size.should eq(1)
    end

    it "assigns distinct keys to distinct spaces" do
      pdf = PDF::Document.new
      page = pdf.page(:a4) { |_| }
      page.color_space(fogra_separation("A")).should eq("CS1")
      page.color_space(fogra_separation("B")).should eq("CS2")
      page.build_resources_public["ColorSpace"].as(PDF::Objects::Dictionary).size.should eq(2)
    end

    it "omits /ColorSpace when no colour space is registered" do
      pdf = PDF::Document.new
      page = pdf.page(:a4) { |_| }
      page.build_resources_public["ColorSpace"]?.should be_nil
    end
  end

  describe "#fill_color / #stroke_color with a special space" do
    it "selects the space and sets the fill tint (Separation → scn)" do
      pdf = PDF::Document.new
      page = pdf.page(:a4) do |p|
        p.fill_color(fogra_separation, 1.0)
        p.rectangle(100, 600, 200, 100)
        p.fill
      end
      content = page.content_string
      content.should contain("/CS1 cs")
      content.should contain("1 scn")
    end

    it "sets one tint per colorant for a DeviceN (→ scn)" do
      pdf = PDF::Document.new
      page = pdf.page(:a4) do |p|
        p.fill_color(fogra_device_n, 1.0, 0.0)
      end
      content = page.content_string
      content.should contain("/CS1 cs")
      content.should contain("1 0 scn")
    end

    it "emits the stroke operators (CS / SCN)" do
      pdf = PDF::Document.new
      page = pdf.page(:a4) do |p|
        p.stroke_color(fogra_separation, 0.5)
      end
      content = page.content_string
      content.should contain("/CS1 CS")
      content.should contain("0.5 SCN")
    end

    it "rejects a tint count that does not match the space" do
      pdf = PDF::Document.new
      expect_raises(ArgumentError, /expects 1 tint/) do
        pdf.page(:a4) do |p|
          p.fill_color(fogra_separation, 1.0, 0.5) # Separation wants 1
        end
      end
    end

    it "rejects a wrong tint count for a DeviceN" do
      pdf = PDF::Document.new
      expect_raises(ArgumentError, /expects 2 tint/) do
        pdf.page(:a4) do |p|
          p.fill_color(fogra_device_n, 1.0) # DeviceN wants 2
        end
      end
    end
  end

  describe "document-level ICC deduplication" do
    it "embeds a shared ICC profile only once" do
      pdf = PDF::Document.new
      icc = PDF::ColorSpaces::ICCBased.fogra39
      ref1 = pdf.icc_profile_ref(icc)
      ref2 = pdf.icc_profile_ref(icc)
      ref1.should eq(ref2)
    end
  end

  describe "end-to-end output" do
    it "writes /ColorSpace, /DeviceN and /Colorants into the PDF" do
      pdf = PDF::Document.new
      pdf.page(:a4) do |p|
        p.fill_color(fogra_device_n, 1.0, 0.0)
        p.rectangle(100, 600, 200, 100)
        p.fill
      end
      bytes = String.new(pdf.to_slice)
      bytes.should contain("/ColorSpace")
      bytes.should contain("/DeviceN")
      bytes.should contain("/Colorants")
      bytes.should contain("/Separation")
    end
  end
end
