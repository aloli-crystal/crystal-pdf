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

describe "PDF::Raster — rendu d'images" do
  it "composite une image JPEG embarquée (DCTDecode)" do
    pdf = PDF::Document.new
    jpeg = PDF::Images::JPEG.load("spec/fixtures/images/test_rgb.jpg")
    pdf.page do |p|
      p.image(jpeg, at: {100, 600}, width: 120, height: 120)
    end
    reader = PDF::Reader.open(IO::Memory.new(pdf.to_slice))
    canvas = PDF::Raster.render_page(reader, 0, dpi: 72)

    # Des pixels colorés (non gris) apparaissent dans la zone de l'image.
    colored = 0
    (140..240).each do |y|
      (110..210).each do |x|
        px = canvas.pixels[x, y]
        r, g, b = (px.r >> 8).to_i, (px.g >> 8).to_i, (px.b >> 8).to_i
        colored += 1 if (r - b).abs > 40
      end
    end
    colored.should be > 100

    # Hors image : blanc.
    empty = canvas.pixels[450, 300]
    {empty.r >> 8, empty.g >> 8, empty.b >> 8}.should eq({255, 255, 255})
  end

  it "composite une image PNG embarquée (FlateDecode RGB)" do
    pdf = PDF::Document.new
    png = PDF::Images::PNG.load("spec/fixtures/images/test_rgb.png")
    pdf.page do |p|
      p.image(png, at: {100, 600}, width: 120, height: 120)
    end
    reader = PDF::Reader.open(IO::Memory.new(pdf.to_slice))
    canvas = PDF::Raster.render_page(reader, 0, dpi: 72)

    colored = 0
    (140..240).each do |y|
      (110..210).each do |x|
        px = canvas.pixels[x, y]
        r, b = (px.r >> 8).to_i, (px.b >> 8).to_i
        colored += 1 if (r - b).abs > 40
      end
    end
    colored.should be > 100
  end
end

describe "PDF::Raster — détourage (W/W*)" do
  it "confine la peinture au rectangle de clip" do
    canvas = PDF::Raster::Canvas.new(400, 400)
    base = PDF::Raster::Matrix.new(1.0, 0.0, 0.0, -1.0, 0.0, 400.0)
    interp = PDF::Raster::Interpreter.new(canvas, base)
    # Clip [100,300]², puis remplit tout en rouge.
    interp.run("q 100 100 200 200 re W n 1 0 0 rg 0 0 600 600 re f Q".to_slice)

    inside = canvas.pixels[200, 200]
    {inside.r >> 8, inside.g >> 8, inside.b >> 8}.should eq({255, 0, 0})
    outside = canvas.pixels[40, 40]
    {outside.r >> 8, outside.g >> 8, outside.b >> 8}.should eq({255, 255, 255})
  end

  it "détoure exactement une forme non rectangulaire (masque)" do
    canvas = PDF::Raster::Canvas.new(400, 400)
    base = PDF::Raster::Matrix.new(1.0, 0.0, 0.0, -1.0, 0.0, 400.0)
    interp = PDF::Raster::Interpreter.new(canvas, base)
    # Clip à un triangle, puis remplit tout en rouge.
    interp.run("100 100 m 300 100 l 100 300 l h W n 1 0 0 rg 0 0 600 600 re f".to_slice)

    # Dans le triangle (pt 150,150 ; x+y<400) → rouge.
    inside = canvas.pixels[150, 250]
    inside.r.should eq(UInt16::MAX)
    # Dans la bbox mais HORS triangle (pt 250,250 ; x+y>400) → blanc :
    # c'est la preuve du détourage exact (vs boîte englobante).
    out = canvas.pixels[250, 150]
    {out.r >> 8, out.g >> 8, out.b >> 8}.should eq({255, 255, 255})
  end
end

describe "PDF::Raster — masque doux (/SMask)" do
  it "composite une image RGBA en laissant transparaître le fond" do
    pdf = PDF::Document.new
    png = PDF::Images::PNG.load("spec/fixtures/images/test_rgba.png")
    pdf.page do |p|
      p.fill_color("00FF00")
      p.rectangle(0, 0, 612, 792)
      p.fill
      p.image(png, at: {100, 500}, width: 200, height: 200)
    end
    reader = PDF::Reader.open(IO::Memory.new(pdf.to_slice))
    canvas = PDF::Raster.render_page(reader, 0, dpi: 72)

    # Dans la zone de l'image, le fond vert reste visible là où l'alpha
    # est faible (bords du dégradé).
    green = 0
    (280..420).each do |y|
      (100..300).each do |x|
        px = canvas.pixels[x, y]
        green += 1 if (px.g >> 8) > 200 && (px.r >> 8) < 100 && (px.b >> 8) < 100
      end
    end
    green.should be > 1000
  end
end

describe "PDF::Raster — traits tiretés (d)" do
  it "rend un trait tireté (alternance plein/vide)" do
    canvas = PDF::Raster::Canvas.new(400, 200)
    base = PDF::Raster::Matrix.new(1.0, 0.0, 0.0, -1.0, 0.0, 200.0)
    interp = PDF::Raster::Interpreter.new(canvas, base)
    interp.run("[10 6] 0 d 6 w 0 0 0 RG 20 100 m 380 100 l S".to_slice)

    # Le long du trait, on doit trouver de nombreuses transitions
    # noir↔blanc (les tirets) — un trait plein n'en aurait que 2.
    transitions = 0
    prev = 255
    (20..380).each do |x|
      cur = (canvas.pixels[x, 100].r >> 8) < 128 ? 0 : 255
      transitions += 1 if cur != prev
      prev = cur
    end
    transitions.should be > 6
  end
end

describe "PDF::Raster::Canvas#downsample" do
  it "moyenne les blocs (un noir + trois blancs → gris ~191)" do
    c = PDF::Raster::Canvas.new(2, 2)
    c.pixels[0, 0] = StumpyCore::RGBA.new(0_u16, 0_u16, 0_u16, UInt16::MAX)
    # les 3 autres restent blancs (fond)
    d = c.downsample(2)
    d.width.should eq(1)
    d.height.should eq(1)
    g = d.pixels[0, 0].r >> 8
    g.should be_close(191, 2) # (0 + 255*3) / 4 ≈ 191
  end
end

describe "PDF::Raster — anti-aliasing (supersampling)" do
  it "conserve les dimensions cibles et lisse les bords" do
    # Un triangle : son hypoténuse diagonale crée une couverture
    # partielle des pixels, donc des gris intermédiaires après réduction.
    pdf = PDF::Document.new
    pdf.page do |p|
      p.fill_color("000000")
      p.move_to(100, 100)
      p.line_to(300, 100)
      p.line_to(100, 300)
      p.fill
    end
    reader = PDF::Reader.open(IO::Memory.new(pdf.to_slice))
    canvas = PDF::Raster.render_page(reader, 0, dpi: 72, supersample: 3)

    # supersample ne change pas les dimensions finales.
    canvas.width.should eq(612)
    canvas.height.should eq(792)

    # Des gris intermédiaires apparaissent (bords lissés), absents d'un
    # rendu purement noir/blanc.
    mid = 0
    canvas.height.times do |y|
      canvas.width.times do |x|
        g = canvas.pixels[x, y].r >> 8
        mid += 1 if g > 40 && g < 215
      end
    end
    mid.should be > 100
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
