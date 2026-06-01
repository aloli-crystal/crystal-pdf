module PDF
  module ColorSpaces
    # ICCBased colour space (PDF spec § 8.6.5.5). Embeds an ICC
    # profile inside a stream object so colours referenced by this
    # space are interpreted with calibrated meaning rather than the
    # uncalibrated device defaults (`DeviceRGB`, `DeviceCMYK`,
    # `DeviceGray`).
    #
    # An `ICCBased` is what an `OutputIntent` references through its
    # `/DestOutputProfile` entry, and what PDF/A-2b/3b requires for
    # any non-DeviceGray content.
    #
    # ## Components and ranges
    #
    # The PDF dict `/N` entry declares how many channels the profile
    # uses — 1 (Gray), 3 (RGB / Lab), or 4 (CMYK). The shard reads
    # this from the ICC header (bytes 16-19 contain the colour space
    # signature like `"RGB "`, `"GRAY"`, `"CMYK"`).
    #
    # ## Factory methods
    #
    # ```
    # # Default sRGB v4 embedded in the shard
    # icc = PDF::ColorSpaces::ICCBased.srgb_v4
    #
    # # Default European CMYK (Coated FOGRA39 / ISOcoated_v2_eci)
    # icc = PDF::ColorSpaces::ICCBased.fogra39
    #
    # # Custom profile from a path
    # icc = PDF::ColorSpaces::ICCBased.from_file("/path/to/profile.icc")
    #
    # # Custom profile from bytes
    # icc = PDF::ColorSpaces::ICCBased.new(File.read("...").to_slice)
    # ```
    class ICCBased
      # Bundled sRGB v4 profile (ICC release 2007-07-25, CC0).
      SRGB_V4_PATH = "#{__DIR__}/../data/icc/sRGB_v4_ICC_preference.icc"

      # Bundled CMYK profile : Coated FOGRA39 / ISOcoated_v2_eci
      # (ECI release 2009, free for use).
      FOGRA39_PATH = "#{__DIR__}/../data/icc/ISOcoated_v2_eci.icc"

      # Raw ICC profile bytes (will be written as the stream payload).
      getter data : Bytes

      # Number of components — 1, 3 or 4. Inferred from the ICC
      # header at construction time.
      getter num_components : Int32

      # Default range array (`[0 1 0 1 ...]`) for each component.
      # Override only if a custom profile needs Lab-style ranges.
      property range : Array(Float64)?

      def initialize(@data : Bytes, range : Array(Float64)? = nil)
        @num_components = read_component_count(@data)
        @range = range
      end

      # Loads an ICC profile from a path on disk.
      def self.from_file(path : String) : ICCBased
        new(File.read(path).to_slice)
      end

      # Returns the bundled sRGB v4 ICC profile.
      def self.srgb_v4 : ICCBased
        from_file(SRGB_V4_PATH)
      end

      # Returns the bundled FOGRA39 CMYK ICC profile.
      def self.fogra39 : ICCBased
        from_file(FOGRA39_PATH)
      end

      # Builds the stream object representing this ICC profile.
      # Caller is responsible for `Document#register_object` to get
      # an indirect reference.
      def to_stream : Objects::Stream
        stream = Objects::Stream.new
        stream["N"] = Objects::Number.new(@num_components)
        if r = @range
          arr = Objects::Array.new
          r.each { |v| arr << Objects::Number.new(v) }
          stream["Range"] = arr
        end
        stream.data = @data
        stream.add_filter(Filters::Flate.new)
        stream
      end

      # Builds the colour-space reference array as it should appear
      # in the page resources — `[/ICCBased <ref>]`.
      def to_colour_space(profile_ref : Objects::Reference) : Objects::Array
        arr = Objects::Array.new
        arr << Objects::Name.new("ICCBased")
        arr << profile_ref
        arr
      end

      # Reads the colour-space signature from the ICC profile header
      # (bytes 16-19, fixed offset per ICC.1:2010). Maps it to the
      # number of components.
      #
      # Recognised signatures (ICC.1:2010 § 7.2.6) :
      # `"GRAY"` → 1, `"RGB "` / `"Lab "` / `"XYZ "` → 3,
      # `"CMYK"` → 4. Anything else raises.
      private def read_component_count(bytes : Bytes) : Int32
        raise ArgumentError.new("ICC profile too small (#{bytes.size} bytes) to contain a header") if bytes.size < 128
        sig = String.new(bytes[16, 4])
        case sig
        when "GRAY"                 then 1
        when "RGB ", "Lab ", "XYZ " then 3
        when "CMYK"                 then 4
        else
          raise ArgumentError.new("Unknown ICC colour-space signature #{sig.inspect} at byte 16 of profile header")
        end
      end
    end
  end
end
