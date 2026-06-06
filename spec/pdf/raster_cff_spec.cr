require "../spec_helper"

# Encode un entier d'opérande de charstring Type 2.
private def op_int(v : Int32) : Array(UInt8)
  if -107 <= v <= 107
    [(v + 139).to_u8]
  elsif 108 <= v <= 1131
    w = v - 108
    [(w // 256 + 247).to_u8, (w % 256).to_u8]
  elsif -1131 <= v <= -108
    w = -v - 108
    [(w // 256 + 251).to_u8, (w % 256).to_u8]
  else
    [28_u8, ((v >> 8) & 0xFF).to_u8, (v & 0xFF).to_u8]
  end
end

private def charstring(*ops) : Bytes
  bytes = [] of UInt8
  ops.each do |op|
    case op
    when Int32 then bytes.concat(op_int(op))
    when UInt8 then bytes << op
    end
  end
  Slice.new(bytes.to_unsafe, bytes.size).dup
end

describe PDF::Raster::CFFOutlines do
  describe ".run_charstring" do
    it "trace un carré via rmoveto + rlineto + endchar" do
      # 100 100 rmoveto 200 0 rlineto 0 200 rlineto -200 0 rlineto endchar
      cs = charstring(100, 100, 21_u8, 200, 0, 5_u8, 0, 200, 5_u8, -200, 0, 5_u8, 14_u8)
      contours, _ = PDF::Raster::CFFOutlines.run_charstring(cs)
      contours.size.should eq(1)
      pts = contours.first
      # Le contour part de (100,100) et passe par les coins du carré.
      pts.first.should eq({100.0, 100.0})
      pts.any? { |p| p == {300.0, 100.0} }.should be_true
      pts.any? { |p| p == {300.0, 300.0} }.should be_true
    end

    it "récupère la chasse (largeur) en tête du premier opérateur" do
      # 555 (width) 0 700 hmoveto … endchar  → hmoveto attend 1 arg,
      # ici 3 sur la pile → le 1er est la chasse (nominal + 555).
      cs = charstring(555, 0, 700, 22_u8, 14_u8)
      _, width = PDF::Raster::CFFOutlines.run_charstring(cs, nominal_width: 10.0)
      width.should eq(565.0) # 10 (nominal) + 555
    end

    it "interprète une courbe rrcurveto (génère des points lissés)" do
      # 0 0 rmoveto 100 100 100 -100 100 0 rrcurveto endchar
      cs = charstring(0, 0, 21_u8, 100, 100, 100, -100, 100, 0, 8_u8, 14_u8)
      contours, _ = PDF::Raster::CFFOutlines.run_charstring(cs)
      contours.size.should eq(1)
      contours.first.size.should be > 3 # courbe aplatie en segments
    end
  end
end
