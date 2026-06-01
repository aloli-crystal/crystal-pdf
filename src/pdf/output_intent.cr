module PDF
  # `OutputIntent` dictionary entry (PDF spec § 14.11.5) — declares
  # the colour reproduction characteristics of the production device
  # the document was targeted at.
  #
  # Required for PDF/A-2b, PDF/A-3 and PDF/X conformance. For plain
  # PDF 1.7 it is optional but recommended : it lets viewers and
  # printers apply colour management consistently.
  #
  # ## Subtype `/S`
  #
  # PDF supports three subtypes :
  #
  # * `GTS_PDFA1` — PDF/A (all parts, all conformance levels)
  # * `GTS_PDFX`  — PDF/X
  # * `ISO_PDFE1` — PDF/E
  #
  # The PDF/A subtype is what ALOLI ships in J3+ via `pdf-a`. The
  # other two are out of ALOLI scope (cf. RATIONALE).
  #
  # ## Factory methods
  #
  # ```
  # # sRGB v4 output intent for a PDF/A-2b document
  # doc.output_intent = PDF::OutputIntent.srgb
  #
  # # CMYK FOGRA39 output intent
  # doc.output_intent = PDF::OutputIntent.fogra39
  #
  # # Custom — bring your own ICC profile
  # doc.output_intent = PDF::OutputIntent.new(
  #   subtype: :gts_pdfa1,
  #   output_condition_identifier: "Custom CMYK",
  #   registry_name: "https://example.com",
  #   info: "Custom press profile",
  #   dest_output_profile: PDF::ColorSpaces::ICCBased.from_file("press.icc"),
  # )
  # ```
  class OutputIntent
    # The /S subtype name. Default `GTS_PDFA1` (the most useful for
    # ALOLI's archival trajectory).
    getter subtype : String

    # /OutputConditionIdentifier (required, name of the condition).
    getter output_condition_identifier : String

    # /RegistryName (optional, URL of the registry where the
    # condition is defined — e.g. "http://www.color.org").
    getter registry_name : String?

    # /Info (optional, human-readable description).
    getter info : String?

    # /OutputCondition (optional, human-readable name of the
    # intended output device).
    getter output_condition : String?

    # /DestOutputProfile — the ICC profile that defines the colour
    # space the document targets.
    getter dest_output_profile : ColorSpaces::ICCBased

    def initialize(
      *,
      subtype : Symbol | String = :gts_pdfa1,
      @output_condition_identifier : String,
      @dest_output_profile : ColorSpaces::ICCBased,
      @registry_name : String? = nil,
      @info : String? = nil,
      @output_condition : String? = nil,
    )
      @subtype = case subtype
                 in Symbol then symbol_to_subtype(subtype)
                 in String then subtype
                 end
    end

    # sRGB v4 output intent. Suitable for any RGB document, including
    # PDF/A-2b/3b. References the bundled sRGB v4 profile.
    def self.srgb : OutputIntent
      new(
        output_condition_identifier: "sRGB",
        registry_name: "http://www.color.org",
        info: "sRGB v4 ICC preference (perceptual)",
        output_condition: "sRGB IEC61966-2-1:1999",
        dest_output_profile: ColorSpaces::ICCBased.srgb_v4,
      )
    end

    # FOGRA39 (Coated, ISOcoated_v2_eci) output intent. Suitable for
    # European offset CMYK workflows. References the bundled
    # ISOcoated_v2_eci profile.
    def self.fogra39 : OutputIntent
      new(
        output_condition_identifier: "FOGRA39",
        registry_name: "http://www.color.org",
        info: "Coated FOGRA39 (ISO 12647-2:2004) — ECI",
        output_condition: "ISO Coated v2 (ECI)",
        dest_output_profile: ColorSpaces::ICCBased.fogra39,
      )
    end

    # Builds the PDF dictionary for this output intent. Caller must
    # register the profile stream first and pass its reference.
    def to_dictionary(profile_ref : Objects::Reference) : Objects::Dictionary
      d = Objects::Dictionary.new
      d["Type"] = Objects::Name.new("OutputIntent")
      d["S"] = Objects::Name.new(@subtype)
      d["OutputConditionIdentifier"] = Objects::Str.new(@output_condition_identifier)
      if rn = @registry_name
        d["RegistryName"] = Objects::Str.new(rn)
      end
      if i = @info
        d["Info"] = Objects::Str.unicode(i)
      end
      if oc = @output_condition
        d["OutputCondition"] = Objects::Str.unicode(oc)
      end
      d["DestOutputProfile"] = profile_ref
      d
    end

    private def symbol_to_subtype(s : Symbol) : String
      case s
      when :gts_pdfa1 then "GTS_PDFA1"
      when :gts_pdfx  then "GTS_PDFX"
      when :iso_pdfe1 then "ISO_PDFE1"
      else
        raise ArgumentError.new("Unknown OutputIntent subtype #{s.inspect} (expected :gts_pdfa1, :gts_pdfx, or :iso_pdfe1)")
      end
    end
  end
end
