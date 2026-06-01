module PDF
  module ColorSpaces
    # Separation colour space (PDF spec § 8.6.6.4) — one *spot*
    # colour with an alternate fallback for viewers that lack the
    # physical ink.
    #
    # A Separation is rendered as the PDF array
    # `[/Separation /<name> <alternate> <tintTransform>]` where :
    # * `/<name>` is a custom name like `/Pantone#20185#20C` (PDF
    #   name encoding ; spaces become `#20`).
    # * `<alternate>` is an ICCBased reference (CMYK or RGB) that
    #   defines how to approximate the spot ink.
    # * `<tintTransform>` is a Type 2 exponential interpolation
    #   function `f(t) = lerp(C0, C1, t)` from `t=0` (paper white)
    #   to `t=1` (full ink).
    #
    # ## Convenience constructors
    #
    # ```
    # # Pantone 185 C on a FOGRA39 fallback (approximate CMYK).
    # pantone185 = PDF::ColorSpaces::Separation.new(
    #   name: "Pantone 185 C",
    #   alternate: PDF::ColorSpaces::ICCBased.fogra39,
    #   c1: [0.0, 1.0, 0.7, 0.0], # CMYK approximation
    # )
    # ```
    class Separation
      # Pretty-printable colour name (without `/`). Will be PDF-name
      # encoded at serialization.
      getter name : String

      # ICC fallback (3 or 4 components — RGB or CMYK).
      getter alternate : ICCBased

      # `C0` (paper white) and `C1` (full ink) tint values in the
      # alternate colour space's coordinates. Length must match
      # `alternate.num_components`.
      getter c0 : Array(Float64)
      getter c1 : Array(Float64)

      def initialize(
        *,
        @name : String,
        @alternate : ICCBased,
        c1 : Array(Float64),
        c0 : Array(Float64)? = nil,
      )
        @c1 = c1
        @c0 = c0 || Array(Float64).new(@alternate.num_components, 0.0)
        unless @c0.size == @alternate.num_components && @c1.size == @alternate.num_components
          raise ArgumentError.new("Separation '#{@name}' : c0/c1 must have #{@alternate.num_components} components (alternate is #{@alternate.num_components}-channel)")
        end
      end

      # Builds the colour-space array given an already-registered
      # ICC profile reference.
      def to_array(alternate_ref : Objects::Reference) : Objects::Array
        arr = Objects::Array.new
        arr << Objects::Name.new("Separation")
        arr << Objects::Name.new(@name)
        arr << ColorSpaces.icc_based_space(alternate_ref)
        arr << build_tint_transform
        arr
      end

      # The Type-2 exponential function that maps the tint scalar
      # `t ∈ [0, 1]` to the alternate-space colour vector.
      private def build_tint_transform : Objects::Dictionary
        f = Objects::Dictionary.new
        f["FunctionType"] = Objects::Number.new(2)
        domain = Objects::Array.new
        domain << Objects::Number.new(0)
        domain << Objects::Number.new(1)
        f["Domain"] = domain

        c0 = Objects::Array.new
        @c0.each { |v| c0 << Objects::Number.new(v) }
        f["C0"] = c0

        c1 = Objects::Array.new
        @c1.each { |v| c1 << Objects::Number.new(v) }
        f["C1"] = c1

        f["N"] = Objects::Number.new(1) # linear interpolation
        f
      end
    end

    # Shared helper : builds the inline `[/ICCBased <ref>]` array
    # reused by Separation, DeviceN and Document#attach_file output
    # intents.
    def self.icc_based_space(profile_ref : Objects::Reference) : Objects::Array
      arr = Objects::Array.new
      arr << Objects::Name.new("ICCBased")
      arr << profile_ref
      arr
    end
  end
end
