require "../spec_helper"
require "file_utils"

# Construit un document avec une image JPEG (DCTDecode) et une image
# PNG (FlateDecode), puis le relit.
private def build_with_images : PDF::Reader
  pdf = PDF::Document.new
  page = pdf.page { |_| }
  jpeg = PDF::Images::JPEG.load("spec/fixtures/images/test_rgb.jpg")
  png = PDF::Images::PNG.load("spec/fixtures/images/test_rgb.png")
  page.image(jpeg, at: {50, 600}, width: 100)
  page.image(png, at: {200, 600}, width: 100)
  PDF::Reader.open(IO::Memory.new(pdf.to_slice))
end

describe PDF::ImageInfo do
  describe ".list" do
    it "énumère les images XObject des pages" do
      images = PDF::ImageInfo.list(build_with_images)
      images.size.should eq(2)
      images.all? { |im| im.page == 1 }.should be_true
    end

    it "classe le filtre et l'espace colorimétrique" do
      images = PDF::ImageInfo.list(build_with_images)
      jpeg = images.find! { |im| im.filter == "jpeg" }
      jpeg.color_space.should eq("rgb")
      jpeg.components.should eq(3)
      jpeg.bits_per_component.should eq(8)
      jpeg.width.should eq(100)
      jpeg.height.should eq(100)
      jpeg.decoded?.should be_false # DCTDecode reste encodé

      flate = images.find! { |im| im.filter == "flate" }
      flate.color_space.should eq("rgb")
      flate.decoded?.should be_true # FlateDecode décodé en échantillons
    end

    it "renvoie une liste vide pour un document sans image" do
      PDF::ImageInfo.list(PDF::Reader.open("spec/fixtures/single_page.pdf")).should be_empty
    end

    it "déduplique par numéro d'objet" do
      images = PDF::ImageInfo.list(build_with_images)
      ids = images.map(&.object_number)
      ids.uniq.size.should eq(ids.size)
    end
  end

  describe "#extension / #write_to" do
    it "donne .jpg pour une image DCTDecode et restitue le JPEG" do
      jpeg = PDF::ImageInfo.list(build_with_images).find! { |im| im.filter == "jpeg" }
      jpeg.extension.should eq("jpg")
      # Signature JPEG : SOI = FF D8.
      data = jpeg.data
      data[0].should eq(0xFF)
      data[1].should eq(0xD8)
    end

    it "donne .ppm pour une image RGB FlateDecode et écrit un en-tête Netpbm" do
      flate = PDF::ImageInfo.list(build_with_images).find! { |im| im.filter == "flate" }
      flate.extension.should eq("ppm")
      dir = File.tempname
      Dir.mkdir_p(dir)
      begin
        dest = flate.write_to(dir, "img")
        dest.should end_with(".ppm")
        File.read(dest).should start_with("P6\n100 100\n255\n")
      ensure
        FileUtils.rm_rf(dir)
      end
    end
  end
end
