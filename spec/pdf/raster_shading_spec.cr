require "../spec_helper"

private def num_array(*vals) : PDF::Objects::Array
  a = PDF::Objects::Array.new
  vals.each { |v| a << PDF::Objects::Number.new(v.to_f) }
  a
end

# Construit un dictionnaire de ressources avec un dégradé axial
# rouge → bleu (Coords [0 0 100 0]).
private def axial_resources : PDF::Objects::Dictionary
  func = PDF::Objects::Dictionary.new
  func["FunctionType"] = PDF::Objects::Number.new(2)
  func["Domain"] = num_array(0, 1)
  func["C0"] = num_array(1, 0, 0)
  func["C1"] = num_array(0, 0, 1)
  func["N"] = PDF::Objects::Number.new(1)

  sh = PDF::Objects::Dictionary.new
  sh["ShadingType"] = PDF::Objects::Number.new(2)
  sh["ColorSpace"] = PDF::Objects::Name.new("DeviceRGB")
  sh["Coords"] = num_array(0, 0, 100, 0)
  sh["Function"] = func
  ext = PDF::Objects::Array.new
  ext << PDF::Objects::Boolean.new(true)
  ext << PDF::Objects::Boolean.new(true)
  sh["Extend"] = ext

  shd = PDF::Objects::Dictionary.new
  shd["Sh1"] = sh
  res = PDF::Objects::Dictionary.new
  res["Shading"] = shd
  res
end

describe PDF::Raster::Shading do
  it "peint un dégradé axial (rouge → bleu) via l'opérateur sh" do
    reader = PDF::Reader.open("spec/fixtures/single_page.pdf")
    canvas = PDF::Raster::Canvas.new(100, 100)
    base = PDF::Raster::Matrix.new(1.0, 0.0, 0.0, -1.0, 0.0, 100.0)
    interp = PDF::Raster::Interpreter.new(canvas, base, reader, axial_resources)
    interp.run("0 0 100 100 re W n /Sh1 sh".to_slice)

    left = canvas.pixels[5, 50]
    mid = canvas.pixels[50, 50]
    right = canvas.pixels[95, 50]

    # Gauche rouge, droite bleu, milieu violet (interpolation linéaire).
    (left.r >> 8).to_i.should be > 200
    (left.b >> 8).to_i.should be < 60
    (right.b >> 8).to_i.should be > 200
    (right.r >> 8).to_i.should be < 60
    (mid.r >> 8).to_i.should be_close(127, 40)
    (mid.b >> 8).to_i.should be_close(127, 40)
  end
end

describe "PDF::Raster — remplissage par motif de dégradé (scn /Pattern)" do
  it "remplit un chemin avec un dégradé détouré à sa forme" do
    func = PDF::Objects::Dictionary.new
    func["FunctionType"] = PDF::Objects::Number.new(2)
    func["Domain"] = num_array(0, 1)
    func["C0"] = num_array(1, 0, 0)
    func["C1"] = num_array(0, 0, 1)
    func["N"] = PDF::Objects::Number.new(1)
    sh = PDF::Objects::Dictionary.new
    sh["ShadingType"] = PDF::Objects::Number.new(2)
    sh["ColorSpace"] = PDF::Objects::Name.new("DeviceRGB")
    sh["Coords"] = num_array(0, 0, 100, 0)
    sh["Function"] = func
    pat = PDF::Objects::Dictionary.new
    pat["PatternType"] = PDF::Objects::Number.new(2)
    pat["Shading"] = sh
    pd = PDF::Objects::Dictionary.new
    pd["P1"] = pat
    res = PDF::Objects::Dictionary.new
    res["Pattern"] = pd

    reader = PDF::Reader.open("spec/fixtures/single_page.pdf")
    canvas = PDF::Raster::Canvas.new(100, 100)
    base = PDF::Raster::Matrix.new(1.0, 0.0, 0.0, -1.0, 0.0, 100.0)
    interp = PDF::Raster::Interpreter.new(canvas, base, reader, res)
    # Triangle bas-droit rempli par le dégradé.
    interp.run("/Pattern cs /P1 scn 0 0 m 100 0 l 100 100 l h f".to_slice)

    inside = canvas.pixels[80, 50] # dans le triangle, x élevé → bleu
    (inside.b >> 8).to_i.should be > 150
    out = canvas.pixels[10, 10] # hors triangle → blanc (détourage)
    {out.r >> 8, out.g >> 8, out.b >> 8}.should eq({255, 255, 255})
  end
end

describe PDF::Raster::PdfFunction do
  it "interpole une fonction exponentielle (type 2)" do
    func = PDF::Objects::Dictionary.new
    func["FunctionType"] = PDF::Objects::Number.new(2)
    func["Domain"] = num_array(0, 1)
    func["C0"] = num_array(0, 0, 0)
    func["C1"] = num_array(1, 0.5, 0)
    func["N"] = PDF::Objects::Number.new(1)
    reader = PDF::Reader.open("spec/fixtures/single_page.pdf")
    fn = PDF::Raster::PdfFunction.parse(reader, func).first

    fn.eval(0.0).should eq([0.0, 0.0, 0.0])
    mid = fn.eval(0.5)
    mid[0].should be_close(0.5, 0.001)
    mid[1].should be_close(0.25, 0.001)
  end
end
