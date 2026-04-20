module PDF
  # Gradient support for PDF documents.
  #
  # Implements linear (axial) and radial gradients using PDF Shading
  # dictionaries with Type 2 (exponential interpolation) functions.
  module Gradient
    # A color stop in a gradient
    struct ColorStop
      getter position : Float64
      getter color : Tuple(Float64, Float64, Float64)

      def initialize(@position : Float64, @color : Tuple(Float64, Float64, Float64))
      end
    end

    # Creates PDF objects for a linear (axial) gradient.
    #
    # Returns a shading pattern dictionary that can be used with
    # the Pattern color space.
    def self.linear(
      x1 : Number, y1 : Number,
      x2 : Number, y2 : Number,
      color1 : Tuple(Float64, Float64, Float64),
      color2 : Tuple(Float64, Float64, Float64),
      document : Document,
    ) : Objects::Indirect
      build_gradient(:axial, x1, y1, x2, y2, 0, 0, color1, color2, document)
    end

    # Creates PDF objects for a radial gradient.
    #
    # The gradient goes from a circle centered at (cx1, cy1) with radius r1
    # to a circle centered at (cx2, cy2) with radius r2.
    def self.radial(
      cx1 : Number, cy1 : Number, r1 : Number,
      cx2 : Number, cy2 : Number, r2 : Number,
      color1 : Tuple(Float64, Float64, Float64),
      color2 : Tuple(Float64, Float64, Float64),
      document : Document,
    ) : Objects::Indirect
      build_gradient(:radial, cx1, cy1, cx2, cy2, r1, r2, color1, color2, document)
    end

    # Simpler radial gradient: same center, radius 0 to r
    def self.radial(
      cx : Number, cy : Number, r : Number,
      color1 : Tuple(Float64, Float64, Float64),
      color2 : Tuple(Float64, Float64, Float64),
      document : Document,
    ) : Objects::Indirect
      radial(cx, cy, 0, cx, cy, r, color1, color2, document)
    end

    private def self.build_gradient(
      type : Symbol,
      x1 : Number, y1 : Number,
      x2 : Number, y2 : Number,
      r1 : Number, r2 : Number,
      color1 : Tuple(Float64, Float64, Float64),
      color2 : Tuple(Float64, Float64, Float64),
      document : Document,
    ) : Objects::Indirect
      # Create the interpolation function (Type 2 = exponential)
      func_dict = Objects::Dictionary.new
      func_dict["FunctionType"] = Objects::Number.new(2)

      domain = Objects::Array.new
      domain << Objects::Number.new(0.0)
      domain << Objects::Number.new(1.0)
      func_dict["Domain"] = domain

      c0 = Objects::Array.new
      c0 << Objects::Number.new(color1[0])
      c0 << Objects::Number.new(color1[1])
      c0 << Objects::Number.new(color1[2])
      func_dict["C0"] = c0

      c1 = Objects::Array.new
      c1 << Objects::Number.new(color2[0])
      c1 << Objects::Number.new(color2[1])
      c1 << Objects::Number.new(color2[2])
      func_dict["C1"] = c1

      func_dict["N"] = Objects::Number.new(1.0)
      func_obj = document.register_object(func_dict)

      # Create the shading dictionary
      shading_dict = Objects::Dictionary.new
      shading_dict["ShadingType"] = Objects::Number.new(type == :axial ? 2 : 3)
      shading_dict["ColorSpace"] = Objects::Name.new("DeviceRGB")

      coords = Objects::Array.new
      if type == :axial
        coords << Objects::Number.new(x1.to_f)
        coords << Objects::Number.new(y1.to_f)
        coords << Objects::Number.new(x2.to_f)
        coords << Objects::Number.new(y2.to_f)
      else
        coords << Objects::Number.new(x1.to_f)
        coords << Objects::Number.new(y1.to_f)
        coords << Objects::Number.new(r1.to_f)
        coords << Objects::Number.new(x2.to_f)
        coords << Objects::Number.new(y2.to_f)
        coords << Objects::Number.new(r2.to_f)
      end
      shading_dict["Coords"] = coords
      shading_dict["Function"] = func_obj.reference

      extend_arr = Objects::Array.new
      extend_arr << Objects::Boolean.new(true)
      extend_arr << Objects::Boolean.new(true)
      shading_dict["Extend"] = extend_arr

      shading_obj = document.register_object(shading_dict)

      # Create the pattern dictionary
      pattern_dict = Objects::Dictionary.new
      pattern_dict["Type"] = Objects::Name.new("Pattern")
      pattern_dict["PatternType"] = Objects::Number.new(2)
      pattern_dict["Shading"] = shading_obj.reference

      document.register_object(pattern_dict)
    end
  end
end
