require "../spec_helper"

describe PDF::Raster::Matrix do
  it "applique l'identité sans changement" do
    m = PDF::Raster::Matrix.identity
    m.apply(3.0, 4.0).should eq({3.0, 4.0})
  end

  it "applique une mise à l'échelle" do
    m = PDF::Raster::Matrix.scale(2.0, 3.0)
    m.apply(5.0, 5.0).should eq({10.0, 15.0})
  end

  it "compose dans l'ordre « d'abord self, puis other »" do
    # translate(10,0) puis scale(2,2) → (x+10)*2
    combined = PDF::Raster::Matrix.translate(10.0, 0.0).then(PDF::Raster::Matrix.scale(2.0, 2.0))
    combined.apply(5.0, 0.0).should eq({30.0, 0.0})
  end

  it "calcule l'échelle moyenne" do
    PDF::Raster::Matrix.scale(4.0, 9.0).mean_scale.should eq(6.0)
  end
end

describe PDF::Raster::Interpreter do
  it "remplit un rectangle de la couleur Device RGB demandée" do
    # 80×80 px, CTM identité (1 pt = 1 px, origine haut-gauche).
    canvas = PDF::Raster::Canvas.new(80, 80)
    base = PDF::Raster::Matrix.identity
    interp = PDF::Raster::Interpreter.new(canvas, base)
    # rouge plein, rectangle (20,20)-(60,60)
    interp.run("1 0 0 rg 20 20 40 40 re f".to_slice)

    inside = canvas.pixels[40, 40]
    {inside.r >> 8, inside.g >> 8, inside.b >> 8}.should eq({255, 0, 0})

    outside = canvas.pixels[5, 5]
    {outside.r >> 8, outside.g >> 8, outside.b >> 8}.should eq({255, 255, 255})
  end

  it "respecte la pile d'état graphique (q/Q)" do
    canvas = PDF::Raster::Canvas.new(40, 40)
    interp = PDF::Raster::Interpreter.new(canvas, PDF::Raster::Matrix.identity)
    # Met le rouge dans un q/Q, puis remplit HORS du bloc : doit rester
    # la couleur par défaut (noir), pas le rouge.
    interp.run("q 1 0 0 rg Q 0 0 30 30 re f".to_slice)
    px = canvas.pixels[15, 15]
    {px.r >> 8, px.g >> 8, px.b >> 8}.should eq({0, 0, 0})
  end
end

describe "PDF::Raster — rendu de texte" do
  it "rend les glyphes d'une fonte TrueType embarquée" do
    pdf = PDF::Document.new
    ttf = PDF::Fonts::TrueTypeFont.load("spec/fixtures/fonts/DejaVuSans.ttf")
    pdf.page do |p|
      p.font(ttf, 40)
      p.text("HII", at: {100, 700})
    end
    reader = PDF::Reader.open(IO::Memory.new(pdf.to_slice))
    canvas = PDF::Raster.render_page(reader, 0, dpi: 72)

    # Compte les pixels noirs (texte) dans la bande où le texte est posé.
    # Texte à y≈700 pt ; en device (72 dpi, h=792) top ≈ 792-740..792-700.
    ink = 0
    (60..130).each do |y|
      (90..260).each do |x|
        px = canvas.pixels[x, y]
        ink += 1 if (px.r >> 8) < 128
      end
    end
    ink.should be > 50 # des glyphes ont bien été remplis

    # Une zone vide reste blanche.
    empty = canvas.pixels[400, 400]
    {empty.r >> 8, empty.g >> 8, empty.b >> 8}.should eq({255, 255, 255})
  end
end

describe PDF::Raster do
  it "rend une page générée en PNG avec les bonnes dimensions" do
    pdf = PDF::Document.new
    pdf.page do |p|
      p.fill_color("00FF00")
      p.rectangle(50, 50, 100, 100)
      p.fill
    end
    reader = PDF::Reader.open(IO::Memory.new(pdf.to_slice))
    canvas = PDF::Raster.render_page(reader, 0, dpi: 72)

    # 72 dpi → 1 px par point. Page Letter = 612×792.
    canvas.width.should eq(612)
    canvas.height.should eq(792)

    # Centre du rectangle vert (100,100) en pt ; y device = 792 - 100.
    px = canvas.pixels[100, 792 - 100]
    {px.r >> 8, px.g >> 8, px.b >> 8}.should eq({0, 255, 0})
  end
end
